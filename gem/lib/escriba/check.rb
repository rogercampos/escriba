# frozen_string_literal: true

require "pathname"
require_relative "yml_format"

module Escriba
  # Everything that can make the YAML catalog wrong without anything failing
  # at runtime, as a list of problems for `escriba:check` to report. Meant for
  # CI: the files are the only source of translations, so they are verified
  # before they ship rather than when they are served.
  #
  # - E18n.t calls that static extraction can't read (dynamic copy or meaning)
  #   and source files it can't parse: their strings are missing from the
  #   catalog, so they can never be translated.
  # - Call sites sharing a key but naming their interpolations differently:
  #   keys ordinalize the names, so "Edit %{name}" and "Edit %{title}" are one
  #   entry, and any translation of it raises a missing-interpolation error at
  #   one of the two call sites. English never shows it.
  # - Files out of step with the source, which `escriba:dump_yml` fixes: a
  #   missing file, new strings without an entry, entries for strings gone
  #   from the source, a file for a locale that isn't translated, or invalid
  #   YAML.
  # - Values that can't be served: not a string, plural forms that aren't
  #   CLDR forms, or error-level lint issues (an interpolation the source
  #   doesn't have or a missing one, a plural without its "other" form).
  #
  # Untranslated (blank) entries are not problems: they show the source copy.
  class Check
    PLURAL_FORMS = KeyDeriver::PLURAL_FORM_KEYS.map(&:to_s).freeze

    # extractor: a SourceExtractor over the app's source.
    # dir:       where the escriba.<locale>.yml files live.
    # root:      paths are reported relative to it.
    def initialize(extractor:, dir:, root: nil)
      @extractor = extractor
      @dir = Pathname.new(dir)
      @root = root && "#{root.to_s.chomp("/")}/"
    end

    def problems
      @problems ||= source_problems + file_problems
    end

    def ok?
      problems.empty?
    end

    private

    def strings
      @extractor.strings
    end

    def source_problems
      dynamic = @extractor.dynamic_calls.map do |call|
        "Dynamic E18n.t call (pass string literals as copy and meaning, or it can't be translated): " \
          "#{rel(call.file)}:#{call.line}"
      end
      failed = @extractor.failed_files.map { |failure| "Could not parse #{rel(failure.file)}: #{failure.message}" }

      dynamic + failed + interpolation_name_problems
    end

    def interpolation_name_problems
      by_key = strings.to_h { |entry| [entry.key, entry] }

      @extractor.occurrences.group_by(&:key).filter_map do |key, sites|
        next if sites.map(&:interpolation_names).uniq.size <= 1

        listed = sites.map do |site|
          names = site.interpolation_names.map { |name| "%{#{name}}" }.join(", ")
          "#{names} at #{rel(site.file)}:#{site.line}"
        end
        "#{Escriba.source_text(by_key.fetch(key)).inspect} names its interpolations differently at each call " \
          "site, and one translation serves them all (give each a different `meaning:`, or use the same names): " \
          "#{listed.join("; ")}"
      end
    end

    def file_problems
      dumper = YmlDumper.new(dir: @dir, extracted: strings)

      layout_problems(dumper.paths, dumper.stale_files) + value_problems(dumper.paths)
    rescue Escriba::InvalidDumpFile => e
      ["Invalid YAML in #{rel(e.message)}"]
    end

    # Only the entries a file has are compared, not its text: a value edited by
    # hand is fine however the editor formatted it, and the comments can't go
    # stale, since the copy and meaning they show are part of the key.
    def layout_problems(paths, stale)
      outdated = paths.filter_map do |path|
        detail = outdated_detail(path)
        "#{rel(path)} is out of date (#{detail}): run bin/rails escriba:dump_yml" if detail
      end
      removed = stale.map do |file|
        "#{rel(file)} is for a locale that isn't translated (the dev locale, or not in available_locales): " \
          "run bin/rails escriba:dump_yml to delete it"
      end

      outdated + removed
    end

    def outdated_detail(path)
      return "missing" unless path.exist?

      in_file = YmlFormat.entries(path.to_s).keys.map(&:to_s)
      in_source = strings.map(&:key)
      details = []
      added = (in_source - in_file).size
      gone = (in_file - in_source).size
      details << "#{added} new string(s) without an entry" if added.positive?
      details << "#{gone} entry(ies) for strings no longer in the source" if gone.positive?
      details.join(", ") unless details.empty?
    end

    def value_problems(paths)
      by_key = strings.to_h { |entry| [entry.key, entry] }

      paths.select(&:exist?).flat_map do |path|
        YmlFormat.entries(path.to_s).filter_map do |key, value|
          entry = by_key[key.to_s]
          next unless entry

          message = value_problem(entry, value)
          "#{rel(path)}: #{Escriba.source_text(entry).inspect} (#{entry.key}): #{message}" if message
        end
      end
    end

    def value_problem(entry, value)
      return nil if value.nil?

      shape = shape_problem(entry, value)
      return shape if shape

      errors = TranslationValidator.call(
        value: value, source_copy: entry.source_copy,
        source_interpolations: entry.interpolation_names, plural: entry.plural
      ).select { |issue| TranslationValidator::ERROR_CODES.include?(issue.code) }
      errors.map(&:message).join(" ") unless errors.empty?
    end

    def shape_problem(entry, value)
      unless entry.plural
        return value.is_a?(String) ? nil : "the value must be a string (quote it), not #{value.inspect}"
      end

      return "a plural needs one entry per plural form, not #{value.inspect}" unless value.is_a?(Hash)

      unknown = value.keys.map(&:to_s) - PLURAL_FORMS
      return "unknown plural form(s) #{unknown.join(", ")}; the forms are #{PLURAL_FORMS.join(", ")}" if unknown.any?

      not_strings = value.reject { |_, form| form.nil? || form.is_a?(String) }
      "plural forms must be strings (quote them): #{not_strings.keys.join(", ")}" if not_strings.any?
    end

    def rel(path)
      @root ? path.to_s.delete_prefix(@root) : path.to_s
    end
  end
end
