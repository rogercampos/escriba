# frozen_string_literal: true

require "test_helper"

class TestKeyDeriver < Minitest::Test
  KD = Escriba::KeyDeriver

  # --- normalize_whitespace ---

  def test_normalize_whitespace_strips_ends
    assert_equal "Save", KD.normalize_whitespace("  Save  ")
  end

  def test_normalize_whitespace_collapses_internal_runs
    assert_equal "Hello world", KD.normalize_whitespace("Hello   world")
  end

  def test_normalize_whitespace_collapses_newlines_and_tabs
    assert_equal "a b c", KD.normalize_whitespace("a\n\tb\r\nc")
  end

  def test_normalize_whitespace_preserves_single_spaces
    assert_equal "Hello world", KD.normalize_whitespace("Hello world")
  end

  # --- ordinalize_interpolations ---

  def test_ordinalize_single_variable
    assert_equal "Hello %{1}", KD.ordinalize_interpolations("Hello %{name}")
  end

  def test_ordinalize_two_distinct_variables
    assert_equal "Hi %{1}, you have %{2} messages",
      KD.ordinalize_interpolations("Hi %{name}, you have %{count} messages")
  end

  def test_ordinalize_repeats_same_variable_with_same_ordinal
    assert_equal "Hi %{1}, %{1} again",
      KD.ordinalize_interpolations("Hi %{name}, %{name} again")
  end

  def test_ordinalize_uses_first_appearance_order
    assert_equal "%{1} %{2} %{1}",
      KD.ordinalize_interpolations("%{a} %{b} %{a}")
  end

  def test_ordinalize_handles_no_interpolations
    assert_equal "plain", KD.ordinalize_interpolations("plain")
  end

  # --- interpolation_names ---

  def test_interpolation_names_returns_names_in_first_appearance_order
    assert_equal %w[name count], KD.interpolation_names("Hello %{name}, %{count} items")
  end

  def test_interpolation_names_deduplicates
    assert_equal %w[name], KD.interpolation_names("%{name} and %{name}")
  end

  def test_interpolation_names_returns_empty_array_when_none
    assert_equal [], KD.interpolation_names("no vars here")
  end

  # --- for_singular ---

  def test_for_singular_returns_16_char_hex
    key = KD.for_singular("Save")
    assert_match(/\A[a-f0-9]{16}\z/, key)
  end

  def test_for_singular_is_deterministic
    assert_equal KD.for_singular("Save"), KD.for_singular("Save")
  end

  def test_for_singular_meaning_changes_key
    refute_equal KD.for_singular("Save"), KD.for_singular("Save", meaning: "to store")
  end

  def test_for_singular_different_meanings_produce_different_keys
    refute_equal KD.for_singular("Save", meaning: "to store"),
      KD.for_singular("Save", meaning: "to rescue")
  end

  def test_for_singular_whitespace_normalization_does_not_affect_key
    assert_equal KD.for_singular("Save"),
      KD.for_singular("  Save  ")
    assert_equal KD.for_singular("Hello world"),
      KD.for_singular("Hello\n\tworld")
  end

  def test_for_singular_ignores_interpolation_variable_names
    assert_equal KD.for_singular("Hello %{name}"),
      KD.for_singular("Hello %{user_name}")
  end

  def test_for_singular_distinguishes_interpolation_position
    refute_equal KD.for_singular("%{a} %{b}"),
      KD.for_singular("%{a} %{b} %{c}")
  end

  def test_for_singular_distinguishes_repeated_vs_unique_interpolations
    refute_equal KD.for_singular("%{x} %{x}"), KD.for_singular("%{x} %{y}")
  end

  # --- for_plural ---

  def test_for_plural_returns_16_char_hex
    key = KD.for_plural(one: "1 item", other: "%{count} items")
    assert_match(/\A[a-f0-9]{16}\z/, key)
  end

  def test_for_plural_is_deterministic_regardless_of_key_order
    a = KD.for_plural(one: "1 item", other: "%{count} items")
    b = KD.for_plural(other: "%{count} items", one: "1 item")
    assert_equal a, b
  end

  def test_for_plural_meaning_changes_key
    a = KD.for_plural(one: "1 item", other: "%{count} items")
    b = KD.for_plural(one: "1 item", other: "%{count} items", meaning: "inbox")
    refute_equal a, b
  end

  def test_for_plural_differs_from_singular_with_same_copy
    refute_equal KD.for_singular("%{count} items"),
      KD.for_plural(other: "%{count} items")
  end

  def test_for_plural_only_normalizes_whitespace
    a = KD.for_plural(one: "1 item", other: "%{count} items")
    b = KD.for_plural(one: "  1   item  ", other: "%{count}\titems")
    assert_equal a, b
  end

  def test_for_plural_changing_one_form_changes_key
    a = KD.for_plural(one: "1 item", other: "%{count} items")
    b = KD.for_plural(one: "one item", other: "%{count} items")
    refute_equal a, b
  end

  def test_for_plural_ignores_interpolation_variable_names
    a = KD.for_plural(one: "1 item", other: "%{count} items")
    b = KD.for_plural(one: "1 item", other: "%{n} items")
    assert_equal a, b
  end
end
