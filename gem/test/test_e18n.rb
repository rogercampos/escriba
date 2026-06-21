# frozen_string_literal: true

require "test_helper"

class TestE18n < Minitest::Test
  def setup
    Escriba.reset_config!
    Escriba.reset_cache!
    Escriba::Translation.delete_all
    I18n.locale = :en
    ENV["ESCRIBA_ENV"] = "test"
  end

  def teardown
    ENV["ESCRIBA_ENV"] = "test"
    Escriba.reset_cache!
    I18n.locale = :en
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

  def test_plural_rejects_positional_arg
    assert_raises(Escriba::ArgumentError) do
      E18n.t("a copy", one: "1", other: "%{count}", count: 1)
    end
  end

  # ---------------- Dev/test + dev_locale (short-circuit) ----------------

  def test_dev_test_dev_locale_returns_source_directly
    result = E18n.t("Save")
    assert_equal "Save", result
  end

  def test_dev_test_dev_locale_does_not_hit_db
    E18n.t("Save")
    assert_equal 0, Escriba::Translation.count
  end

  def test_dev_test_dev_locale_interpolates
    result = E18n.t("Hello %{name}", name: "Roger")
    assert_equal "Hello Roger", result
  end

  def test_dev_test_dev_locale_pluralizes_one
    result = E18n.t(one: "1 item", other: "%{count} items", count: 1)
    assert_equal "1 item", result
  end

  def test_dev_test_dev_locale_pluralizes_other
    result = E18n.t(one: "1 item", other: "%{count} items", count: 5)
    assert_equal "5 items", result
  end

  def test_dev_test_dev_locale_does_not_seed_for_plural
    E18n.t(one: "1 item", other: "%{count} items", count: 3)
    assert_equal 0, Escriba::Translation.count
  end

  # ---------------- Dev/test + non-dev_locale (fallback) ----------------

  def test_dev_test_non_dev_locale_falls_back_to_source
    I18n.locale = :es
    result = E18n.t("Save")
    assert_equal "Save", result
  end

  def test_dev_test_non_dev_locale_does_not_write_to_db
    I18n.locale = :es
    E18n.t("Save")

    assert_equal 0, Escriba::Translation.count
  end

  def test_dev_test_non_dev_locale_does_not_create_target_locale_row
    I18n.locale = :es
    E18n.t("Save")
    refute Escriba::Translation.exists?(locale: "es")
  end

  def test_dev_test_non_dev_locale_uses_db_translation_when_present
    hash_key = Escriba::KeyDeriver.for_singular("Save")
    Escriba::Translation.create!(
      key: hash_key, locale: "es",
      value: "Guardar", source_copy: "Save",
    )

    I18n.locale = :es
    assert_equal "Guardar", E18n.t("Save")
  end

  def test_dev_test_non_dev_locale_interpolates_db_translation
    hash_key = Escriba::KeyDeriver.for_singular("Hello %{name}")
    Escriba::Translation.create!(
      key: hash_key, locale: "es",
      value: "Hola %{name}", source_copy: "Hello %{name}",
      interpolation_names: ["name"],
    )

    I18n.locale = :es
    assert_equal "Hola Roger", E18n.t("Hello %{name}", name: "Roger")
  end

  def test_dev_test_non_dev_locale_pluralizes_db_translation
    hash_key = Escriba::KeyDeriver.for_plural(one: "1 item", other: "%{count} items")
    Escriba::Translation.create!(
      key: hash_key, locale: "es", plural: true,
      value: { "one" => "1 elemento", "other" => "%{count} elementos" },
      source_copy: { "one" => "1 item", "other" => "%{count} items" },
    )

    I18n.locale = :es
    assert_equal "1 elemento",
      E18n.t(one: "1 item", other: "%{count} items", count: 1)
    assert_equal "5 elementos",
      E18n.t(one: "1 item", other: "%{count} items", count: 5)
  end

  # ---------------- Production + dev_locale (served from source, no write) ----------------

  def test_prod_dev_locale_returns_source_without_writing
    ENV["ESCRIBA_ENV"] = "production"
    Escriba.reset_cache!

    result = E18n.t("Save")
    assert_equal "Save", result

    # The read path never writes: the catalog is populated at deploy time by
    # the static extractor, not lazily on lookup.
    assert_equal 0, Escriba::Translation.count
  end

  def test_prod_dev_locale_uses_db_value_when_already_present
    ENV["ESCRIBA_ENV"] = "production"
    Escriba.reset_cache!

    hash_key = Escriba::KeyDeriver.for_singular("Save")
    Escriba::Translation.create!(
      key: hash_key, locale: "en",
      value: "Save (edited)", source_copy: "Save",
    )

    assert_equal "Save (edited)", E18n.t("Save")
  end

  # ---------------- Production + non-dev_locale (fallback, no write) ----------------

  def test_prod_non_dev_locale_falls_back_to_source_without_writing
    ENV["ESCRIBA_ENV"] = "production"
    Escriba.reset_cache!

    I18n.locale = :es
    result = E18n.t("Save")

    # No DB row and no YAML entry: the I18n fallback chain resolves es -> en,
    # and the dev locale serves the source copy in code.
    assert_equal "Save", result

    assert_equal 0, Escriba::Translation.count
  end

  def test_prod_non_dev_locale_uses_db_translation_when_present
    ENV["ESCRIBA_ENV"] = "production"
    Escriba.reset_cache!

    hash_key = Escriba::KeyDeriver.for_singular("Save")
    Escriba::Translation.create!(
      key: hash_key, locale: "en",
      value: "Save", source_copy: "Save",
    )
    Escriba::Translation.create!(
      key: hash_key, locale: "es",
      value: "Guardar", source_copy: "Save",
    )

    I18n.locale = :es
    assert_equal "Guardar", E18n.t("Save")
  end

  # ---------------- Cache behavior ----------------

  def test_cache_avoids_repeat_db_hits
    ENV["ESCRIBA_ENV"] = "production"
    Escriba.reset_cache!

    hash_key = Escriba::KeyDeriver.for_singular("Greet")
    Escriba::Translation.create!(
      key: hash_key, locale: "en",
      value: "Greet", source_copy: "Greet",
    )

    E18n.t("Greet") # primes cache

    # Delete the row underneath — cache should still serve it.
    Escriba::Translation.delete_all
    assert_equal "Greet", E18n.t("Greet")
  end

  # ---------------- Meaning disambiguation ----------------

  def test_meaning_routes_to_distinct_db_rows
    ENV["ESCRIBA_ENV"] = "production"
    Escriba.reset_cache!

    store_key = Escriba::KeyDeriver.for_singular("Save", meaning: "to store")
    rescue_key = Escriba::KeyDeriver.for_singular("Save", meaning: "to rescue")
    refute_equal store_key, rescue_key

    I18n.locale = :es
    Escriba::Translation.create!(key: store_key, locale: "es", value: "Guardar", source_copy: "Save")
    Escriba::Translation.create!(key: rescue_key, locale: "es", value: "Rescatar", source_copy: "Save")

    assert_equal "Guardar", E18n.t("Save", meaning: "to store")
    assert_equal "Rescatar", E18n.t("Save", meaning: "to rescue")
  end

  # ---------------- Plural fallback ----------------

  def test_dev_test_non_dev_locale_plural_falls_back_to_dev_source
    I18n.locale = :es
    assert_equal "1 item",
      E18n.t(one: "1 item", other: "%{count} items", count: 1)
    assert_equal "5 items",
      E18n.t(one: "1 item", other: "%{count} items", count: 5)
  end

  def test_dev_test_non_dev_locale_plural_does_not_write_to_db
    I18n.locale = :es
    E18n.t(one: "1 item", other: "%{count} items", count: 3)

    assert_equal 0, Escriba::Translation.count
  end

  def test_prod_non_dev_locale_plural_falls_back_without_writing
    ENV["ESCRIBA_ENV"] = "production"
    Escriba.reset_cache!

    I18n.locale = :es
    result = E18n.t(one: "1 item", other: "%{count} items", count: 7)
    assert_equal "7 items", result

    assert_equal 0, Escriba::Translation.count
  end

  # ---------------- dev_locale_from_code mode ----------------

  def test_prod_dev_locale_from_code_short_circuits_to_source
    ENV["ESCRIBA_ENV"] = "production"
    Escriba.reset_cache!
    Escriba.configure { |c| c.dev_locale_from_code = true }

    assert_equal "Save", E18n.t("Save")
    assert_equal 0, Escriba::Translation.where(locale: "en").count
  end

  def test_prod_dev_locale_from_code_ignores_db_row_for_dev_locale
    ENV["ESCRIBA_ENV"] = "production"
    Escriba.reset_cache!
    Escriba.configure { |c| c.dev_locale_from_code = true }

    hash_key = Escriba::KeyDeriver.for_singular("Save")
    Escriba::Translation.create!(
      key: hash_key, locale: "en",
      value: "Save (edited via UI)", source_copy: "Save",
    )

    assert_equal "Save", E18n.t("Save")
  end

  def test_prod_dev_locale_from_code_non_dev_locale_falls_back_without_writing
    ENV["ESCRIBA_ENV"] = "production"
    Escriba.reset_cache!
    Escriba.configure { |c| c.dev_locale_from_code = true }

    I18n.locale = :es
    # es has no DB row and no YAML: the fallback chain resolves to the dev
    # locale, which is served from source code. Nothing is written.
    assert_equal "Save", E18n.t("Save")

    assert_equal 0, Escriba::Translation.count
  end

  def test_prod_dev_locale_from_code_still_serves_non_dev_locale_from_db
    ENV["ESCRIBA_ENV"] = "production"
    Escriba.reset_cache!
    Escriba.configure { |c| c.dev_locale_from_code = true }

    hash_key = Escriba::KeyDeriver.for_singular("Save")
    Escriba::Translation.create!(
      key: hash_key, locale: "es",
      value: "Guardar", source_copy: "Save",
    )

    I18n.locale = :es
    assert_equal "Guardar", E18n.t("Save")
  end

  def test_prod_dev_locale_from_code_pluralizes_source_directly
    ENV["ESCRIBA_ENV"] = "production"
    Escriba.reset_cache!
    Escriba.configure { |c| c.dev_locale_from_code = true }

    assert_equal "1 item",
      E18n.t(one: "1 item", other: "%{count} items", count: 1)
    assert_equal "7 items",
      E18n.t(one: "1 item", other: "%{count} items", count: 7)
    assert_equal 0, Escriba::Translation.count
  end

  # ---------------- Non-Escriba I18n keys still work ----------------

  def test_non_escriba_keys_pass_through_to_simple_backend
    I18n.backend.store_translations(:en, hello: "world")
    assert_equal "world", I18n.t("hello")
  end

  # ---------------- YAML fallback (dumped escriba.<locale>.yml files) ----------------

  def store_yml(locale, hash_key, value)
    I18n.backend.store_translations(locale, escriba: { hash_key => value })
  end

  def test_prod_non_dev_locale_falls_back_to_yml_when_db_has_no_value
    ENV["ESCRIBA_ENV"] = "production"
    Escriba.reset_cache!
    store_yml(:es, Escriba::KeyDeriver.for_singular("Save"), "Guardar")

    I18n.locale = :es
    assert_equal "Guardar", E18n.t("Save")
  ensure
    I18n.backend.reload!
  end

  def test_prod_db_translation_wins_over_yml
    ENV["ESCRIBA_ENV"] = "production"
    Escriba.reset_cache!

    hash_key = Escriba::KeyDeriver.for_singular("Save")
    Escriba::Translation.create!(key: hash_key, locale: "en", value: "Save", source_copy: "Save")
    Escriba::Translation.create!(key: hash_key, locale: "es", value: "Guardar (DB)", source_copy: "Save")
    store_yml(:es, hash_key, "Guardar (YML)")

    I18n.locale = :es
    assert_equal "Guardar (DB)", E18n.t("Save")
  ensure
    I18n.backend.reload!
  end

  def test_prod_blank_yml_skeleton_entries_count_as_missing
    ENV["ESCRIBA_ENV"] = "production"
    Escriba.reset_cache!
    store_yml(:es, Escriba::KeyDeriver.for_singular("Save"), "")

    I18n.locale = :es
    # Falls back through the chain to the dev-locale source copy, not to "".
    assert_equal "Save", E18n.t("Save")
  ensure
    I18n.backend.reload!
  end

  def test_prod_whitespace_only_yml_entries_count_as_missing
    ENV["ESCRIBA_ENV"] = "production"
    Escriba.reset_cache!
    store_yml(:es, Escriba::KeyDeriver.for_singular("Save"), "  ")

    I18n.locale = :es
    assert_equal "Save", E18n.t("Save")
  ensure
    I18n.backend.reload!
  end

  def test_prod_non_string_yml_scalars_count_as_missing
    ENV["ESCRIBA_ENV"] = "production"
    Escriba.reset_cache!
    # A hand-edited file with unquoted scalars: YAML types them as Integer/true.
    store_yml(:es, Escriba::KeyDeriver.for_singular("Save"), 123)
    store_yml(:es, Escriba::KeyDeriver.for_singular("Enabled"), true)

    I18n.locale = :es
    assert_equal "Save", E18n.t("Save")
    assert_equal "Enabled", E18n.t("Enabled")
  ensure
    I18n.backend.reload!
  end

  def test_prod_plural_yml_fallback_pluralizes_and_skips_blank_forms
    ENV["ESCRIBA_ENV"] = "production"
    Escriba.reset_cache!

    hash_key = Escriba::KeyDeriver.for_plural(one: "1 file", other: "%{count} files")
    store_yml(:es, hash_key, { one: "", other: "%{count} fitxers" })

    I18n.locale = :es
    assert_equal "2 fitxers", E18n.t(one: "1 file", other: "%{count} files", count: 2)
  ensure
    I18n.backend.reload!
  end

  def test_prod_yml_fallback_is_cached
    ENV["ESCRIBA_ENV"] = "production"
    Escriba.reset_cache!
    store_yml(:es, Escriba::KeyDeriver.for_singular("Save"), "Guardar")

    I18n.locale = :es
    E18n.t("Save") # primes the cache from the YAML store

    I18n.backend.reload! # wipes the YAML store — the cache should still serve it
    assert_equal "Guardar", E18n.t("Save")
  end
end
