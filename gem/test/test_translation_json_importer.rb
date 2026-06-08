# frozen_string_literal: true

require "test_helper"

class TestTranslationJsonImporter < Minitest::Test
  def setup
    Escriba::Translation.delete_all
  end

  def create_row(key:, value:, source_copy: value, plural: false, interpolation_names: nil)
    Escriba::Translation.create!(
      key: key, locale: "en", value: value, source_copy: source_copy,
      meaning: nil, plural: plural, interpolation_names: interpolation_names
    )
  end

  def importer(text, locales: %i[es it fr])
    Escriba::TranslationJsonImporter.new(text, locales: locales, dev_locale: :en)
  end

  KEY = "a" * 16

  def test_parses_plain_json_and_reconciles_by_key
    create_row(key: KEY, value: "Save")
    imp = importer(%([{"key":"#{KEY}","locale":"es","translation":"Guardar"}]))

    assert imp.valid?
    assert_equal [:es], imp.detected_locales
    op = imp.operations.first
    assert_equal :create, op.status
    assert_equal "Guardar", op.new_value
  end

  def test_strips_code_fences_and_surrounding_prose
    create_row(key: KEY, value: "Save")
    text = %(Sure! Here is your JSON:\n```json\n[{"key":"#{KEY}","locale":"es","translation":"Guardar"}]\n```\nHope it helps!)

    assert importer(text).valid?
    assert_equal "Guardar", importer(text).operations.first.new_value
  end

  def test_plural_object_becomes_a_value_hash
    forms = { "one" => "1 item", "other" => "%{count} items" }
    create_row(key: KEY, value: forms, source_copy: forms, plural: true, interpolation_names: ["count"])
    text = %([{"key":"#{KEY}","locale":"es","translation":{"one":"1 elemento","other":"%{count} elementos"}}])

    op = importer(text).operations.first
    assert_equal :create, op.status
    assert_equal({ "one" => "1 elemento", "other" => "%{count} elementos" }, op.new_value)
  end

  def test_broken_interpolation_is_blocked_invalid
    create_row(key: KEY, value: "Hello %{name}", source_copy: "Hello %{name}", interpolation_names: ["name"])
    text = %([{"key":"#{KEY}","locale":"es","translation":"Hola %{nombre}"}])

    op = importer(text).operations.first
    assert_equal :invalid, op.status
    assert(op.issues.any? { |i| i.code == :unknown_interpolation })
    assert_equal({ created: 0, updated: 0 }, importer(text).apply!)
    assert_nil Escriba::Translation.find_by(key: KEY, locale: "es")
  end

  def test_unknown_key_is_unmatched
    text = %([{"key":"#{'f' * 16}","locale":"es","translation":"x"}])
    op = importer(text).operations.first
    assert_equal :unmatched, op.status
  end

  def test_invalid_json_is_reported_not_raised
    imp = importer("this is not json at all")
    refute imp.valid?
    assert imp.errors.any?
    assert_empty imp.operations
  end

  def test_schema_violation_is_reported
    create_row(key: KEY, value: "Save")
    imp = importer(%([{"key":"short","locale":"es","translation":"x"}]))
    refute imp.valid?
    assert(imp.errors.any? { |e| e.include?("key") })
  end

  def test_locale_outside_the_importable_set_fails_schema
    create_row(key: KEY, value: "Save")
    imp = importer(%([{"key":"#{KEY}","locale":"de","translation":"x"}]), locales: %i[es])
    refute imp.valid?
  end

  def test_apply_writes_rows
    create_row(key: KEY, value: "Save")
    result = importer(%([{"key":"#{KEY}","locale":"es","translation":"Guardar"}])).apply!
    assert_equal({ created: 1, updated: 0 }, result)
    assert_equal "Guardar", Escriba::Translation.find_by(key: KEY, locale: "es").value
  end
end
