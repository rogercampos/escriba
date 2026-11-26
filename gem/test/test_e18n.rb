# frozen_string_literal: true

require "test_helper"
require "tmpdir"

class TestE18n < Minitest::Test
  def setup
    Escriba.reset_config!
    I18n.locale = :en
  end

  def teardown
    I18n.backend.reload!
    I18n.locale = :en
  end

  # What a config/locales/escriba.<locale>.yml file holds, once I18n loads it.
  def store_yml(locale, hash_key, value)
    I18n.backend.store_translations(locale, escriba: { hash_key => value })
  end

  # ---------------- Signature errors ----------------

  def test_singular_requires_a_string
    assert_raises(Escriba::ArgumentError) { E18n.t }
    assert_raises(Escriba::ArgumentError) { E18n.t(42) }
  end

  def test_singular_rejects_multiple_positional_args
    assert_raises(Escriba::ArgumentError) { E18n.t("a", "b") }
  end

  def test_plural_requires_count
    assert_raises(Escriba::ArgumentError) do
      E18n.t(one: "1 item", other: "%{count} items")
    end
  end

  def test_plural_requires_other_form
    assert_raises(Escriba::ArgumentError) do
      E18n.t(one: "1 item", count: 1)
    end
  end

  def test_plural_rejects_a_form_that_is_not_a_string
    error = assert_raises(Escriba::ArgumentError) do
      E18n.t(one: "1 item", other: 5, count: 1)
    end
    assert_equal "Plural form values must be Strings", error.message
  end

  def test_plural_rejects_positional_arg
    assert_raises(Escriba::ArgumentError) do
      E18n.t("a copy", one: "1", other: "%{count}", count: 1)
    end
  end

  # ---------------- Dev locale: the copy in the code ----------------

  def test_dev_locale_returns_the_source_copy
    assert_equal "Save", E18n.t("Save")
  end

  def test_dev_locale_interpolates
    assert_equal "Hello Roger", E18n.t("Hello %{name}", name: "Roger")
  end

  def test_dev_locale_pluralizes
    assert_equal "1 item", E18n.t(one: "1 item", other: "%{count} items", count: 1)
    assert_equal "5 items", E18n.t(one: "1 item", other: "%{count} items", count: 5)
  end

  def test_dev_locale_ignores_a_value_stored_for_it
    store_yml(:en, Escriba::KeyDeriver.for_singular("Save"), "Save (edited)")

    assert_equal "Save", E18n.t("Save")
  end

  # ---------------- Other locales: their YAML file ----------------

  def test_serves_the_translation_from_the_file
    store_yml(:es, Escriba::KeyDeriver.for_singular("Save"), "Guardar")

    I18n.locale = :es
    assert_equal "Guardar", E18n.t("Save")
  end

  def test_reads_escriba_files_from_the_i18n_load_path
    Dir.mktmpdir do |dir|
      path = File.join(dir, "escriba.es.yml")
      File.write(path, YAML.dump("es" => { "escriba" => { Escriba::KeyDeriver.for_singular("Delete") => "Borrar" } }))
      I18n.load_path += [path]
      I18n.backend.reload!

      I18n.locale = :es
      assert_equal "Borrar", E18n.t("Delete")
    ensure
      I18n.load_path -= [path]
    end
  end

  def test_interpolates_the_translation
    store_yml(:es, Escriba::KeyDeriver.for_singular("Hello %{name}"), "Hola %{name}")

    I18n.locale = :es
    assert_equal "Hola Roger", E18n.t("Hello %{name}", name: "Roger")
  end

  def test_pluralizes_the_translation
    store_yml(:es, Escriba::KeyDeriver.for_plural(one: "1 item", other: "%{count} items"),
      { one: "1 elemento", other: "%{count} elementos" })

    I18n.locale = :es
    assert_equal "1 elemento", E18n.t(one: "1 item", other: "%{count} items", count: 1)
    assert_equal "5 elementos", E18n.t(one: "1 item", other: "%{count} items", count: 5)
  end

  def test_meaning_selects_a_different_entry
    store_yml(:es, Escriba::KeyDeriver.for_singular("Save", meaning: "to store"), "Guardar")
    store_yml(:es, Escriba::KeyDeriver.for_singular("Save", meaning: "to rescue"), "Rescatar")

    I18n.locale = :es
    assert_equal "Guardar", E18n.t("Save", meaning: "to store")
    assert_equal "Rescatar", E18n.t("Save", meaning: "to rescue")
  end

  # ---------------- Untranslated: the fallback chain lands on the source ----------------

  def test_a_string_without_an_entry_falls_back_to_the_source_copy
    I18n.locale = :es
    assert_equal "Save", E18n.t("Save")
  end

  def test_a_plural_without_an_entry_falls_back_to_the_source_forms
    I18n.locale = :es
    assert_equal "1 item", E18n.t(one: "1 item", other: "%{count} items", count: 1)
    assert_equal "7 items", E18n.t(one: "1 item", other: "%{count} items", count: 7)
  end

  def test_blank_and_whitespace_entries_count_as_missing
    store_yml(:es, Escriba::KeyDeriver.for_singular("Save"), "")
    store_yml(:es, Escriba::KeyDeriver.for_singular("Delete"), "  ")

    I18n.locale = :es
    assert_equal "Save", E18n.t("Save")
    assert_equal "Delete", E18n.t("Delete")
  end

  def test_non_string_scalars_count_as_missing
    # A hand-edited file with unquoted scalars: YAML types them as Integer/true.
    store_yml(:es, Escriba::KeyDeriver.for_singular("Save"), 123)
    store_yml(:es, Escriba::KeyDeriver.for_singular("Enabled"), true)

    I18n.locale = :es
    assert_equal "Save", E18n.t("Save")
    assert_equal "Enabled", E18n.t("Enabled")
  end

  def test_blank_plural_forms_are_skipped
    store_yml(:es, Escriba::KeyDeriver.for_plural(one: "1 file", other: "%{count} files"),
      { one: "", other: "%{count} fitxers" })

    I18n.locale = :es
    assert_equal "2 fitxers", E18n.t(one: "1 file", other: "%{count} files", count: 2)
  end

  # ---------------- Non-Escriba I18n keys still work ----------------

  def test_non_escriba_keys_pass_through_to_the_simple_backend
    I18n.backend.store_translations(:en, hello: "world")
    assert_equal "world", I18n.t("hello")
  end
end
