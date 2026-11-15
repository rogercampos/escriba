# frozen_string_literal: true

require "i18n"
require "i18n/backend/simple"
require "i18n/backend/pluralization"
require "i18n/backend/fallbacks"
require_relative "yml_format"

module Escriba
  # Rails' Simple backend, with Escriba's lookups answered as follows:
  #
  # - the dev locale serves the copy written at the E18n.t call site, always;
  # - every other locale serves its config/locales/escriba.<locale>.yml file,
  #   which Rails loads like any other locale file. An entry that is blank or
  #   not a string counts as missing, so I18n's fallback chain applies and the
  #   page shows the dev-locale copy instead of nothing.
  class Backend < I18n::Backend::Simple
    include I18n::Backend::Pluralization
    include I18n::Backend::Fallbacks

    NAMESPACE = Escriba::YmlFormat::NAMESPACE.to_sym

    def lookup(locale, key, scope = [], options = {})
      keys = I18n.normalize_keys(locale, key, scope, options[:separator])
      # keys is [locale, *path]; for Escriba lookups path is [:escriba, :<hash>]
      return super unless keys.size == 3 && keys[1] == NAMESPACE

      if locale.to_sym == Escriba.config.dev_locale.to_sym
        source_value(Thread.current[:escriba_source])
      else
        file_value(super)
      end
    end

    private

    def source_value(source)
      return nil unless source

      value = source[:value]
      value.is_a?(Hash) ? value.transform_keys(&:to_sym) : value
    end

    # The files are edited by hand, so only well-formed values are served:
    # blank skeleton entries, blank plural forms and YAML-typed scalars (an
    # unquoted `123` or `yes`) count as missing. `escriba:check` reports the
    # malformed ones.
    def file_value(value)
      case value
      when String
        value.strip.empty? ? nil : value
      when Hash
        forms = value.select { |_, v| v.is_a?(String) && !v.strip.empty? }
        forms.empty? ? nil : forms
      end
    end
  end
end
