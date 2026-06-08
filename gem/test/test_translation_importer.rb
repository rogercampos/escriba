# frozen_string_literal: true

require "test_helper"

class TestTranslationImporter < Minitest::Test
  def setup
    Escriba::Translation.delete_all
  end

  def create_row(key:, locale:, value:, source_copy: value, meaning: nil, plural: false)
    Escriba::Translation.create!(
      key: key, locale: locale.to_s, value: value, source_copy: source_copy,
      meaning: meaning, plural: plural, interpolation_names: nil
    )
  end

  def importer(csv, locales: %i[es it fr])
    Escriba::TranslationImporter.new(csv, locales: locales, dev_locale: :en)
  end

  def statuses(csv, **kwargs)
    importer(csv, **kwargs).operations.map(&:status)
  end

  KEY = "a" * 16

  def test_match_by_key_creates_when_no_existing_value
    create_row(key: KEY, locale: :en, value: "Save")
    csv = "key,source,es\n#{KEY},Save,Guardar\n"

    ops = importer(csv).operations
    assert_equal 1, ops.size
    assert_equal :create, ops.first.status
    assert_equal "Guardar", ops.first.new_value
  end

  def test_match_by_source_copy_when_key_absent
    create_row(key: KEY, locale: :en, value: "Save")
    csv = "key,source,es\n,Save,Guardar\n"

    ops = importer(csv).operations
    assert_equal [:create], ops.map(&:status)
    assert_equal KEY, ops.first.key
  end

  def test_overwrite_when_value_differs
    create_row(key: KEY, locale: :en, value: "Save")
    create_row(key: KEY, locale: :es, value: "Guardar")
    csv = "key,source,es\n#{KEY},Save,Conservar\n"

    op = importer(csv).operations.first
    assert_equal :overwrite, op.status
    assert_equal "Guardar", op.old_value
    assert_equal "Conservar", op.new_value
  end

  def test_unchanged_when_value_equal
    create_row(key: KEY, locale: :en, value: "Save")
    create_row(key: KEY, locale: :es, value: "Guardar")
    csv = "key,source,es\n#{KEY},Save,Guardar\n"

    assert_equal [:unchanged], statuses(csv)
  end

  def test_unmatched_when_no_dev_string
    csv = "key,source,es\n#{'f' * 16},Nope,Nada\n"
    op = importer(csv).operations.first
    assert_equal :unmatched, op.status
    assert_equal "Nope", op.source
  end

  def test_blank_value_cell_produces_no_operation
    create_row(key: KEY, locale: :en, value: "Save")
    csv = "key,source,es\n#{KEY},Save,\n"
    assert_empty importer(csv).operations
  end

  def test_detects_locale_columns_and_imports_several_at_once
    create_row(key: KEY, locale: :en, value: "Save")
    csv = "key,source,es,it\n#{KEY},Save,Guardar,Salva\n"

    imp = importer(csv)
    assert_equal %i[es it], imp.detected_locales
    by_locale = imp.operations.to_h { |op| [op.locale, op] }
    assert_equal "Guardar", by_locale["es"].new_value
    assert_equal "Salva", by_locale["it"].new_value
    assert_equal [:create, :create], imp.operations.map(&:status)
  end

  def test_value_columns_empty_when_no_known_locale_header
    create_row(key: KEY, locale: :en, value: "Save")
    csv = "key,source,de\n#{KEY},Save,Speichern\n"
    assert_empty importer(csv).value_columns
    assert_empty importer(csv).operations
  end

  def test_ignores_unknown_locale_columns
    create_row(key: KEY, locale: :en, value: "Save")
    csv = "key,source,es,de\n#{KEY},Save,Guardar,Speichern\n"

    imp = importer(csv)
    assert_equal %i[es], imp.detected_locales
    assert_equal [:create], imp.operations.map(&:status)
    assert_equal "es", imp.operations.first.locale
  end

  def test_plural_reconstructs_value_hash
    forms = { "one" => "1 item", "other" => "%{count} items" }
    create_row(key: KEY, locale: :en, value: forms, source_copy: forms, plural: true)
    csv = +"key,plural_form,source,es\n"
    csv << "#{KEY},one,1 item,1 elemento\n"
    csv << "#{KEY},other,%{count} items,%{count} elementos\n"

    ops = importer(csv).operations
    assert_equal 1, ops.size
    op = ops.first
    assert_equal :create, op.status
    assert_equal({ "one" => "1 elemento", "other" => "%{count} elementos" }, op.new_value)
  end

  def test_invalid_interpolation_is_blocked_not_written
    create_row(key: KEY, locale: :en, value: "Hello %{name}", source_copy: "Hello %{name}")
    csv = "key,source,es\n#{KEY},Hello %{name},Hola %{nombre}\n"

    op = importer(csv).operations.first
    assert_equal :invalid, op.status
    assert(op.issues.any? { |i| i.code == :unknown_interpolation })

    assert_equal({ created: 0, updated: 0 }, importer(csv).apply!)
    assert_nil Escriba::Translation.find_by(key: KEY, locale: "es")
  end

  def test_missing_interpolation_is_blocked
    create_row(key: KEY, locale: :en, value: "Hello %{name}", source_copy: "Hello %{name}")
    csv = "key,source,es\n#{KEY},Hello %{name},Hola\n"

    op = importer(csv).operations.first
    assert_equal :invalid, op.status
    assert(op.issues.any? { |i| i.code == :missing_interpolation })
  end

  def test_overwrite_with_broken_interpolation_does_not_replace_existing
    create_row(key: KEY, locale: :en, value: "Hello %{name}", source_copy: "Hello %{name}")
    create_row(key: KEY, locale: :es, value: "Hola %{name}", source_copy: "Hello %{name}")
    csv = "key,source,es\n#{KEY},Hello %{name},Hola %{nombre}\n"

    assert_equal [:invalid], statuses(csv)
    importer(csv).apply!
    assert_equal "Hola %{name}", Escriba::Translation.find_by(key: KEY, locale: "es").value
  end

  def test_valid_interpolation_imports_normally
    create_row(key: KEY, locale: :en, value: "Hello %{name}", source_copy: "Hello %{name}")
    csv = "key,source,es\n#{KEY},Hello %{name},Hola %{name}\n"

    op = importer(csv).operations.first
    assert_equal :create, op.status
    assert_empty op.issues
  end

  def test_untranslated_warning_still_imports
    # Value identical to source is a *warning*, not an error — it still imports.
    create_row(key: KEY, locale: :en, value: "Save", source_copy: "Save")
    csv = "key,source,es\n#{KEY},Save,Save\n"

    op = importer(csv).operations.first
    assert_equal :create, op.status
    assert(op.issues.any? { |i| i.code == :untranslated })
    assert_equal({ created: 1, updated: 0 }, importer(csv).apply!)
  end

  def test_apply_writes_rows_and_is_idempotent
    create_row(key: KEY, locale: :en, value: "Save")
    csv = "key,source,es\n#{KEY},Save,Guardar\n"

    result = importer(csv).apply!
    assert_equal({ created: 1, updated: 0 }, result)
    row = Escriba::Translation.find_by(key: KEY, locale: "es")
    assert_equal "Guardar", row.value
    assert_equal "Save", row.source_copy

    # Re-applying the same CSV now classifies as unchanged → no writes.
    again = importer(csv)
    assert_equal [:unchanged], again.operations.map(&:status)
    assert_equal({ created: 0, updated: 0 }, again.apply!)
  end

  def test_round_trip_export_then_import_is_all_unchanged
    create_row(key: KEY, locale: :en, value: "Save")
    create_row(key: KEY, locale: :es, value: "Guardar")
    plural = { "one" => "1 item", "other" => "%{count} items" }
    es_plural = { "one" => "1 elemento", "other" => "%{count} elementos" }
    create_row(key: "b" * 16, locale: :en, value: plural, source_copy: plural, plural: true)
    create_row(key: "b" * 16, locale: :es, value: es_plural, source_copy: plural, plural: true)

    csv = Escriba::TranslationExporter.call(locale: :es, dev_locale: :en, locales: %i[es])
    statuses = importer(csv).operations.map(&:status)
    assert_equal [:unchanged, :unchanged], statuses
  end
end
