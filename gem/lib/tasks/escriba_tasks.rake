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

  desc "Import config/locales/escriba.*.yml into the database (fills blanks; never overwrites)"
  task import_yml: :environment do
    extractor = escriba_extractor
    importer = Escriba::YmlImporter.new(
      dir: Rails.root.join("config/locales"), extracted: extractor.strings
    )

    summary = importer.summary
    result = importer.apply!
    puts "escriba: imported #{result[:created]} value(s), kept #{summary[:kept]} existing, " \
         "#{summary[:invalid]} invalid, #{summary[:unmatched]} unmatched"
    escriba_report_dynamic_calls(extractor)
  end
end
