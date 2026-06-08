# frozen_string_literal: true

require "test_helper"
require "csv"

class TestTranslationExporter < Minitest::Test
  def setup
    Escriba::Translation.delete_all
  end

  def create_row(key:, locale:, value:, source_copy: value, meaning: nil, plural: false)
    Escriba::Translation.create!(
      key: key, locale: locale.to_s, value: value, source_copy: source_copy,
      meaning: meaning, plural: plural, interpolation_names: nil
    )
  end

  def export(locale:, only_missing: false, locales: %i[es it])
    Escriba::TranslationExporter.call(
      locale: locale, dev_locale: :en, locales: locales, only_missing: only_missing
    )
  end

  def test_singular_single_locale
    create_row(key: "a" * 16, locale: :en, value: "Save")
    create_row(key: "a" * 16, locale: :es, value: "Guardar")

    table = CSV.parse(export(locale: :es), headers: true)
    assert_equal %w[key plural_form source meaning es], table.headers
    assert_equal 1, table.size
    row = table.first
    assert_equal "a" * 16, row["key"]
    assert_equal "Save", row["source"]
    assert_equal "Guardar", row["es"]
    assert_nil row["plural_form"]
  end

  def test_meaning_is_exported
    create_row(key: "b" * 16, locale: :en, value: "Save", meaning: "to store")
    table = CSV.parse(export(locale: :es), headers: true)
    assert_equal "to store", table.first["meaning"]
  end

  def test_plural_expands_to_one_row_per_form
    forms = { "one" => "1 item", "other" => "%{count} items" }
    es    = { "one" => "1 elemento", "other" => "%{count} elementos" }
    create_row(key: "c" * 16, locale: :en, value: forms, source_copy: forms, plural: true)
    create_row(key: "c" * 16, locale: :es, value: es, source_copy: forms, plural: true)

    rows = CSV.parse(export(locale: :es), headers: true)
    assert_equal 2, rows.size
    one = rows.find { |r| r["plural_form"] == "one" }
    other = rows.find { |r| r["plural_form"] == "other" }
    assert_equal "1 item", one["source"]
    assert_equal "1 elemento", one["es"]
    assert_equal "%{count} elementos", other["es"]
  end

  def test_all_locales_emits_a_column_per_locale
    create_row(key: "d" * 16, locale: :en, value: "Save")
    create_row(key: "d" * 16, locale: :es, value: "Guardar")
    create_row(key: "d" * 16, locale: :it, value: "Salva")

    table = CSV.parse(export(locale: "all"), headers: true)
    assert_equal %w[key plural_form source meaning es it], table.headers
    row = table.first
    assert_equal "Guardar", row["es"]
    assert_equal "Salva", row["it"]
  end

  def test_missing_value_is_blank
    create_row(key: "e" * 16, locale: :en, value: "Save")
    row = CSV.parse(export(locale: :es), headers: true).first
    assert_equal "", row["es"].to_s
  end

  def test_only_missing_skips_fully_translated_strings
    create_row(key: "f" * 16, locale: :en, value: "Save")
    create_row(key: "f" * 16, locale: :es, value: "Guardar")
    create_row(key: "0" * 16, locale: :en, value: "Cancel") # untranslated in es

    rows = CSV.parse(export(locale: :es, only_missing: true), headers: true)
    assert_equal ["Cancel"], rows.map { |r| r["source"] }
  end
end
