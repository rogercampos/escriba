# frozen_string_literal: true

def escriba_extractor
  paths = [Rails.root.join("app"), Rails.root.join("lib")].select(&:exist?)
  Escriba::SourceExtractor.new(paths: paths)
end

def escriba_dir
  Rails.root.join("config/locales")
end

def escriba_report_dynamic_calls(extractor)
  extractor.dynamic_calls.each do |call|
    warn "escriba: skipped dynamic E18n.t call at #{call.file}:#{call.line} (copy not statically derivable)"
  end
  extractor.failed_files.each do |failure|
    warn "escriba: could not extract from #{failure.file}: #{failure.message}"
  end
end

# { locale => [translated, total] } for every translated locale, read from its
# file.
def escriba_coverage(extractor)
  Escriba.translated_locales.to_h do |locale|
    path = escriba_dir.join(Escriba::YmlFormat.file_name(locale))
    entries = path.exist? ? Escriba::YmlFormat.entries(path.to_s) : {}
    translated = extractor.strings.count do |string|
      issues = Escriba::TranslationValidator.call(
        value: entries[string.key], source_copy: string.source_copy, plural: string.plural
      )
      issues.none? { |issue| issue.code == :missing }
    end
    [locale, [translated, extractor.strings.size]]
  end
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
  desc "Write config/locales/escriba.<locale>.yml for every translated locale: an entry for each " \
       "E18n.t string in the source, keeping the values already there"
  task dump_yml: :environment do
    extractor = escriba_extractor
    files = Escriba::YmlDumper.new(dir: escriba_dir, extracted: extractor.strings).dump!

    files.each { |file| puts file }
    escriba_report_dynamic_calls(extractor)
  end

  desc "Verify the translation catalog: every E18n.t call extractable, config/locales/escriba.*.yml " \
       "up to date with the source, and every value servable. Fails with the list of problems"
  task check: :environment do
    extractor = escriba_extractor
    check = Escriba::Check.new(extractor: extractor, dir: escriba_dir, root: Rails.root)

    if check.ok?
      untranslated = escriba_coverage(extractor).sum { |_, (translated, total)| total - translated }
      puts "escriba:check OK: #{extractor.strings.size} strings, #{untranslated} untranslated entry(ies) " \
           "across #{Escriba.translated_locales.size} locale(s)."
    else
      abort(["escriba:check FAILED:", *check.problems.map { |problem| "  - #{problem}" }, ""].join("\n"))
    end
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

    puts "Translated, per locale (from config/locales/escriba.<locale>.yml)"
    puts "-" * 72
    escriba_coverage(extractor).each do |locale, (translated, total)|
      percent = total.zero? ? 100.0 : translated * 100.0 / total
      puts format("  %-8s %5d / %-5d %5.1f%%", locale, translated, total, percent)
    end
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
    # still renders the copy it is given, but is never translated.
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
