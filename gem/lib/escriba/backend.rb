# frozen_string_literal: true

require "i18n"
require "i18n/backend/simple"
require_relative "yml_format"
require "i18n/backend/pluralization"
require "i18n/backend/fallbacks"

module Escriba
  class Backend < I18n::Backend::Simple
    include I18n::Backend::Pluralization
    include I18n::Backend::Fallbacks

    NAMESPACE = Escriba::YmlFormat::NAMESPACE.to_sym

    def lookup(locale, key, scope = [], options = {})
      keys = I18n.normalize_keys(locale, key, scope, options[:separator])
      # keys is [locale, *path]; for Escriba lookups path is [:escriba, :<hash>]
      if keys.size == 3 && keys[1] == NAMESPACE
        # The block reaches Simple#lookup, i.e. the YAML files on the I18n
        # load path (the escriba.<locale>.yml dumps shipped with the app).
        escriba_lookup(locale, keys[2].to_s) { super }
      else
        super
      end
    end

    private

    def escriba_lookup(locale, hash_key, &yml_lookup)
      locale = locale.to_sym
      dev_locale = Escriba.config.dev_locale
      source = Thread.current[:escriba_source]

      if Escriba.dev_locale_in_code? && locale == dev_locale
        return source_value(source)
      end

      # The database is the source of truth; the dumped YAML files cover keys
      # it doesn't have a value for yet, so copies shipped with a deploy are
      # live before anyone translates them in the admin UI.
      Escriba.cache.fetch(locale, hash_key) do
        load_or_seed(locale, hash_key, source, dev_locale) || yml_value(yml_lookup&.call)
      end
    end

    # The dumped YAML files are hand-edited, so only well-formed values get
    # served: blank/whitespace-only skeleton entries, blank plural forms and
    # YAML-typed scalars (an unquoted `123` or `yes`) all count as missing, so
    # the normal fallbacks apply instead of leaking raw scalars into pages.
    def yml_value(value)
      case value
      when String
        value.strip.empty? ? nil : value
      when Hash
        forms = value.select { |_, v| v.is_a?(String) && !v.strip.empty? }
        forms.empty? ? nil : forms
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
