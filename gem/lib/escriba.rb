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
