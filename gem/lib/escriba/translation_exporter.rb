# frozen_string_literal: true

require "csv"

module Escriba
  # Serializes translations to a flat CSV for hand-off to a translator or
  # service. One row per (string, plural form):
  #
  #   key, plural_form, source, meaning, <locale>[, <locale>...]
  #
  # `locale` is either a single locale (one value column, named after it) or
  # :all (one value column per exported locale — a wide format a translator can
  # fill across locales). Plural strings expand to one row per CLDR form present
  # in the source. TranslationImporter is the inverse.
  class TranslationExporter
    BASE_HEADER = %w[key plural_form source meaning].freeze

    def self.call(...)
      new(...).to_csv
    end

    # locale       - a single locale (symbol/string) or :all / "all"
    # dev_locale   - the source locale (its rows define which strings exist)
    # locales      - all exportable (non-dev) locales; used when locale == :all
    # only_missing - skip strings already translated in every exported locale
    def initialize(locale:, dev_locale:, locales:, only_missing: false)
      @dev_locale = dev_locale.to_sym
      all = locale.to_s == "all"
      @locales = (all ? locales : [locale]).map(&:to_sym)
      @only_missing = only_missing
    end

    def to_csv
      dev_rows = Escriba::Translation.for_locale(@dev_locale).order(:source_copy).to_a
      values = values_by_locale(dev_rows.map(&:key))

      CSV.generate do |csv|
        csv << BASE_HEADER + @locales.map(&:to_s)
        dev_rows.each do |dev|
          next if @only_missing && translated_in_all?(dev, values)

          emit_rows(csv, dev, values)
        end
      end
    end

    private

    def emit_rows(csv, dev, values)
      meaning = dev.meaning.to_s
      if dev.plural
        source = dev.source_copy.is_a?(Hash) ? dev.source_copy : {}
        source.each_key do |form|
          cells = @locales.map { |loc| plural_cell(values.dig(loc, dev.key), form) }
          csv << [dev.key, form, source[form], meaning, *cells]
        end
      else
        cells = @locales.map { |loc| singular_cell(values.dig(loc, dev.key)) }
        csv << [dev.key, nil, dev.source_copy.to_s, meaning, *cells]
      end
    end

    def singular_cell(row)
      v = row&.value
      v.is_a?(Hash) ? "" : v.to_s
    end

    def plural_cell(row, form)
      v = row&.value
      v.is_a?(Hash) ? v[form.to_s].to_s : ""
    end

    # { locale => { key => Translation } } for the target locales.
    def values_by_locale(keys)
      @locales.to_h do |loc|
        [loc, Escriba::Translation.where(locale: loc.to_s, key: keys).index_by(&:key)]
      end
    end

    def translated_in_all?(dev, values)
      @locales.all? { |loc| present_value?(values.dig(loc, dev.key), dev.plural) }
    end

    def present_value?(row, plural)
      return false unless row

      v = row.value
      if plural
        v.is_a?(Hash) && v.values.any? { |s| !s.to_s.strip.empty? }
      else
        !v.to_s.strip.empty?
      end
    end
  end
end
