# frozen_string_literal: true

require "test_helper"
require "tmpdir"

class TestYmlDumper < Minitest::Test
  def setup
    Escriba.reset_config!
    Escriba.config.available_locales = %i[en es it]
  end

  def teardown
    Escriba.reset_config!
  end

  def singular(copy, meaning: nil)
    Escriba::SourceExtractor::ExtractedString.new(
      key: Escriba::KeyDeriver.for_singular(copy, meaning: meaning), source_copy: copy, meaning: meaning,
      plural: false, interpolation_names: Escriba::KeyDeriver.interpolation_names(copy)
    )
  end

  def plural(**forms)
    Escriba::SourceExtractor::ExtractedString.new(
      key: Escriba::KeyDeriver.for_plural(**forms), source_copy: forms.transform_keys(&:to_s), meaning: nil,
      plural: true, interpolation_names: forms.values.flat_map { |v| Escriba::KeyDeriver.interpolation_names(v) }.uniq
    )
  end

  def dump(dir, *extracted)
    Escriba::YmlDumper.new(dir: dir, extracted: extracted).dump!
  end

  def write_yml(dir, locale, entries)
    File.write(File.join(dir, "escriba.#{locale}.yml"), YAML.dump(locale.to_s => { "escriba" => entries }))
  end

  def entries(dir, locale)
    YAML.safe_load(File.read(File.join(dir, "escriba.#{locale}.yml"), encoding: Encoding::UTF_8)).dig(locale.to_s, "escriba")
  end

  def test_writes_a_skeleton_file_per_translated_locale_and_none_for_the_dev_locale
    save = singular("Save")

    Dir.mktmpdir do |dir|
      files = dump(dir, save)

      assert_equal %w[escriba.es.yml escriba.it.yml], files.map { |f| File.basename(f) }
      assert_equal({ save.key => "" }, entries(dir, :es))
      assert_equal({ save.key => "" }, entries(dir, :it))
    end
  end

  def test_keeps_the_values_already_in_the_files
    save = singular("Save")
    delete = singular("Delete")

    Dir.mktmpdir do |dir|
      write_yml(dir, :es, { save.key => "Guardar" })

      dump(dir, save, delete)

      assert_equal({ delete.key => "", save.key => "Guardar" }, entries(dir, :es))
    end
  end

  def test_drops_entries_for_strings_no_longer_in_the_source
    save = singular("Save")

    Dir.mktmpdir do |dir|
      write_yml(dir, :es, { save.key => "Guardar", "f" * 16 => "Huérfano" })

      dump(dir, save)

      assert_equal({ save.key => "Guardar" }, entries(dir, :es))
    end
  end

  def test_deletes_dumps_of_locales_no_longer_translated_but_leaves_other_yml_files_alone
    Dir.mktmpdir do |dir|
      File.write(File.join(dir, "escriba.fr.yml"), "fr:\n")
      File.write(File.join(dir, "escriba.en.yml"), "en:\n")
      File.write(File.join(dir, "devise.en.yml"), "en:\n")

      dump(dir, singular("Save"))

      assert_equal %w[devise.en.yml escriba.es.yml escriba.it.yml], Dir.children(dir).sort
    end
  end

  def test_dumps_plural_values_in_cldr_order_and_plural_skeletons_from_the_source_forms
    files = plural(one: "1 file", other: "%{count} files")

    Dir.mktmpdir do |dir|
      write_yml(dir, :es, { files.key => { "other" => "%{count} fitxers", "one" => "1 fitxer" } })

      dump(dir, files)

      assert_equal({ "one" => "1 fitxer", "other" => "%{count} fitxers" }, entries(dir, :es)[files.key])
      assert_match(/one: 1 fitxer\n.*other:/m, File.read(File.join(dir, "escriba.es.yml"), encoding: Encoding::UTF_8))
      assert_equal({ "one" => "", "other" => "" }, entries(dir, :it)[files.key])
    end
  end

  def test_annotates_entries_with_the_source_copy_and_meaning
    Dir.mktmpdir do |dir|
      dump(dir, singular("Save", meaning: "verb, button label"))
      content = File.read(File.join(dir, "escriba.es.yml"), encoding: Encoding::UTF_8)

      assert_includes content, "# Save"
      assert_includes content, "# meaning: verb, button label"
    end
  end

  def test_orders_entries_by_source_copy_then_meaning
    Dir.mktmpdir do |dir|
      dump(dir, singular("Save", meaning: "to store"), singular("Delete"), singular("Save", meaning: "to rescue"))
      content = File.read(File.join(dir, "escriba.es.yml"), encoding: Encoding::UTF_8)

      comments = content.scan(/# (?:meaning: )?(.+)$/).flatten.drop(2) # past the header
      assert_equal ["Delete", "Save", "to rescue", "Save", "to store"], comments
    end
  end

  def test_contents_previews_the_dump_without_writing
    Dir.mktmpdir do |dir|
      contents = Escriba::YmlDumper.new(dir: dir, extracted: [singular("Save")]).contents

      assert_equal %w[escriba.es.yml escriba.it.yml], contents.keys.map { |path| File.basename(path) }
      assert_empty Dir.children(dir)
    end
  end

  def test_an_empty_catalog_still_writes_the_files
    Dir.mktmpdir do |dir|
      dump(dir)

      assert_equal({ "es" => { "escriba" => {} } }, YAML.safe_load(File.read(File.join(dir, "escriba.es.yml"), encoding: Encoding::UTF_8)))
    end
  end

  def test_a_file_with_invalid_yaml_is_named
    Dir.mktmpdir do |dir|
      File.write(File.join(dir, "escriba.es.yml"), "es:\n  escriba: [\n")

      error = assert_raises(Escriba::InvalidDumpFile) { dump(dir, singular("Save")) }
      assert_includes error.message, "escriba.es.yml"
    end
  end
end
