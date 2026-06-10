# frozen_string_literal: true

require "yaml"

module Escriba
  # The single definition of the on-disk YAML catalog format
  # (config/locales/escriba.<locale>.yml with entries under "<locale>:
  # escriba:"). Three parties must agree on it — the dumper writes it, the
  # importer re-parses it, and the I18n backend looks entries up through the
  # same namespace — so they all reference these instead of their own copies.
  module YmlFormat
    NAMESPACE = "escriba"
    FILE_GLOB = "#{NAMESPACE}.*.yml"
    FILE_RE = /\A#{NAMESPACE}\.(?<locale>.+)\.yml\z/

    module_function

    def file_name(locale)
      "#{NAMESPACE}.#{locale}.yml"
    end

    def locale_of(file)
      File.basename(file)[FILE_RE, :locale]
    end

    # The {key => value} entries of a dump file. These files are hand-edited
    # (that's the workflow), so parse errors must name the file — and aliases,
    # which a human may legitimately use, are allowed.
    def entries(file)
      data = YAML.safe_load(File.read(file), aliases: true) || {}
      data.dig(locale_of(file), NAMESPACE) || {}
    rescue Psych::Exception => e
      raise Escriba::InvalidDumpFile, "#{file}: #{e.message}"
    end
  end
end
