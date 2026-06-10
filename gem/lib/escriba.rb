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
if defined?(Rails::Engine)
  require "pagy"
  require_relative "escriba/engine"
end

module Escriba
  # When this process loaded the library, i.e. when its per-process
  # translation cache started filling.
  BOOTED_AT = Time.now.utc

  class << self
    def config
      @config ||= Configuration.new
    end

    def booted_at
      BOOTED_AT
    end

    # The last time edits were published. Translations are cached per process,
    # so the real publish gate is a restart of the serving processes — under
    # Kamal (and most deploy tools) that's the last deploy, which is why this
    # process' boot time is the default. Rows updated after this moment may
    # still be served stale. config.last_published_at (a Time or a callable)
    # overrides it for teams that record exact deploy times.
    def last_published_at
      configured = config.last_published_at
      value = configured.respond_to?(:call) ? configured.call : configured
      value || booted_at
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
