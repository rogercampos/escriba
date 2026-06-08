# frozen_string_literal: true

require "csv"

module Escriba
  # Bulk file workflows for translations: export to CSV for hand-off, and import
  # a filled-in CSV back through a dry-run preview. The heavy lifting lives in
  # Escriba::TranslationExporter / Escriba::TranslationImporter; this controller
  # only handles params, the upload and the preview→apply round-trip.
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

    def preview
      file = params[:file]
      return redirect_to(import_export_path, alert: "Choose a CSV file to import.") if file.blank?

      @csv = file.read.to_s.force_encoding("UTF-8")
      importer = build_importer(@csv)

      if importer.value_columns.empty?
        return redirect_to import_export_path,
          alert: "The file has no locale columns to import. Add a column named after each " \
            "locale (e.g. #{importable_locales.join(', ')})."
      end

      if importer.row_count > MAX_IMPORT_ROWS
        return redirect_to import_export_path,
          alert: "That file has more than #{MAX_IMPORT_ROWS} rows — split it into smaller files."
      end

      @detected_locales = importer.detected_locales
      @operations = importer.operations
      @summary = importer.summary
    end

    def apply
      result = build_importer(params[:csv].to_s).apply!

      redirect_to import_export_path,
        notice: "Imported #{result[:created]} new and updated #{result[:updated]} existing " \
          "translations. Changes go live on the next deploy."
    end

    private

    def build_importer(csv)
      Escriba::TranslationImporter.new(csv, locales: importable_locales, dev_locale: dev_locale)
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
