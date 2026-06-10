# frozen_string_literal: true

module Escriba
  class IssuesController < ApplicationController
    def index
      # The Issues page surfaces quality problems with *existing* values (plain
      # "missing" entries are handled by the per-locale Missing filter), which
      # is exactly what the issues column caches at write time.
      locales = editable_locales.map(&:to_s) - [dev_locale.to_s]
      scope = Escriba::Translation
        .where(locale: locales)
        .with_issues
        .order(:locale, :source_copy)

      @pagy, @rows = pagy(:offset, scope, limit: PER_PAGE)
    end
  end
end
