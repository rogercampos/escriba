# frozen_string_literal: true

module Escriba
  # Indexes the dev-locale rows (the source-of-truth strings) so importers can
  # resolve an incoming row to the string it translates — by Escriba key first,
  # then by exact source copy for singular strings (a convenience for
  # hand-authored files). Loads the dev rows once and memoizes the lookups.
  class DevIndex
    KEY_RE = /\A[a-f0-9]{16}\z/

    def initialize(dev_locale)
      @dev_locale = dev_locale.to_sym
    end

    # Returns the dev Translation row for an incoming (key, source) pair, or nil
    # when the string is unknown.
    def resolve(key:, source:)
      normalized_key = key.to_s.strip
      return by_key[normalized_key] if normalized_key.match?(KEY_RE) && by_key[normalized_key]

      normalized_source = source.to_s
      return nil if normalized_source.empty?

      by_source[normalized_source]
    end

    def by_key
      @by_key ||= rows.index_by(&:key)
    end

    private

    def rows
      @rows ||= Escriba::Translation.for_locale(@dev_locale).to_a
    end

    # Singular dev strings keyed by their source copy.
    def by_source
      @by_source ||= rows.reject(&:plural).index_by { |d| d.source_copy.to_s }
    end
  end
end
