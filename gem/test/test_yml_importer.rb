# frozen_string_literal: true

require "test_helper"
require "tmpdir"

class TestYmlImporter < Minitest::Test
  def setup
    Escriba.reset_config!
    Escriba::Translation.delete_all
    Escriba.config.available_locales = %i[en es]
  end

  def teardown
    Escriba.reset_config!
  end

  KEY = "d" * 16

  def create_dev_row(key: KEY, source_copy: "Save", interpolation_names: nil, plural: false)
    Escriba::Translation.create!(
      key: key, locale: "en", value: source_copy, source_copy: source_copy,
      interpolation_names: interpolation_names, plural: plural
    )
  end

  def with_yml(locale, entries)
    Dir.mktmpdir do |dir|
      File.write(File.join(dir, "escriba.#{locale}.yml"),
        YAML.dump({ locale.to_s => { "escriba" => entries } }))
      return yield(dir)
    end
  end

  def import(dir, extracted: [], overwrite: false)
    Escriba::YmlImporter.new(dir: dir, extracted: extracted, overwrite: overwrite)
  end

  def extracted_string(copy)
    Escriba::SourceExtractor::ExtractedString.new(
      key: Escriba::KeyDeriver.for_singular(copy), source_copy: copy,
      meaning: nil, plural: false, interpolation_names: Escriba::KeyDeriver.interpolation_names(copy)
    )
  end

  def test_fills_values_the_database_has_blank
    create_dev_row
    with_yml(:es, { KEY => "Guardar" }) do |dir|
      result = import(dir).apply!

      assert_equal 1, result[:created]
      assert_equal "Guardar", Escriba::Translation.find_by(key: KEY, locale: "es").value
    end
  end

  def test_never_overwrites_an_existing_database_value
    create_dev_row
    Escriba::Translation.create!(key: KEY, locale: "es", value: "Guardar (admin)", source_copy: "Save")

    with_yml(:es, { KEY => "Guardar (yml)" }) do |dir|
      importer = import(dir)
      assert_equal 1, importer.summary[:kept]
      importer.apply!

      assert_equal "Guardar (admin)", Escriba::Translation.find_by(key: KEY, locale: "es").value
    end
  end

  # The one case the default cannot serve: the source copy is unchanged, so the
  # key is unchanged, so a row already exists and no file edit can ever reach
  # it. Without this the value in the repo and the value in production disagree
  # forever, and only the admin UI can settle it.
  def test_overwrite_replaces_a_value_that_differs
    create_dev_row
    Escriba::Translation.create!(key: KEY, locale: "es", value: "Guardar (old)", source_copy: "Save")

    with_yml(:es, { KEY => "Guardar (new)" }) do |dir|
      importer = import(dir, overwrite: true)

      assert_equal 1, importer.summary[:overwrite]
      assert_equal 0, importer.summary[:kept]
      assert_equal({ created: 0, updated: 1 }, importer.apply!)
      assert_equal "Guardar (new)", Escriba::Translation.find_by(key: KEY, locale: "es").value
    end
  end

  # So an operator can see what they are about to discard. The reconciler
  # carries the old value on the operation for exactly this.
  def test_overwrite_reports_the_value_it_would_replace_before_applying
    create_dev_row
    Escriba::Translation.create!(key: KEY, locale: "es", value: "Guardar (old)", source_copy: "Save")

    with_yml(:es, { KEY => "Guardar (new)" }) do |dir|
      operation = import(dir, overwrite: true).operations.find { |op| op.status == :overwrite }

      assert_equal "Guardar (old)", operation.old_value
      assert_equal "Guardar (new)", operation.new_value
      assert_equal "Guardar (old)", Escriba::Translation.find_by(key: KEY, locale: "es").value
    end
  end

  # Overwriting is about the database losing to the file, not about the file
  # losing its guard rails: a value that would land in the Issues page the
  # moment it was written is still refused.
  def test_overwrite_still_rejects_values_with_error_level_lint_issues
    create_dev_row(source_copy: "Hello %{name}", interpolation_names: ["name"])
    Escriba::Translation.create!(key: KEY, locale: "es", value: "Hola %{name}", source_copy: "Hello %{name}")

    with_yml(:es, { KEY => "Hola %{nombre}" }) do |dir|
      importer = import(dir, overwrite: true)
      importer.apply!

      assert_equal 1, importer.summary[:invalid]
      assert_equal "Hola %{name}", Escriba::Translation.find_by(key: KEY, locale: "es").value
    end
  end

  # A blank entry is "not translated here", never "clear what you have" — which
  # would otherwise make one OVERWRITE run wipe every value the files have no
  # opinion about.
  def test_overwrite_leaves_a_value_alone_when_the_file_entry_is_blank
    create_dev_row
    Escriba::Translation.create!(key: KEY, locale: "es", value: "Guardar", source_copy: "Save")

    with_yml(:es, { KEY => "" }) do |dir|
      import(dir, overwrite: true).apply!

      assert_equal "Guardar", Escriba::Translation.find_by(key: KEY, locale: "es").value
    end
  end

  def test_overwrite_is_idempotent
    create_dev_row
    Escriba::Translation.create!(key: KEY, locale: "es", value: "Guardar (old)", source_copy: "Save")

    with_yml(:es, { KEY => "Guardar (new)" }) do |dir|
      import(dir, overwrite: true).apply!
      second = import(dir, overwrite: true)

      assert_equal({ created: 0, updated: 0 }, second.apply!)
      assert_equal 1, second.summary[:unchanged]
    end
  end

  def test_skips_blank_skeleton_entries
    create_dev_row
    with_yml(:es, { KEY => "" }) do |dir|
      import(dir).apply!

      refute Escriba::Translation.exists?(key: KEY, locale: "es")
    end
  end

  def test_rejects_values_with_error_level_lint_issues
    create_dev_row(source_copy: "Hello %{name}", interpolation_names: ["name"])
    with_yml(:es, { KEY => "Hola %{nombre}" }) do |dir|
      importer = import(dir)
      importer.apply!

      assert_equal 1, importer.summary[:invalid]
      refute Escriba::Translation.exists?(key: KEY, locale: "es")
    end
  end

  def test_seeds_dev_rows_from_extraction_and_imports_brand_new_strings
    entry = extracted_string("Brand new")
    with_yml(:es, { entry.key => "Nuevo" }) do |dir|
      import(dir, extracted: [entry]).apply!

      dev = Escriba::Translation.find_by(key: entry.key, locale: "en")
      assert_equal "Brand new", dev.source_copy
      assert_equal "Nuevo", Escriba::Translation.find_by(key: entry.key, locale: "es").value
    end
  end

  def test_imports_plural_values
    source = { "one" => "1 file", "other" => "%{count} files" }
    create_dev_row(source_copy: source, plural: true)

    with_yml(:es, { KEY => { "one" => "1 fitxer", "other" => "%{count} fitxers" } }) do |dir|
      import(dir).apply!

      assert_equal({ "one" => "1 fitxer", "other" => "%{count} fitxers" },
        Escriba::Translation.find_by(key: KEY, locale: "es").value)
    end
  end

  def test_is_idempotent
    create_dev_row
    with_yml(:es, { KEY => "Guardar" }) do |dir|
      import(dir).apply!
      second = import(dir)
      result = second.apply!

      assert_equal 0, result[:created]
      assert_equal 1, second.summary[:unchanged]
      assert_equal 1, Escriba::Translation.where(key: KEY, locale: "es").count
    end
  end

  def test_drops_non_string_plural_forms_from_hand_edited_files
    source = { "one" => "1 file", "other" => "%{count} files" }
    create_dev_row(source_copy: source, plural: true)

    # Unquoted numbers in the yml parse as Integers — they must never be written.
    with_yml(:es, { KEY => { "one" => 1, "other" => 2 } }) do |dir|
      import(dir).apply!

      refute Escriba::Translation.exists?(key: KEY, locale: "es")
    end
  end

  def test_invalid_yaml_raises_an_error_naming_the_file
    create_dev_row
    Dir.mktmpdir do |dir|
      File.write(File.join(dir, "escriba.es.yml"), "es:\n  escriba:\n bad: indent\n")

      error = assert_raises(Escriba::InvalidDumpFile) { import(dir).apply! }
      assert_includes error.message, "escriba.es.yml"
    end
  end

  def test_supports_yaml_aliases_in_hand_edited_files
    create_dev_row
    Dir.mktmpdir do |dir|
      File.write(File.join(dir, "escriba.es.yml"), <<~YML)
        es:
          escriba:
            #{KEY}: &shared Guardar
      YML

      import(dir).apply!
      assert_equal "Guardar", Escriba::Translation.find_by(key: KEY, locale: "es").value
    end
  end

  def test_reports_unmatched_keys_and_ignores_unknown_locales
    with_yml(:es, { "f" * 16 => "Huérfano" }) do |dir|
      File.write(File.join(dir, "escriba.xx.yml"), YAML.dump({ "xx" => { "escriba" => { KEY => "?" } } }))
      importer = import(dir)
      importer.apply!

      assert_equal 1, importer.summary[:unmatched]
      assert_equal 0, Escriba::Translation.count
    end
  end
end
