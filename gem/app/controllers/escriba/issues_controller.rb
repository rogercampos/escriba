# frozen_string_literal: true

module Escriba
  class IssuesController < ApplicationController
    SCAN_LIMIT = 500

    def index
      dev_rows = Escriba::Translation.for_locale(dev_locale).order(:source_copy).limit(SCAN_LIMIT).to_a
      @scanned = dev_rows.size
      @capped = @scanned == SCAN_LIMIT
      dev_keys = dev_rows.map(&:key)

      @issues = []
      editable_locales.map(&:to_sym).reject { |l| l == dev_locale }.each do |locale|
        values = Escriba::Translation.where(locale: locale.to_s, key: dev_keys).index_by(&:key)
        dev_rows.each do |dev|
          # The Issues page surfaces quality problems with *existing* values;
          # plain "missing" entries are handled by the per-locale Missing filter.
          list = translation_issues(dev, values[dev.key]).reject { |i| i.code == :missing }
          @issues << { locale: locale, dev: dev, issues: list } if list.any?
        end
      end
    end
  end
end
