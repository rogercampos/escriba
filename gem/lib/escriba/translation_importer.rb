# frozen_string_literal: true

require "csv"

module Escriba
  # Parses a CSV produced by TranslationExporter (or hand-authored in the same
  # shape) and reconciles it against the stored translations.
  #
  # The target locales are auto-detected from the header: any column named after
  # an importable locale (e.g. "es", "it") is a value column, so a single file
  # can carry several locales at once — exactly what the "All locales" export
  # produces. The fixed columns key/plural_form/source/meaning are never treated
  # as values.
  #
  # It is split in two phases so the admin UI can show a dry-run preview before
  # writing anything:
  #
  #   * #operations - pure analysis: classifies every (locale, string) as
  #     :create, :overwrite, :unchanged, :invalid, or a row as :unmatched. Each
  #     create/overwrite is linted with Escriba::TranslationValidator against the
  #     source string; a value with error-level issues (e.g. broken
  #     interpolations) is downgraded to :invalid so it is never written. No
  #     writes happen here.
  #   * #apply!     - persists the :create and :overwrite operations in a single
  #     transaction (skipping :invalid), seeding source metadata from the
  #     dev-locale row exactly the way the per-string edit form does.
  #
  # Rows are matched to a known string by Escriba key first (the stable
  # identifier, always present in exports) and fall back to an exact source-copy
  # match for singular strings (a convenience for hand-authored files). Blank
  # value cells are skipped — an import never clears an existing translation.
  class TranslationImporter
    Operation = Struct.new(:key, :locale, :source, :status, :old_value, :new_value, :plural, :issues,
      keyword_init: true)

    KEY_RE = /\A[a-f0-9]{16}\z/
    BASE_COLUMNS = %w[key plural_form source meaning].freeze

    # csv        - the raw CSV text
    # locales    - the importable (non-dev) locales; the header columns matching
    #              these are imported
    # dev_locale - the source locale (defines which strings exist)
    def initialize(csv, locales:, dev_locale:)
      @csv = csv
      @locales = locales.map(&:to_sym)
      @dev_locale = dev_locale.to_sym
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
      @operations ||= build_operations
    end

    def summary
      operations.each_with_object(Hash.new(0)) { |op, acc| acc[op.status] += 1 }
    end

    def apply!
      created = 0
      updated = 0
      Escriba::Translation.transaction do
        operations.each do |op|
          next unless %i[create overwrite].include?(op.status)

          write(op)
          op.status == :create ? created += 1 : updated += 1
        end
      end
      { created: created, updated: updated }
    end

    private

    def write(op)
      dev = dev_by_key[op.key]
      row = Escriba::Translation.find_or_initialize_by(key: op.key, locale: op.locale)
      row.source_copy = dev.source_copy
      row.meaning = dev.meaning
      row.interpolation_names = dev.interpolation_names
      row.plural = dev.plural
      row.value = op.new_value
      row.save!
    end

    def build_operations
      # matched[locale][key] = { dev:, forms: {form => cell}, single: cell }
      matched = Hash.new { |h, loc| h[loc] = {} }
      unmatched = {} # key||source => Operation (reported once, locale-agnostic)

      table.each do |csv_row|
        dev = resolve_dev(csv_row)
        unless dev
          id = csv_row["key"].to_s.strip
          id = csv_row["source"].to_s if id.empty?
          unmatched[id] ||= Operation.new(
            key: csv_row["key"], locale: nil, source: csv_row["source"],
            status: :unmatched, old_value: nil, new_value: nil, plural: false, issues: []
          )
          next
        end

        value_columns.each { |locale| accumulate(matched[locale], dev, csv_row, locale) }
      end

      existing = load_existing(matched)
      ops = matched.flat_map do |locale, by_key|
        by_key.filter_map { |key, bucket| operation_for(locale, key, bucket, existing.dig(locale, key)) }
      end
      ops + unmatched.values
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

    def load_existing(matched)
      result = Hash.new { |h, loc| h[loc] = {} }
      matched.each do |locale, by_key|
        Escriba::Translation.for_locale(locale).where(key: by_key.keys).each do |row|
          result[locale][row.key] = row
        end
      end
      result
    end

    def operation_for(locale, key, bucket, existing)
      dev = bucket[:dev]
      new_value = dev.plural ? bucket[:forms].reject { |_, v| blank?(v) } : bucket[:single]

      # Blank input leaves the existing value untouched — emit no operation.
      return nil if dev.plural ? new_value.empty? : blank?(new_value)

      old_value = existing&.value
      status =
        if blank_value?(old_value, dev.plural)
          :create
        elsif values_equal?(old_value, new_value, dev.plural)
          :unchanged
        else
          :overwrite
        end

      # Lint values we are about to write. Error-level issues (broken/missing
      # interpolations, a missing required plural form) downgrade the row to
      # :invalid so apply! skips it — an import must not introduce a translation
      # the Issues page would immediately flag.
      issues = []
      if %i[create overwrite].include?(status)
        issues = lint(dev, new_value)
        status = :invalid if issues.any? { |i| Escriba::TranslationValidator::ERROR_CODES.include?(i.code) }
      end

      Operation.new(key: key, locale: locale, source: source_text(dev), status: status,
        old_value: old_value, new_value: new_value, plural: dev.plural, issues: issues)
    end

    def lint(dev, new_value)
      Escriba::TranslationValidator.call(
        value: new_value,
        source_copy: dev.source_copy,
        source_interpolations: dev.interpolation_names,
        plural: dev.plural,
      )
    end

    def resolve_dev(csv_row)
      key = csv_row["key"].to_s.strip
      return dev_by_key[key] if key.match?(KEY_RE) && dev_by_key[key]

      source = csv_row["source"].to_s
      return nil if source.empty?

      dev_by_source[source]
    end

    def values_equal?(old_value, new_value, plural)
      if plural
        normalize_plural(old_value) == new_value
      else
        old_value.to_s == new_value.to_s
      end
    end

    def blank_value?(value, plural)
      return true if value.nil?

      plural ? normalize_plural(value).empty? : value.to_s.strip.empty?
    end

    def normalize_plural(value)
      return {} unless value.is_a?(Hash)

      value.transform_keys(&:to_s).reject { |_, v| blank?(v) }
    end

    def source_text(dev)
      source = dev.source_copy
      if dev.plural && source.is_a?(Hash)
        source.map { |k, v| "#{k}: #{v}" }.join(" · ")
      else
        source.to_s
      end
    end

    def blank?(value)
      value.to_s.strip.empty?
    end

    def table
      @table ||= CSV.parse(@csv.to_s, headers: true)
    end

    def dev_rows
      @dev_rows ||= Escriba::Translation.for_locale(@dev_locale).to_a
    end

    def dev_by_key
      @dev_by_key ||= dev_rows.index_by(&:key)
    end

    # Singular dev strings keyed by their source copy, for source-based matching.
    def dev_by_source
      @dev_by_source ||= dev_rows.reject(&:plural).index_by { |d| d.source_copy.to_s }
    end
  end
end
