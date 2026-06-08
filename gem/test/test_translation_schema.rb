# frozen_string_literal: true

require "test_helper"
require "json_schemer"

class TestTranslationSchema < Minitest::Test
  def schemer(locales = [:es])
    JSONSchemer.schema(Escriba::TranslationSchema.for(locales: locales))
  end

  def item(overrides = {})
    { "key" => "a" * 16, "locale" => "es", "translation" => "Hola" }.merge(overrides)
  end

  def test_compliant_singular_validates
    assert schemer.valid?([item])
  end

  def test_compliant_plural_validates
    assert schemer.valid?([item("translation" => { "one" => "1", "other" => "%{count}" })])
  end

  def test_bad_key_pattern_fails
    refute schemer.valid?([item("key" => "not-hex")])
  end

  def test_extra_property_fails
    refute schemer.valid?([item("note" => "nope")])
  end

  def test_empty_translation_fails
    refute schemer.valid?([item("translation" => "")])
  end

  def test_unknown_plural_form_fails
    refute schemer.valid?([item("translation" => { "bogus" => "x" })])
  end

  def test_missing_required_field_fails
    refute schemer.valid?([{ "key" => "a" * 16, "translation" => "x" }])
  end

  def test_locale_is_pinned_to_the_given_set
    refute schemer([:es]).valid?([item("locale" => "de")])
    assert schemer([:es, :it]).valid?([item("locale" => "it")])
  end

  def test_top_level_must_be_an_array
    refute schemer.valid?(item)
  end
end
