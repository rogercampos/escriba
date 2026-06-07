# frozen_string_literal: true

require "test_helper"

class TestTranslationValidator < Minitest::Test
  def codes(**kwargs)
    Escriba::TranslationValidator.call(**kwargs).map(&:code)
  end

  # ---------------- singular ----------------

  def test_singular_ok
    assert_empty codes(value: "Guardar", source_copy: "Save")
  end

  def test_singular_missing_when_nil
    assert_equal [:missing], codes(value: nil, source_copy: "Save")
  end

  def test_singular_missing_when_blank
    assert_equal [:missing], codes(value: "   ", source_copy: "Save")
  end

  def test_singular_untranslated_when_identical_to_source
    assert_equal [:untranslated], codes(value: "Save", source_copy: "Save")
  end

  def test_singular_unknown_interpolation
    issues = codes(value: "Hola %{nombre}", source_copy: "Hello %{name}")
    assert_includes issues, :unknown_interpolation
    assert_includes issues, :missing_interpolation # %{name} dropped
  end

  def test_singular_missing_interpolation
    assert_equal [:missing_interpolation],
      codes(value: "Hola", source_copy: "Hello %{name}")
  end

  def test_singular_interpolation_ok
    assert_empty codes(value: "Hola %{name}", source_copy: "Hello %{name}")
  end

  def test_explicit_source_interpolations_used_over_derivation
    # source_copy has no placeholders, but the stored shape says it should.
    assert_equal [:missing_interpolation],
      codes(value: "Hola", source_copy: "Hello", source_interpolations: %w[name])
  end

  # ---------------- plural ----------------

  def test_plural_ok
    assert_empty codes(
      value: { "one" => "1 elemento", "other" => "%{count} elementos" },
      source_copy: { "one" => "1 item", "other" => "%{count} items" },
      plural: true,
    )
  end

  def test_plural_missing_when_empty
    assert_equal [:missing], codes(value: {}, source_copy: { "other" => "%{count} items" }, plural: true)
  end

  def test_plural_missing_other_form
    issues = codes(
      value: { "one" => "1 elemento" },
      source_copy: { "one" => "1 item", "other" => "%{count} items" },
      plural: true,
    )
    assert_includes issues, :missing_plural_other
  end

  def test_plural_one_form_may_omit_count_without_missing_interpolation
    # "one" has no %{count}; plural must NOT flag missing_interpolation.
    assert_empty codes(
      value: { "one" => "un elemento", "other" => "%{count} elementi" },
      source_copy: { "one" => "1 item", "other" => "%{count} items" },
      plural: true,
    )
  end

  def test_plural_unknown_interpolation_in_a_form
    assert_equal [:unknown_interpolation], codes(
      value: { "one" => "1 elemento", "other" => "%{cuenta} elementos" },
      source_copy: { "one" => "1 item", "other" => "%{count} items" },
      plural: true,
    )
  end

  def test_plural_untranslated_when_forms_identical_to_source
    assert_includes codes(
      value: { "one" => "1 item", "other" => "%{count} items" },
      source_copy: { "one" => "1 item", "other" => "%{count} items" },
      plural: true,
    ), :untranslated
  end
end
