# frozen_string_literal: true

module Escriba
  # Stub only — the view describes the planned import/export workflow; no
  # backend is wired yet.
  class ImportExportController < ApplicationController
    def index
      @locales = editable_locales.map(&:to_sym).reject { |l| l == dev_locale }
    end
  end
end
