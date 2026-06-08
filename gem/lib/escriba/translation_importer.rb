# frozen_string_literal: true

require "csv"

module Escriba
  # Parses a CSV produced by TranslationExporter (or hand-authored in the same
  # shape) into normalized proposals and reconciles them via
  # Escriba::TranslationReconciler.
  #
  # The target locales are auto-detected from the header: any column named after
  # an importable locale (e.g. "es", "it") is a value column, so a single file
  # can carry several locales at once — exactly what the "All locales" export
  # produces. The fixed columns key/plural_form/source/meaning are never treated
  # as values. Plural strings are grouped from their per-form rows back into a
  # single value Hash; blank cells are skipped so an import never clears a value.
  #
  # Classification, linting and writing live in TranslationReconciler (shared
  # with the JSON importer).
  class TranslationImporter
    def initialize(csv, locales:, dev_locale:)
      @csv = csv
      @locales = locales.map(&:to_sym)
      @dev_index = Escriba::DevIndex.new(dev_locale)
    end

    # Header columns that name an importable locale — the locales this file will
    # import into. Empty when the file names no recognizable locale column.
    def value_columns
      @value_columns ||= begin
        headers = table.headers.map(&:to_s)
        @locales.map(&:to_s).select { |loc| headers.include?(loc) }
      end
    end

    def detected_locales
      value_columns.map(&:to_sym)
    end

    def row_count
      table.size
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
      @reconciler ||= Escriba::TranslationReconciler.new(build_proposals)
    end

    def build_proposals
      # grouped[locale][dev.key] = { dev:, forms: {form => cell}, single: cell }
      grouped = Hash.new { |h, locale| h[locale] = {} }
      proposals = []

      table.each do |csv_row|
        dev = @dev_index.resolve(key: csv_row["key"], source: csv_row["source"])
        unless dev
          proposals << { dev: nil, key: csv_row["key"], source: csv_row["source"] }
          next
        end

        value_columns.each { |locale| accumulate(grouped[locale], dev, csv_row, locale) }
      end

      grouped.each do |locale, by_key|
        by_key.each_value do |bucket|
          value = bucket[:dev].plural ? bucket[:forms] : bucket[:single]
          proposals << { dev: bucket[:dev], locale: locale, value: value }
        end
      end

      proposals
    end

    def accumulate(by_key, dev, csv_row, locale)
      bucket = (by_key[dev.key] ||= { dev: dev, forms: {}, single: nil })
      cell = csv_row[locale].to_s
      if dev.plural
        form = csv_row["plural_form"].to_s.strip
        bucket[:forms][form] = cell unless form.empty?
      else
        bucket[:single] = cell
      end
    end

    def table
      @table ||= CSV.parse(@csv.to_s, headers: true)
    end
  end
end
