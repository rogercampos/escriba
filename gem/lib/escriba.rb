# frozen_string_literal: true

require_relative "escriba/version"
require_relative "escriba/errors"
require_relative "escriba/configuration"
require_relative "escriba/key_deriver"
require_relative "escriba/translation_validator"
require_relative "escriba/dev_index"
require_relative "escriba/translation_reconciler"
require_relative "escriba/translation_schema"
require_relative "escriba/translation_exporter"
require_relative "escriba/translation_importer"
require_relative "escriba/translation_prompt"
require_relative "escriba/translation_json_importer"
require_relative "escriba/cache"
require_relative "escriba/backend"
require_relative "escriba/e18n"
require_relative "escriba/engine" if defined?(Rails::Engine)

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

    def cache
      @cache ||= Cache.new
    end

    def reset_cache!
      @cache = Cache.new
    end

    def env
      return Rails.env if defined?(Rails) && Rails.respond_to?(:env)

      ENV.fetch("ESCRIBA_ENV", "development")
    end

    def dev_or_test?
      %w[development test].include?(env.to_s)
    end

    def dev_locale_in_code?
      dev_or_test? || config.dev_locale_from_code
    end
  end
end

E18n = Escriba::E18n unless defined?(E18n)
