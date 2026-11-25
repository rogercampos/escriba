# frozen_string_literal: true

require_relative "escriba/version"
require_relative "escriba/errors"
require_relative "escriba/configuration"
require_relative "escriba/yml_format"
require_relative "escriba/key_deriver"
require_relative "escriba/translation_validator"
require_relative "escriba/source_extractor"
require_relative "escriba/yml_dumper"
require_relative "escriba/check"
require_relative "escriba/backend"
require_relative "escriba/e18n"
require_relative "escriba/railtie" if defined?(Rails::Railtie)

module Escriba
  class << self
    def config
      @config ||= Configuration.new
    end

    def configure
      yield config
    end

    def reset_config!
      @config = Configuration.new
    end

    # The locales that have a YAML file: every available locale but the dev
    # locale, whose copy is the source code itself.
    def translated_locales
      config.available_locales.map(&:to_sym) - [config.dev_locale.to_sym]
    end

    # The CLDR plural forms `locale` uses, as strings (["one", "few", "many",
    # "other"] for Polish), read from the locale's I18n data under
    # `i18n.plural.keys`, next to the plural rule that picks among them
    # (rails-i18n declares both for every locale it ships). nil when the locale
    # declares none, or isn't an I18n locale: then only the source's forms and
    # "other" are known.
    def plural_forms(locale)
      return nil unless I18n.locale_available?(locale)

      forms = I18n.t(:"i18n.plural.keys", locale: locale, resolve: false, default: nil)
      forms.map(&:to_s) & KeyDeriver::PLURAL_FORM_KEYS.map(&:to_s) if forms.is_a?(Array)
    end

    # Plain-text rendering of a string's source copy (plural forms joined on
    # one line), for the comments in the YAML files and for reports. `entry` is
    # anything responding to #source_copy and #plural.
    def source_text(entry)
      source = entry.source_copy
      if entry.plural && source.is_a?(Hash)
        source.map { |form, copy| "#{form}: #{copy}" }.join(" · ")
      else
        source.to_s
      end
    end
  end
end

E18n = Escriba::E18n unless defined?(E18n)
