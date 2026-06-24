# frozen_string_literal: true

module Escriba
  # Validates a translation's value against the source string it translates,
  # using only data already stored on the rows (interpolation shape, plural
  # flag, source copy). Pure and side-effect-free, so it is safe to run across
  # many rows (workspace lists, the Issues page, the dashboard).
  #
  # It deliberately does NOT try to compute the full set of CLDR plural
  # categories a locale requires (that needs CLDR data Escriba doesn't ship);
  # it only enforces the universally-required "other" form.
  class TranslationValidator
    Issue = Struct.new(:code, :message, keyword_init: true)

    # Order matters: severity classification reads these.
    ERROR_CODES = %i[unknown_interpolation missing_interpolation missing_plural_other].freeze
    WARNING_CODES = %i[missing].freeze

    def self.call(...)
      new(...).issues
    end

    # value                 - the translation: a String (singular) or a Hash of
    #                         CLDR plural forms (plural). Blank => missing.
    # source_copy           - the dev-locale source: String or Hash of forms.
    # source_interpolations - Array of interpolation names in the source. When
    #                         omitted it is derived from source_copy.
    # plural                - whether this is a plural string.
    def initialize(value:, source_copy:, source_interpolations: nil, plural: false)
      @value = value
      @source_copy = source_copy
      @plural = plural
      @source_interpolations = Array(source_interpolations || derive_source_interpolations).map(&:to_s)
    end

    def issues
      return [issue(:missing, "No translation yet.")] if blank_value?

      list = []
      list << issue(:missing_plural_other, %(Missing the required "other" plural form.)) if @plural && !present?(forms["other"])
      list.concat(interpolation_issues)
      list
    end

    def valid?
      issues.empty?
    end

    private

    def issue(code, message)
      Issue.new(code: code, message: message)
    end

    def blank_value?
      if @plural
        forms.values.none? { |v| present?(v) }
      else
        !present?(@value)
      end
    end

    def forms
      @forms ||= @value.is_a?(Hash) ? @value.transform_keys(&:to_s) : {}
    end

    def interpolation_issues
      out = []
      used = used_interpolations

      unknown = used - @source_interpolations
      out << issue(:unknown_interpolation, "Unknown interpolation #{format_vars(unknown)} — absent from the source string.") unless unknown.empty?

      # The "one" plural form legitimately drops %{count}, so a missing-variable
      # check is only meaningful for singular strings.
      unless @plural
        missing = @source_interpolations - used
        out << issue(:missing_interpolation, "Missing interpolation #{format_vars(missing)} from the source string.") unless missing.empty?
      end

      out
    end

    def used_interpolations
      texts = @plural ? forms.values : [@value]
      texts.compact.flat_map { |t| Escriba::KeyDeriver.interpolation_names(t.to_s) }.uniq
    end

    def derive_source_interpolations
      if @source_copy.is_a?(Hash)
        @source_copy.values.flat_map { |v| Escriba::KeyDeriver.interpolation_names(v.to_s) }.uniq
      else
        Escriba::KeyDeriver.interpolation_names(@source_copy.to_s)
      end
    end

    def present?(value)
      value.is_a?(String) ? !value.strip.empty? : !value.nil?
    end

    def format_vars(names)
      names.map { |n| "%{#{n}}" }.join(", ")
    end
  end
end
