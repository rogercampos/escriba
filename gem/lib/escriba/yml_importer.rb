# frozen_string_literal: true

require "yaml"
require "pathname"
require_relative "yml_format"

module Escriba
  # Imports the escriba.<locale>.yml dumps back into the database — the
  # deploy-time half of shipping copies in a PR (run it from a Kamal
  # pre-app-boot hook or the Docker entrypoint).
  #
  # Statically extracted strings (see SourceExtractor) are seeded as dev-locale
  # rows first, so brand-new strings — which have no database row until they
  # first execute — are resolvable and the whole catalog exists right at
  # deploy. Values then go through TranslationReconciler with overwrite
  # disabled: they only fill rows the database has blank (an admin edit always
  # wins), blank skeleton entries are skipped, and values with error-level
  # lint issues are rejected. The operation is idempotent, so re-running it on
  # every boot group or deploy is safe.
  class YmlImporter
    def initialize(dir:, extracted: [])
      @dir = Pathname.new(dir)
      @extracted = extracted
    end

    def operations
      reconciler.operations
    end

    def summary
      reconciler.summary
    end

    def apply!
      seed_dev_rows!
      reconciler.apply!
    end

    private

    def reconciler
      @reconciler ||= Escriba::TranslationReconciler.new(proposals, overwrite: false)
    end

    def dev_locale
      Escriba.config.dev_locale
    end

    # Make the extracted catalog exist in the database up front, instead of
    # waiting for each string's first execution. Same write the backend does
    # lazily (insert-only — existing dev rows are untouched), batched into a
    # single statement.
    def seed_dev_rows!
      missing = @extracted.reject { |entry| dev_index.by_key.key?(entry.key) }
      Escriba::Translation.seed_dev_locale(dev_locale, missing.map do |entry|
        [entry.key, {
          value: entry.source_copy,
          meaning: entry.meaning,
          plural: entry.plural,
          interpolation_names: entry.interpolation_names,
        }]
      end)
    end

    def proposals
      @proposals ||= Dir[@dir.join(YmlFormat::FILE_GLOB).to_s].sort.flat_map do |file|
        locale = YmlFormat.locale_of(file)
        next [] unless importable_locales.include?(locale)

        YmlFormat.entries(file).map do |key, value|
          if (dev = resolve(key.to_s))
            { dev: dev, locale: locale, value: value }
          else
            { dev: nil, key: key.to_s, source: nil }
          end
        end
      end
    end

    # Resolution consults the DB first and the extracted catalog second, so
    # operations/summary preview correctly before apply! seeds any dev row.
    # ExtractedString exposes the same readers the reconciler needs.
    def resolve(key)
      dev_index.resolve(key: key, source: nil) || extracted_by_key[key]
    end

    def extracted_by_key
      @extracted_by_key ||= @extracted.to_h { |entry| [entry.key, entry] }
    end

    def dev_index
      @dev_index ||= Escriba::DevIndex.new(dev_locale)
    end

    def importable_locales
      @importable_locales ||= Escriba.config.available_locales.map(&:to_s)
    end
  end
end
