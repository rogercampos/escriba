# frozen_string_literal: true

require "i18n"
require "i18n/backend/simple"
require "i18n/backend/pluralization"
require "i18n/backend/fallbacks"

module Escriba
  class Backend < I18n::Backend::Simple
    include I18n::Backend::Pluralization
    include I18n::Backend::Fallbacks

    NAMESPACE = :escriba

    def lookup(locale, key, scope = [], options = {})
      keys = I18n.normalize_keys(locale, key, scope, options[:separator])
      # keys is [locale, *path]; for Escriba lookups path is [:escriba, :<hash>]
      if keys.size == 3 && keys[1] == NAMESPACE
        escriba_lookup(locale, keys[2].to_s)
      else
        super
      end
    end

    private

    def escriba_lookup(locale, hash_key)
      locale = locale.to_sym
      dev_locale = Escriba.config.dev_locale
      source = Thread.current[:escriba_source]

      if Escriba.dev_or_test? && locale == dev_locale
        return source_value(source)
      end

      Escriba.cache.fetch(locale, hash_key) do
        load_or_seed(locale, hash_key, source, dev_locale)
      end
    end

    def load_or_seed(locale, hash_key, source, dev_locale)
      row = Escriba::Translation.find_by(key: hash_key, locale: locale.to_s)
      return row_value(row) if row

      return nil unless source

      Escriba::Translation.upsert_dev_locale(hash_key, dev_locale, source)

      if locale == dev_locale
        source_value(source)
      end
    end

    def source_value(source)
      return nil unless source
      value = source[:value]
      value.is_a?(Hash) ? value.transform_keys(&:to_sym) : value
    end

    def row_value(row)
      value = row.value
      if row.plural && value.is_a?(Hash)
        value.transform_keys(&:to_sym)
      else
        value
      end
    end
  end
end
