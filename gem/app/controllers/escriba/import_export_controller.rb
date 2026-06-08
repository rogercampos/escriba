# frozen_string_literal: true

require "csv"

module Escriba
  # Bulk file/LLM workflows for translations: export to CSV for hand-off, generate
  # a ready-to-paste LLM prompt, and import a filled-in CSV or a pasted LLM JSON
  # reply through a dry-run preview. The work lives in Escriba::Translation*
  # POROs; this controller handles params, the upload and the preview→apply
  # round-trip.
  class ImportExportController < ApplicationController
    # Guard rail against pathologically large uploads. Real catalogs are far
    # smaller; over this we ask the user to split the file rather than carrying a
    # huge payload through the preview round-trip.
    MAX_IMPORT_ROWS = 5000

    def index
      @locales = importable_locales
    end

    def export
      locale = params[:locale].to_s
      return redirect_with_invalid_locale unless locale == "all" || importable_locales.map(&:to_s).include?(locale)

      csv = Escriba::TranslationExporter.call(
        locale: locale,
        dev_locale: dev_locale,
        locales: importable_locales,
        only_missing: params[:only_missing].present?,
      )

      send_data csv, type: "text/csv; charset=utf-8",
        filename: "escriba-#{locale}.csv", disposition: "attachment"
    end

    def prompt
      @locale = params[:locale].to_s
      return redirect_with_invalid_locale unless importable_locales.map(&:to_s).include?(@locale)

      only_missing = params[:only_missing].present?
      @rows = strings_to_translate(@locale, only_missing)
      if @rows.empty?
        scope = only_missing ? "missing " : ""
        return redirect_to import_export_path, notice: "Nothing to translate — #{@locale} has no #{scope}strings."
      end

      @prompt = Escriba::TranslationPrompt.call(locale: @locale, dev_locale: dev_locale, rows: @rows)
    end

    def preview
      return preview_json if params[:json].present?
      return preview_csv if params[:file].present?

      redirect_to import_export_path, alert: "Choose a CSV file or paste AI output to import."
    end

    def apply
      result = importer_for(params[:format].to_s, params[:payload].to_s).apply!

      redirect_to import_export_path,
        notice: "Imported #{result[:created]} new and updated #{result[:updated]} existing " \
          "translations. Changes go live on the next deploy."
    end

    private

    def preview_csv
      @format = "csv"
      @payload = params[:file].read.to_s.force_encoding("UTF-8")
      importer = Escriba::TranslationImporter.new(@payload, locales: importable_locales, dev_locale: dev_locale)

      if importer.value_columns.empty?
        return redirect_to import_export_path,
          alert: "The file has no locale columns to import. Add a column named after each " \
            "locale (e.g. #{importable_locales.join(', ')})."
      end

      if importer.row_count > MAX_IMPORT_ROWS
        return redirect_to import_export_path,
          alert: "That file has more than #{MAX_IMPORT_ROWS} rows — split it into smaller files."
      end

      assign_preview(importer)
      render :preview
    end

    def preview_json
      @format = "json"
      @payload = params[:json].to_s
      importer = Escriba::TranslationJsonImporter.new(@payload, locales: importable_locales, dev_locale: dev_locale)

      if importer.errors.any?
        @locales = importable_locales
        @json_input = @payload
        @json_errors = importer.errors
        return render :index, status: :unprocessable_entity
      end

      assign_preview(importer)
      render :preview
    end

    def assign_preview(importer)
      @detected_locales = importer.detected_locales
      @operations = importer.operations
      @summary = importer.summary
    end

    def importer_for(format, payload)
      if format == "json"
        Escriba::TranslationJsonImporter.new(payload, locales: importable_locales, dev_locale: dev_locale)
      else
        Escriba::TranslationImporter.new(payload, locales: importable_locales, dev_locale: dev_locale)
      end
    end

    # Dev strings to send to the LLM: all, or only those without a value yet in
    # the target locale.
    def strings_to_translate(locale, only_missing)
      dev_rows = Escriba::Translation.for_locale(dev_locale).order(:source_copy).to_a
      return dev_rows unless only_missing

      values = Escriba::Translation.where(locale: locale, key: dev_rows.map(&:key)).index_by(&:key)
      dev_rows.reject { |dev| present_value?(values[dev.key], dev.plural) }
    end

    def present_value?(row, plural)
      return false unless row

      value = row.value
      if plural
        value.is_a?(Hash) && value.values.any? { |s| !s.to_s.strip.empty? }
      else
        !value.to_s.strip.empty?
      end
    end

    # Locales an import can target / an export can include: editable, non-dev.
    def importable_locales
      editable_locales.map(&:to_sym).reject { |l| l == dev_locale }
    end

    def redirect_with_invalid_locale
      redirect_to import_export_path, alert: "Unknown locale."
    end
  end
end
