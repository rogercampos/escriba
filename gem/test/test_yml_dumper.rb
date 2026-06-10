# frozen_string_literal: true

require "test_helper"
require "tmpdir"

class TestYmlDumper < Minitest::Test
  def setup
    Escriba.reset_config!
    Escriba::Translation.delete_all
    Escriba.config.available_locales = %i[en es it]
  end

  def teardown
    Escriba.reset_config!
  end

  KEY_A = "a" * 16
  KEY_B = "b" * 16

  def create_row(key:, locale:, value:, source_copy: "Save", plural: false, meaning: nil)
    Escriba::Translation.create!(
      key: key, locale: locale.to_s, value: value, source_copy: source_copy,
      plural: plural, meaning: meaning
    )
  end

  def dump_into(dir)
    Escriba::YmlDumper.new(dir: dir).dump!
  end

  def parsed(dir, locale)
    YAML.safe_load(File.read(File.join(dir, "escriba.#{locale}.yml")))
  end

  def test_writes_one_file_per_locale_with_values_and_skeletons
    create_row(key: KEY_A, locale: :en, value: "Save")
    create_row(key: KEY_A, locale: :es, value: "Guardar")

    Dir.mktmpdir do |dir|
      files = dump_into(dir)

      assert_equal %w[escriba.en.yml escriba.es.yml escriba.it.yml],
        files.map { |f| File.basename(f) }
      assert_equal({ "en" => { "escriba" => { KEY_A => "Save" } } }, parsed(dir, :en))
      assert_equal({ "es" => { "escriba" => { KEY_A => "Guardar" } } }, parsed(dir, :es))
      assert_equal({ "it" => { "escriba" => { KEY_A => "" } } }, parsed(dir, :it))
    end
  end

  def test_skips_the_dev_locale_when_it_is_served_from_code
    Escriba.config.dev_locale_from_code = true
    create_row(key: KEY_A, locale: :en, value: "Save")

    Dir.mktmpdir do |dir|
      files = dump_into(dir)
      assert_equal %w[escriba.es.yml escriba.it.yml], files.map { |f| File.basename(f) }
    end
  end

  def test_regenerating_keeps_file_values_the_local_database_does_not_have
    create_row(key: KEY_A, locale: :en, value: "Save")
    create_row(key: KEY_B, locale: :en, value: "Delete", source_copy: "Delete")
    create_row(key: KEY_B, locale: :es, value: "Eliminar (DB)", source_copy: "Delete")

    Dir.mktmpdir do |dir|
      File.write(File.join(dir, "escriba.es.yml"), YAML.dump(
        { "es" => { "escriba" => { KEY_A => "Guardar (file)", KEY_B => "Eliminar (file)" } } }
      ))

      dump_into(dir)

      entries = parsed(dir, :es).dig("es", "escriba")
      assert_equal "Guardar (file)", entries[KEY_A] # local DB blank — file value survives
      assert_equal "Eliminar (DB)", entries[KEY_B]  # database wins over the file
    end
  end

  def test_replaces_stale_dumps_but_leaves_other_yml_files_alone
    create_row(key: KEY_A, locale: :en, value: "Save")

    Dir.mktmpdir do |dir|
      File.write(File.join(dir, "escriba.fr.yml"), "fr:\n")
      File.write(File.join(dir, "devise.en.yml"), "en:\n")

      dump_into(dir)

      refute File.exist?(File.join(dir, "escriba.fr.yml"))
      assert File.exist?(File.join(dir, "devise.en.yml"))
    end
  end

  def test_dumps_plural_values_and_plural_skeletons_from_the_source_forms
    source = { "one" => "1 file", "other" => "%{count} files" }
    create_row(key: KEY_B, locale: :en, value: source, source_copy: source, plural: true)
    create_row(key: KEY_B, locale: :es, value: { "other" => "%{count} fitxers", "one" => "1 fitxer" },
      source_copy: source, plural: true)

    Dir.mktmpdir do |dir|
      dump_into(dir)

      assert_equal({ "one" => "1 fitxer", "other" => "%{count} fitxers" },
        parsed(dir, :es).dig("es", "escriba", KEY_B))
      assert_equal({ "one" => "", "other" => "" },
        parsed(dir, :it).dig("it", "escriba", KEY_B))
    end
  end

  def test_annotates_entries_with_the_source_copy_and_meaning
    create_row(key: KEY_A, locale: :en, value: "Save", meaning: "verb, button label")

    Dir.mktmpdir do |dir|
      dump_into(dir)
      content = File.read(File.join(dir, "escriba.es.yml"))

      assert_includes content, "# Save"
      assert_includes content, "# meaning: verb, button label"
    end
  end

  def test_merges_extracted_strings_into_the_catalog
    create_row(key: KEY_A, locale: :en, value: "Save")
    extracted = [
      Escriba::SourceExtractor::ExtractedString.new(
        key: KEY_B, source_copy: "Brand new", meaning: nil, plural: false, interpolation_names: []
      ),
      # Same key as the DB row — the DB row wins, no duplicate entry.
      Escriba::SourceExtractor::ExtractedString.new(
        key: KEY_A, source_copy: "Save", meaning: nil, plural: false, interpolation_names: []
      ),
    ]

    Dir.mktmpdir do |dir|
      Escriba::YmlDumper.new(dir: dir, extracted: extracted).dump!

      assert_equal({ "es" => { "escriba" => { KEY_B => "", KEY_A => "" } } }, parsed(dir, :es))
      assert_includes File.read(File.join(dir, "escriba.es.yml")), "# Brand new"
    end
  end

  def test_empty_catalog_still_writes_skeleton_files
    Dir.mktmpdir do |dir|
      files = dump_into(dir)

      assert_equal 3, files.size
      assert_equal({ "es" => { "escriba" => {} } }, parsed(dir, :es))
    end
  end
end
