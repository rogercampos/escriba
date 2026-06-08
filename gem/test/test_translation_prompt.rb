# frozen_string_literal: true

require "test_helper"

class TestTranslationPrompt < Minitest::Test
  def setup
    Escriba::Translation.delete_all
  end

  def create_row(key:, value:, source_copy: value, meaning: nil, plural: false, interpolation_names: nil)
    Escriba::Translation.create!(
      key: key, locale: "en", value: value, source_copy: source_copy,
      meaning: meaning, plural: plural, interpolation_names: interpolation_names
    )
  end

  def prompt(rows, locale: :es, dev_locale: :en)
    Escriba::TranslationPrompt.call(locale: locale, dev_locale: dev_locale, rows: rows)
  end

  def test_contains_language_names_rules_schema_and_input
    row = create_row(key: "a" * 16, value: "Hello %{name}", interpolation_names: ["name"])
    out = prompt([row])

    assert_includes out, "English (en)"
    assert_includes out, "Spanish (es)"
    assert_includes out, "%{name}"                 # placeholder rule
    assert_includes out, "^[a-f0-9]{16}$"          # embedded JSON Schema
    assert_includes out, row.key                   # input data
    assert_includes out, "placeholders"
  end

  def test_pins_locale_in_the_embedded_schema
    row = create_row(key: "a" * 16, value: "Save")
    out = prompt([row], locale: :it)
    # The schema's locale enum is the single target locale.
    assert_match(/"locale".*\n.*"enum".*\n.*"it"/, out)
  end

  def test_falls_back_to_locale_code_for_unknown_language
    row = create_row(key: "a" * 16, value: "Save")
    out = prompt([row], locale: :xx)
    assert_includes out, "(xx)"
  end

  def test_plural_row_is_included_as_an_object_with_forms
    forms = { "one" => "1 item", "other" => "%{count} items" }
    row = create_row(key: "b" * 16, value: forms, source_copy: forms, plural: true, interpolation_names: ["count"])
    out = prompt([row])

    assert_includes out, %("plural": true)
    assert_includes out, "1 item"
    assert_includes out, "%{count} items"
  end

  def test_meaning_included_in_input_only_when_present
    with = create_row(key: "c" * 16, value: "Save", meaning: "to store")
    without = create_row(key: "d" * 16, value: "Cancel")

    # The rules text always mentions the "meaning" field; assert against the JSON
    # key form ("meaning":) that only appears in the input data.
    assert_includes prompt([with]), %("meaning": "to store")
    refute_includes prompt([without]), %("meaning":)
  end
end
