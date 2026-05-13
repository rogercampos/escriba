# frozen_string_literal: true

require "digest"
require "json"

module Escriba
  module KeyDeriver
    extend self

    PLURAL_FORM_KEYS = %i[zero one two few many other].freeze
    KEY_LENGTH = 16
    INTERPOLATION_REGEX = /%\{([^}]+)\}/

    def for_singular(copy, meaning: nil)
      normalized = ordinalize_interpolations(normalize_whitespace(copy))
      canonical = { "copy" => normalized, "meaning" => meaning }
      sha(canonical)
    end

    def for_plural(meaning: nil, **forms)
      normalized_forms = forms
        .transform_keys(&:to_s)
        .transform_values { |v| ordinalize_interpolations(normalize_whitespace(v)) }
        .sort
        .to_h
      canonical = { "plural" => normalized_forms, "meaning" => meaning }
      sha(canonical)
    end

    def normalize_whitespace(str)
      str.strip.gsub(/\s+/, " ")
    end

    def ordinalize_interpolations(str)
      seen = {}
      counter = 0
      str.gsub(INTERPOLATION_REGEX) do
        name = ::Regexp.last_match(1)
        unless seen.key?(name)
          counter += 1
          seen[name] = counter
        end
        "%{#{seen[name]}}"
      end
    end

    def interpolation_names(copy)
      names = []
      copy.scan(INTERPOLATION_REGEX) do |match|
        name = match[0]
        names << name unless names.include?(name)
      end
      names
    end

    def sha(canonical)
      Digest::SHA256.hexdigest(JSON.generate(canonical))[0, KEY_LENGTH]
    end
  end
end
