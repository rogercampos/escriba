# frozen_string_literal: true

require "test_helper"

class TestTranslation < Minitest::Test
  def setup
    Escriba.reset_config!
    Escriba::Translation.delete_all
  end

  KEY = "b" * 16

  def create_row(locale:, value:, source_copy: "Save", interpolation_names: nil, plural: false)
    Escriba::Translation.create!(
      key: KEY, locale: locale.to_s, value: value, source_copy: source_copy,
      interpolation_names: interpolation_names, plural: plural
    )
  end

  def test_clean_value_caches_no_issues
    row = create_row(locale: :es, value: "Guardar")
    assert_nil row.issues
    assert_empty row.issue_list
  end

  def test_untranslated_value_caches_the_issue
    row = create_row(locale: :es, value: "Save")
    issues = row.issue_list
    assert_equal [:untranslated], issues.map(&:code)
    assert_kind_of String, issues.first.message
  end

  def test_interpolation_issues_are_cached
    row = Escriba::Translation.create!(
      key: KEY, locale: "es", value: "Hola %{nombre}",
      source_copy: "Hello %{name}", interpolation_names: ["name"]
    )
    assert_equal %i[unknown_interpolation missing_interpolation], row.issue_list.map(&:code)
  end

  def test_dev_locale_rows_cache_nothing
    row = create_row(locale: :en, value: "Save")
    assert_nil row.issues
  end

  def test_cache_refreshes_when_the_value_changes
    row = create_row(locale: :es, value: "Save")
    refute_nil row.issues

    row.update!(value: "Guardar")
    assert_nil row.reload.issues
  end

  def test_blank_plural_value_normalizes_to_nil
    row = Escriba::Translation.create!(
      key: KEY, locale: "es", value: { "other" => "" },
      source_copy: { "one" => "One file", "other" => "%{count} files" }, plural: true
    )
    assert_nil row.value
    assert_nil row.issues
  end

  def test_with_issues_scope_finds_only_problematic_rows
    create_row(locale: :es, value: "Save")
    create_row(locale: :it, value: "Salva")

    assert_equal ["es"], Escriba::Translation.with_issues.pluck(:locale)
  end

  def test_rows_saved_after_boot_are_pending_publish
    row = create_row(locale: :es, value: "Guardar")

    assert row.pending_publish?
    assert_includes Escriba::Translation.pending_publish, row
  end

  def test_rows_untouched_since_boot_are_not_pending_publish
    row = create_row(locale: :es, value: "Guardar")
    row.update_columns(updated_at: Escriba.booted_at - 60)

    refute row.reload.pending_publish?
    assert_empty Escriba::Translation.pending_publish.to_a
  end

  # ---------------- seed_dev_locale ----------------

  def test_seed_dev_locale_stores_value_meaning_and_interpolations
    source = {
      value: "Hello %{name}, you have %{count} messages",
      meaning: "greeting",
      plural: false,
      interpolation_names: %w[name count],
    }
    Escriba::Translation.seed_dev_locale(:en, [[KEY, source]])

    row = Escriba::Translation.find_by(key: KEY, locale: "en")
    assert_equal "Hello %{name}, you have %{count} messages", row.value
    assert_equal "Hello %{name}, you have %{count} messages", row.source_copy
    assert_equal "greeting", row.meaning
    assert_equal %w[name count], row.interpolation_names
    refute row.plural
  end

  def test_seed_dev_locale_stores_plural_forms
    source = {
      value: { "one" => "1 item", "other" => "%{count} items" },
      meaning: nil, plural: true, interpolation_names: ["count"],
    }
    Escriba::Translation.seed_dev_locale(:en, [[KEY, source]])

    row = Escriba::Translation.find_by(key: KEY, locale: "en")
    assert row.plural
    assert_equal({ "one" => "1 item", "other" => "%{count} items" }, row.value)
  end

  def test_seed_dev_locale_is_insert_only_and_leaves_existing_rows_untouched
    create_row(locale: :en, value: "Save")
    source = { value: "Overwritten", meaning: nil, plural: false, interpolation_names: nil }
    Escriba::Translation.seed_dev_locale(:en, [[KEY, source]])

    assert_equal 1, Escriba::Translation.where(locale: "en").count
    assert_equal "Save", Escriba::Translation.find_by(key: KEY, locale: "en").value
  end
end
