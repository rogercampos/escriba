# frozen_string_literal: true

require "json"
require "json_schemer"

module Escriba
  # Reconciles an LLM's JSON reply (produced from a TranslationPrompt) against the
  # stored translations. Parsing is tolerant of the noise chat models add (code
  # fences, surrounding prose), then the payload is validated against
  # TranslationSchema — the same schema that was embedded in the prompt — before
  # it is reconciled via TranslationReconciler (shared with the CSV importer).
  #
  # The reply is self-describing: each item carries its own `locale`, so no locale
  # has to be chosen at paste time.
  class TranslationJsonImporter
    MAX_ERRORS = 20

    def initialize(text, locales:, dev_locale:)
      @text = text.to_s
      @locales = locales.map(&:to_sym)
      @dev_index = Escriba::DevIndex.new(dev_locale)
    end

    # Human-readable parse/schema errors (capped). Empty when the payload is good.
    def errors
      parse_and_validate
      @errors
    end

    def valid?
      errors.empty?
    end

    def detected_locales
      return [] unless valid?

      data.map { |item| item["locale"].to_sym }.uniq
    end

    def operations
      reconciler.operations
    end

    def summary
      reconciler.summary
    end

    def apply!
      reconciler.apply!
    end

    private

    def reconciler
      @reconciler ||= Escriba::TranslationReconciler.new(valid? ? build_proposals : [])
    end

    def build_proposals
      data.filter_map do |item|
        locale = item["locale"].to_sym
        next unless @locales.include?(locale)

        dev = @dev_index.resolve(key: item["key"], source: nil)
        if dev
          { dev: dev, locale: locale.to_s, value: item["translation"] }
        else
          { dev: nil, key: item["key"], source: nil }
        end
      end
    end

    def data
      parse_and_validate
      @data || []
    end

    def parse_and_validate
      return if @parsed

      @parsed = true
      @errors = []

      json = extract_json(@text)
      if json.nil?
        @errors << "Couldn't find a JSON array in the pasted text."
        return
      end

      begin
        parsed = JSON.parse(json)
      rescue JSON::ParserError => e
        @errors << "Invalid JSON: #{e.message}"
        return
      end

      schema_errors = schemer.validate(parsed).first(MAX_ERRORS).map { |err| format_error(err) }
      if schema_errors.any?
        @errors.concat(schema_errors)
        return
      end

      @data = parsed
    end

    def schemer
      @schemer ||= JSONSchemer.schema(Escriba::TranslationSchema.for(locales: @locales))
    end

    # Pull a JSON array out of free-form LLM output: a clean payload as-is, else
    # the contents of a ``` fence, else the text between the outermost brackets.
    def extract_json(text)
      stripped = text.strip
      return stripped if stripped.start_with?("[")

      if (fenced = stripped[/```(?:json)?\s*(.+?)```/m, 1])
        fenced = fenced.strip
        return fenced if fenced.start_with?("[")
      end

      open = stripped.index("[")
      close = stripped.rindex("]")
      return stripped[open..close] if open && close && close > open

      nil
    end

    def format_error(err)
      pointer = err["data_pointer"].to_s
      where = pointer.empty? ? "the root array" : "item #{pointer}"
      detail = err["error"] || "failed #{err['type']} validation"
      "#{where}: #{detail}"
    end
  end
end
