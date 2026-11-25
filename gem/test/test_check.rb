# frozen_string_literal: true

require "test_helper"
require "tmpdir"
require "fileutils"

class TestCheck < Minitest::Test
  def setup
    Escriba.reset_config!
    Escriba.config.available_locales = %i[en es]
    @root = Dir.mktmpdir
    @app = File.join(@root, "app")
    @locales = File.join(@root, "config/locales")
    FileUtils.mkdir_p([@app, @locales])
  end

  def teardown
    FileUtils.remove_entry(@root)
    Escriba.reset_config!
    I18n.backend.reload!
  end

  def source(code, file: "page.rb")
    File.write(File.join(@app, file), code)
  end

  def extractor
    Escriba::SourceExtractor.new(paths: [@app])
  end

  def check
    Escriba::Check.new(extractor: extractor, dir: @locales, root: @root)
  end

  def dump
    Escriba::YmlDumper.new(dir: @locales, extracted: extractor.strings).dump!
  end

  # Sets a value in the dumped file, the way a translator would.
  def translate(key, value)
    path = File.join(@locales, "escriba.es.yml")
    content = File.read(path, encoding: Encoding::UTF_8).sub(/^    #{key}:.*(\n      .*)*$/) do
      YAML.dump({ key => value }).sub(/\A---\n/, "").chomp.gsub(/^/, "    ")
    end
    File.write(path, content, encoding: Encoding::UTF_8)
  end

  def key(copy, meaning: nil)
    Escriba::KeyDeriver.for_singular(copy, meaning: meaning)
  end

  def test_a_dumped_and_translated_catalog_passes
    source(%(E18n.t("Hello %{name}", name: n)\nE18n.t(one: "1 file", other: "%{count} files", count: n)))
    dump
    translate(key("Hello %{name}"), "Hola %{name}")
    translate(Escriba::KeyDeriver.for_plural(one: "1 file", other: "%{count} files"),
      { "one" => "1 fitxer", "other" => "%{count} fitxers" })

    assert check.ok?, check.problems.inspect
  end

  def test_reports_dynamic_calls_and_unparseable_files
    source(%(E18n.t(label)))
    File.write(File.join(@app, "bad.erb"), "\xE9 <%= E18n.t(\"x\") %>".b)
    dump

    problems = check.problems
    assert(problems.any? { |p| p.start_with?("Dynamic E18n.t call") && p.end_with?("app/page.rb:1") })
    assert(problems.any? { |p| p.start_with?("Could not parse app/bad.erb") })
  end

  def test_reports_call_sites_sharing_a_key_with_different_interpolation_names
    source(%(E18n.t("Edit %{name}", name: a)\nE18n.t("Edit %{title}", title: b)))
    dump

    assert_equal 1, check.problems.size
    assert_includes check.problems.first, "%{name} at app/page.rb:1; %{title} at app/page.rb:2"
  end

  def test_reports_a_missing_file
    source(%(E18n.t("Save")))

    assert_equal ["config/locales/escriba.es.yml is out of date (missing): run bin/rails escriba:dump_yml"],
      check.problems
  end

  def test_reports_new_strings_and_strings_gone_from_the_source
    source(%(E18n.t("Save")))
    dump
    source(%(E18n.t("Delete")\nE18n.t("Cancel")))

    assert_equal ["config/locales/escriba.es.yml is out of date (2 new string(s) without an entry, " \
                  "1 entry(ies) for strings no longer in the source): run bin/rails escriba:dump_yml"],
      check.problems
  end

  def test_reads_a_file_edited_by_hand_in_another_layout
    source(%(E18n.t("Hello %{name}", name: n)))
    dump
    path = File.join(@locales, "escriba.es.yml")
    File.write(path, "es:\n  escriba: { #{key("Hello %{name}")}: \"Hola %{nombre}\" }\n")

    assert_equal 1, check.problems.size
    assert_includes check.problems.first, "Unknown interpolation %{nombre}"
  end

  def test_reports_a_file_for_a_locale_that_is_not_translated
    source(%(E18n.t("Save")))
    dump
    File.write(File.join(@locales, "escriba.en.yml"), "en:\n  escriba: {}\n")

    assert_equal 1, check.problems.size
    assert_includes check.problems.first, "config/locales/escriba.en.yml is for a locale that isn't translated"
  end

  def test_reports_invalid_yaml
    source(%(E18n.t("Save")))
    File.write(File.join(@locales, "escriba.es.yml"), "es:\n  escriba: [\n")

    assert_equal 1, check.problems.size
    assert check.problems.first.start_with?("Invalid YAML in config/locales/escriba.es.yml")
  end

  def test_reports_values_with_interpolation_errors
    source(%(E18n.t("Hello %{name}", name: n)))
    dump
    translate(key("Hello %{name}"), "Hola %{nombre}")

    assert_equal 1, check.problems.size
    problem = check.problems.first
    assert problem.start_with?(%(config/locales/escriba.es.yml: "Hello %{name}" (#{key("Hello %{name}")}): ))
    assert_includes problem, "Unknown interpolation %{nombre}"
    assert_includes problem, "Missing interpolation %{name}"
  end

  def test_reports_values_that_are_not_strings
    source(%(E18n.t("Yes")))
    dump
    translate(key("Yes"), true)

    assert_equal 1, check.problems.size
    assert_includes check.problems.first, "the value must be a string (quote it), not true"
  end

  def test_reports_plurals_missing_a_form_their_locale_uses
    I18n.backend.store_translations(:es, i18n: { plural: { keys: %i[one few many other] } })
    source(%(E18n.t(one: "1 file", other: "%{count} files", count: n)))
    dump
    plural_key = Escriba::KeyDeriver.for_plural(one: "1 file", other: "%{count} files")

    translate(plural_key, { "one" => "1 plik", "few" => "%{count} pliki", "many" => "", "other" => "%{count} pliku" })
    assert_equal 1, check.problems.size
    assert_includes check.problems.first, "config/locales/escriba.es.yml"
    assert_includes check.problems.first, "Missing the plural form(s) many this locale uses"

    translate(plural_key, { "one" => "1 plik", "few" => "%{count} pliki", "many" => "%{count} plików",
                            "other" => "%{count} pliku" })
    assert check.ok?, check.problems.inspect
  end

  def test_reports_malformed_plurals
    plural_key = Escriba::KeyDeriver.for_plural(one: "1 file", other: "%{count} files")
    source(%(E18n.t(one: "1 file", other: "%{count} files", count: n)))
    dump

    translate(plural_key, "%{count} fitxers")
    assert_includes check.problems.first, "a plural needs one entry per plural form"

    translate(plural_key, { "one" => "1 fitxer", "others" => "%{count} fitxers" })
    assert_includes check.problems.first, "unknown plural form(s) others"

    translate(plural_key, { "one" => "1 fitxer", "other" => 2 })
    assert_includes check.problems.first, "plural forms must be strings (quote them): other"

    translate(plural_key, { "one" => "1 fitxer", "other" => "" })
    assert_includes check.problems.first, %(Missing the required "other" plural form.)
  end
end
