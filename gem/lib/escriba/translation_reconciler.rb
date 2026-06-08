# frozen_string_literal: true

module Escriba
  # The format-agnostic core of importing. Both the CSV and the JSON importers
  # parse their input into normalized *proposals* and hand them here; this class
  # classifies each one, lints the values it would write, and persists them.
  #
  # A proposal is a Hash:
  #   matched   -> { dev:, locale:, value: }   value is a String or plural Hash
  #   unmatched -> { dev: nil, key:, source: } the string is unknown
  #
  # It produces Operations (the dry-run preview reads these) and, on #apply!,
  # writes the :create / :overwrite ones in a single transaction. Values with
  # error-level lint issues (broken/missing interpolations, missing required
  # plural form) are downgraded to :invalid and never written — so an import,
  # whatever its source format, can't introduce a translation the Issues page
  # would immediately flag.
  class TranslationReconciler
    Operation = Struct.new(:key, :locale, :source, :status, :old_value, :new_value, :plural, :issues, :dev,
      keyword_init: true)

    def initialize(proposals)
      @proposals = proposals
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

    def build_operations
      matched = @proposals.select { |p| p[:dev] }
      existing = load_existing(matched)

      ops = matched.filter_map do |proposal|
        dev = proposal[:dev]
        operation_for(proposal, existing.dig(proposal[:locale].to_s, dev.key))
      end

      ops + unmatched_operations
    end

    # One :unmatched operation per unknown string, deduped by key/source so a
    # plural spread over several rows (or a string repeated across locales)
    # reports once.
    def unmatched_operations
      seen = {}
      @proposals.reject { |p| p[:dev] }.each do |proposal|
        id = proposal[:key].to_s.strip
        id = proposal[:source].to_s if id.empty?
        seen[id] ||= Operation.new(
          key: proposal[:key], locale: nil, source: proposal[:source], status: :unmatched,
          old_value: nil, new_value: nil, plural: false, issues: [], dev: nil
        )
      end
      seen.values
    end

    def load_existing(matched)
      result = Hash.new { |h, locale| h[locale] = {} }
      matched.group_by { |p| p[:locale].to_s }.each do |locale, proposals|
        keys = proposals.map { |p| p[:dev].key }
        Escriba::Translation.for_locale(locale).where(key: keys).each do |row|
          result[locale][row.key] = row
        end
      end
      result
    end

    def operation_for(proposal, existing)
      dev = proposal[:dev]
      locale = proposal[:locale].to_s
      new_value = normalize_new_value(proposal[:value], dev.plural)

      # Blank input leaves the existing value untouched — emit no operation.
      return nil if blank_value?(new_value, dev.plural)

      old_value = existing&.value
      status =
        if blank_value?(old_value, dev.plural)
          :create
        elsif values_equal?(old_value, new_value, dev.plural)
          :unchanged
        else
          :overwrite
        end

      issues = []
      if %i[create overwrite].include?(status)
        issues = lint(dev, new_value)
        status = :invalid if issues.any? { |i| Escriba::TranslationValidator::ERROR_CODES.include?(i.code) }
      end

      Operation.new(key: dev.key, locale: locale, source: source_text(dev), status: status,
        old_value: old_value, new_value: new_value, plural: dev.plural, issues: issues, dev: dev)
    end

    # Coerce a proposed value to the shape the dev string expects. A plural Hash
    # is cleaned of blank forms; a non-String value for a singular string is
    # dropped (never written as bad data). A String for a plural string is kept
    # so the linter can flag the missing plural forms.
    def normalize_new_value(value, plural)
      if plural
        value.is_a?(Hash) ? value.transform_keys(&:to_s).reject { |_, v| blank?(v) } : value
      else
        value.is_a?(String) ? value : nil
      end
    end

    def write(op)
      dev = op.dev
      row = Escriba::Translation.find_or_initialize_by(key: dev.key, locale: op.locale)
      row.source_copy = dev.source_copy
      row.meaning = dev.meaning
      row.interpolation_names = dev.interpolation_names
      row.plural = dev.plural
      row.value = op.new_value
      row.save!
    end

    def lint(dev, new_value)
      Escriba::TranslationValidator.call(
        value: new_value,
        source_copy: dev.source_copy,
        source_interpolations: dev.interpolation_names,
        plural: dev.plural,
      )
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

      if plural
        value.is_a?(Hash) ? normalize_plural(value).empty? : value.to_s.strip.empty?
      else
        value.to_s.strip.empty?
      end
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
  end
end
