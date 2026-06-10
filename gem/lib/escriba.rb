# frozen_string_literal: true

require_relative "escriba/version"
require_relative "escriba/errors"
require_relative "escriba/configuration"
require_relative "escriba/yml_format"
require_relative "escriba/key_deriver"
require_relative "escriba/translation_validator"
require_relative "escriba/dev_index"
require_relative "escriba/translation_reconciler"
require_relative "escriba/translation_schema"
require_relative "escriba/translation_exporter"
require_relative "escriba/translation_importer"
require_relative "escriba/translation_prompt"
require_relative "escriba/translation_json_importer"
require_relative "escriba/yml_dumper"
require_relative "escriba/yml_importer"
require_relative "escriba/source_extractor"
require_relative "escriba/cache"
require_relative "escriba/backend"
require_relative "escriba/e18n"
if defined?(Rails::Engine)
  require "pagy"
  require_relative "escriba/engine"
end

module Escriba
  # When this process loaded the library, i.e. when its per-process
  # translation cache started filling. Translations are cached per process, so
  # this is also when edits were last published from this process' point of
  # view — under Kamal (and most deploy tools) that's the last deploy. Rows
  # updated after this moment may still be served stale.
  BOOTED_AT = Time.now.utc

  class << self
    def config
      @config ||= Configuration.new
    end

    def booted_at
      BOOTED_AT
    end

    # Plain-text rendering of an entry's source copy (plural forms joined on
    # one line). Shared by the admin UI, the reconciler and the YAML dumper.
    # `entry` is anything responding to #source_copy and #plural.
    def source_text(entry)
      source = entry.source_copy
      if entry.plural && source.is_a?(Hash)
        source.map { |form, copy| "#{form}: #{copy}" }.join(" · ")
      else
        source.to_s
      end
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
