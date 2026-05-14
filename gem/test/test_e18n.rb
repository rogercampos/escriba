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

  def test_dev_test_non_dev_locale_seeds_dev_locale_row
    I18n.locale = :es
    E18n.t("Save")

    rows = Escriba::Translation.all.to_a
    assert_equal 1, rows.size
    assert_equal "en", rows.first.locale
    assert_equal "Save", rows.first.value
    assert_equal "Save", rows.first.source_copy
    refute rows.first.plural
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

  # ---------------- Production + dev_locale (auto-seed) ----------------

  def test_prod_dev_locale_inserts_row_and_returns_source
    ENV["ESCRIBA_ENV"] = "production"
    Escriba.reset_cache!

    result = E18n.t("Save")
    assert_equal "Save", result

    row = Escriba::Translation.find_by(locale: "en")
    assert row
    assert_equal "Save", row.value
    assert_equal "Save", row.source_copy
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

  def test_prod_dev_locale_concurrent_inserts_do_not_raise
    ENV["ESCRIBA_ENV"] = "production"
    Escriba.reset_cache!

    hash_key = Escriba::KeyDeriver.for_singular("Concurrent")
    Escriba::Translation.create!(
      key: hash_key, locale: "en",
      value: "Concurrent", source_copy: "Concurrent",
    )

    assert_equal "Concurrent", E18n.t("Concurrent")
  end

  # ---------------- Production + non-dev_locale (seed dev row, fallback) ----------------

  def test_prod_non_dev_locale_seeds_dev_row_and_falls_back
    ENV["ESCRIBA_ENV"] = "production"
    Escriba.reset_cache!

    I18n.locale = :es
    result = E18n.t("Save")

    # Falls back through the chain to dev_locale (en), which after the seed
    # has value "Save" in the DB.
    assert_equal "Save", result

    assert Escriba::Translation.exists?(locale: "en")
    refute Escriba::Translation.exists?(locale: "es")
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

  def test_meaning_produces_distinct_storage
    ENV["ESCRIBA_ENV"] = "production"
    Escriba.reset_cache!

    E18n.t("Save", meaning: "to store")
    E18n.t("Save", meaning: "to rescue")

    keys = Escriba::Translation.pluck(:key).uniq
    assert_equal 2, keys.size
  end

  def test_meaning_is_stored_with_the_row
    ENV["ESCRIBA_ENV"] = "production"
    Escriba.reset_cache!

    E18n.t("Save", meaning: "to store")

    row = Escriba::Translation.first
    assert_equal "to store", row.meaning
  end

  # ---------------- Plural fallback ----------------

  def test_dev_test_non_dev_locale_plural_falls_back_to_dev_source
    I18n.locale = :es
    assert_equal "1 item",
      E18n.t(one: "1 item", other: "%{count} items", count: 1)
    assert_equal "5 items",
      E18n.t(one: "1 item", other: "%{count} items", count: 5)
  end

  def test_dev_test_non_dev_locale_plural_seeds_dev_locale_row
    I18n.locale = :es
    E18n.t(one: "1 item", other: "%{count} items", count: 3)

    row = Escriba::Translation.find_by(locale: "en")
    assert row
    assert row.plural
    assert_equal({ "one" => "1 item", "other" => "%{count} items" }, row.value)
  end

  def test_prod_non_dev_locale_plural_seeds_dev_row_and_falls_back
    ENV["ESCRIBA_ENV"] = "production"
    Escriba.reset_cache!

    I18n.locale = :es
    result = E18n.t(one: "1 item", other: "%{count} items", count: 7)
    assert_equal "7 items", result

    row = Escriba::Translation.find_by(locale: "en")
    assert row
    assert row.plural
  end

  # ---------------- Interpolation names recorded ----------------

  def test_seeded_row_records_interpolation_names
    ENV["ESCRIBA_ENV"] = "production"
    Escriba.reset_cache!

    E18n.t("Hello %{name}, you have %{count} messages", name: "x", count: 0)
    row = Escriba::Translation.first
    assert_equal %w[name count], row.interpolation_names
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

  def test_prod_dev_locale_from_code_still_seeds_dev_row_for_discovery
    ENV["ESCRIBA_ENV"] = "production"
    Escriba.reset_cache!
    Escriba.configure { |c| c.dev_locale_from_code = true }

    I18n.locale = :es
    assert_equal "Save", E18n.t("Save")

    assert Escriba::Translation.exists?(locale: "en")
    refute Escriba::Translation.exists?(locale: "es")
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
end
