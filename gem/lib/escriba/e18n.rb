# frozen_string_literal: true

require "i18n"

module Escriba
  module E18n
    extend self

    PLURAL_KEYS = KeyDeriver::PLURAL_FORM_KEYS

    def t(*args, **opts)
      meaning = opts.delete(:meaning)
      plural_keys_present = opts.keys & PLURAL_KEYS

      if plural_keys_present.any?
        translate_plural(args, opts, meaning, plural_keys_present)
      else
        translate_singular(args, opts, meaning)
      end
    end

    private

    def translate_singular(args, opts, meaning)
      raise Escriba::ArgumentError, "Singular call requires a copy string as first argument" if args.empty?
      raise Escriba::ArgumentError, "Singular call accepts only one positional argument" if args.size > 1

      copy = args.first
      raise Escriba::ArgumentError, "Source copy must be a String" unless copy.is_a?(String)

      hash_key = KeyDeriver.for_singular(copy, meaning: meaning)
      source = {
        value: copy,
        meaning: meaning,
        plural: false,
        interpolation_names: KeyDeriver.interpolation_names(copy),
      }

      dispatch(hash_key, source, opts)
    end

    def translate_plural(args, opts, meaning, plural_keys_present)
      raise Escriba::ArgumentError, "Cannot pass positional copy with plural forms" if args.any?
      raise Escriba::ArgumentError, "Plural call requires :count" unless opts.key?(:count)
      raise Escriba::ArgumentError, "Plural call requires :other form" unless plural_keys_present.include?(:other)

      forms = {}
      plural_keys_present.each do |k|
        forms[k] = opts.delete(k)
      end

      forms.each_value do |v|
        raise Escriba::ArgumentError, "Plural form values must be Strings" unless v.is_a?(String)
      end

      hash_key = KeyDeriver.for_plural(meaning: meaning, **forms)
      source = {
        value: forms.transform_keys(&:to_s),
        meaning: meaning,
        plural: true,
        interpolation_names: forms.values.flat_map { |v| KeyDeriver.interpolation_names(v) }.uniq,
      }

      dispatch(hash_key, source, opts)
    end

    def dispatch(hash_key, source, opts)
      Thread.current[:escriba_source] = source
      I18n.t(:"#{Backend::NAMESPACE}.#{hash_key}", **opts)
    ensure
      Thread.current[:escriba_source] = nil
    end
  end
end
