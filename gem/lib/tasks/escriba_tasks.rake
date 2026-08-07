# frozen_string_literal: true

def escriba_extractor
  paths = [Rails.root.join("app"), Rails.root.join("lib")].select(&:exist?)
  Escriba::SourceExtractor.new(paths: paths)
end

def escriba_report_dynamic_calls(extractor)
  extractor.dynamic_calls.each do |call|
    warn "escriba: skipped dynamic E18n.t call at #{call.file}:#{call.line} (copy not statically derivable)"
  end
  extractor.failed_files.each do |failure|
    warn "escriba: could not extract from #{failure.file}: #{failure.message}"
  end
end

# An on/off environment variable: set to anything but the words for "off". An
# unset variable is off, and so is `OVERWRITE=0` — which somebody who has just
# run it once will reach for, and which reading `ENV[...].present?` would treat
# as a request to do it again.
def escriba_flag?(name)
  !["", "0", "false", "no", "off"].include?(ENV[name].to_s.strip.downcase)
end

# A short, single-line label for an extracted string, for use in stats listings.
def escriba_label(string)
  copy = string.source_copy
  text = string.plural ? copy.values_at("other", "one").compact.first : copy
  text = text.to_s.gsub(/\s+/, " ").strip
  label = text.length > 70 ? "#{text[0, 67]}..." : text
  string.plural ? "#{label} (plural)" : label
end

namespace :escriba do
  desc "Dump all translations to config/locales/escriba.<locale>.yml, replacing the previous dump"
  task dump_yml: :environment do
    extractor = escriba_extractor
    files = Escriba::YmlDumper.new(
      dir: Rails.root.join("config/locales"), extracted: extractor.strings
    ).dump!

    files.each { |file| puts file }
    escriba_report_dynamic_calls(extractor)
  end

  desc "Import config/locales/escriba.*.yml into the database (fills blanks; never overwrites). " \
       "OVERWRITE=1 also replaces values that differ; DRY_RUN=1 reports without writing"
  task import_yml: :environment do
    overwrite = escriba_flag?("OVERWRITE")
    dry_run = escriba_flag?("DRY_RUN")

    extractor = escriba_extractor
    importer = Escriba::YmlImporter.new(
      dir: Rails.root.join("config/locales"), extracted: extractor.strings, overwrite: overwrite
    )

    summary = importer.summary

    # Every replacement is named. What it discards is whatever the database
    # holds, which is where translators' own edits live — so an operator who
    # asked for OVERWRITE gets to see exactly what they asked for before it is
    # gone, and afterwards has a record of it in the deploy log.
    importer.operations.each do |op|
      next unless op.status == :overwrite

      puts "escriba: #{op.locale} #{op.key} replacing #{op.old_value.inspect} with #{op.new_value.inspect}"
    end

    if dry_run
      puts "escriba: DRY RUN, nothing written — would create #{summary[:create]}, " \
           "replace #{summary[:overwrite]}, keep #{summary[:kept]} existing, " \
           "#{summary[:invalid]} invalid, #{summary[:unmatched]} unmatched"
    else
      result = importer.apply!
      puts "escriba: imported #{result[:created]} value(s), replaced #{result[:updated]}, " \
           "kept #{summary[:kept]} existing, #{summary[:invalid]} invalid, " \
           "#{summary[:unmatched]} unmatched"
    end

    escriba_report_dynamic_calls(extractor)
  end

  desc "Recompute the cached lint issues for every non-dev row (clears issues that " \
       "a validator change no longer produces, e.g. the removed untranslated check)"
  task relint: :environment do
    dev = Escriba.config.dev_locale.to_s
    changed = 0

    Escriba::Translation.where.not(locale: dev).find_each do |row|
      list = Escriba::TranslationValidator.call(
        value: row.value,
        source_copy: row.source_copy,
        source_interpolations: row.interpolation_names,
        plural: row.plural,
      )
      list = list.reject { |i| i.code == :missing }
      issues = list.empty? ? nil : list.map { |i| { "code" => i.code.to_s, "message" => i.message } }

      next if issues == row.issues

      # update_columns: rewrite the cache only, never touching updated_at — a
      # bump there would falsely flag every row as "pending deploy".
      row.update_columns(issues: issues)
      changed += 1
    end

    puts "escriba: relinted #{changed} row(s)"
  end

  desc "Report statistics about extracted translations (set TOP=n to size the ranked lists)"
  task stats: :environment do
    extractor = escriba_extractor
    top = (ENV["TOP"] || "15").to_i

    strings = extractor.strings
    occurrences = extractor.occurrences
    counts = occurrences.group_by(&:key).transform_values(&:size)
    by_key = strings.index_by(&:key)

    with_meaning = strings.select(&:meaning)
    with_interpolation = strings.reject { |s| s.interpolation_names.empty? }
    plural = strings.select(&:plural)
    repeated = counts.select { |_, n| n > 1 }

    puts "=" * 72
    puts "Escriba translation statistics (from static extraction)"
    puts "=" * 72
    puts

    puts "Counters"
    puts "-" * 72
    puts "  Distinct keys (unique copies) : #{strings.size}"
    puts "  Total call sites (usages)     : #{occurrences.size}"
    puts "  Reused copies (used > once)   : #{repeated.size}"
    puts "  With a meaning string         : #{with_meaning.size}"
    puts "  With interpolation            : #{with_interpolation.size}"
    puts "  Plural forms                  : #{plural.size}"
    puts "  Singular forms                : #{strings.size - plural.size}"
    puts "  Dynamic calls (not extracted) : #{extractor.dynamic_calls.size}"
    puts "  Files that failed to parse    : #{extractor.failed_files.size}"
    puts "  Source files with a usage     : #{occurrences.map(&:file).uniq.size}"
    puts

    puts "Most-used copies (top #{top})"
    puts "-" * 72
    if repeated.empty?
      puts "  (no copy is used more than once)"
    else
      counts.sort_by { |key, n| [-n, escriba_label(by_key[key])] }.first(top).each do |key, n|
        puts format("  %4d×  %s", n, escriba_label(by_key[key]))
      end
    end
    puts

    puts "Copies using a meaning string (#{with_meaning.size})"
    puts "-" * 72
    if with_meaning.empty?
      puts "  (none)"
    else
      with_meaning.sort_by { |s| escriba_label(s) }.each do |s|
        puts "  #{escriba_label(s)}"
        puts "      meaning: #{s.meaning.inspect}"
      end
    end
    puts

    # Same copy text reused under different meanings — these are the cases the
    # meaning disambiguator exists for, since they resolve to distinct keys.
    collisions = strings.group_by { |s| [s.source_copy, s.plural] }.select { |_, v| v.size > 1 }
    puts "Copies sharing source text under different meanings (#{collisions.size})"
    puts "-" * 72
    if collisions.empty?
      puts "  (none)"
    else
      collisions.each do |(_, _), group|
        puts "  #{escriba_label(group.first)}"
        group.each { |s| puts "      meaning: #{s.meaning.inspect}" }
      end
    end
    puts

    # Dynamic E18n.t calls: copy (or meaning) isn't a plain literal, so the key
    # can't be derived statically and the copy never enters the catalog. It
    # still renders at runtime via the source fallback, but won't be translated.
    dynamic = extractor.dynamic_calls
    puts "Dynamic calls — cannot be analyzed (#{dynamic.size})"
    puts "-" * 72
    if dynamic.empty?
      puts "  (none — every E18n.t call has a statically derivable copy)"
    else
      dynamic.sort_by { |c| [c.file, c.line] }.each do |call|
        puts "  #{call.file}:#{call.line}"
      end
    end
    puts

    failed = extractor.failed_files
    unless failed.empty?
      puts "Files that could not be parsed (#{failed.size})"
      puts "-" * 72
      failed.each { |f| puts "  #{f.file}: #{f.message}" }
      puts
    end
  end
end
