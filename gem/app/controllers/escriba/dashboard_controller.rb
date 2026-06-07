# frozen_string_literal: true

module Escriba
  class DashboardController < ApplicationController
    SCAN_LIMIT = 500

    def index
      # "Known strings" = distinct keys seen so far. This is a lower bound until
      # static extraction lands (strings are discovered at runtime).
      @total = Escriba::Translation.distinct.count(:key)

      @locales = editable_locales.map(&:to_sym).reject { |l| l == dev_locale }
      @stats = @locales.to_h do |locale|
        translated = Escriba::Translation.for_locale(locale).where.not(value: nil).count
        [locale, { translated: translated, missing: [@total - translated, 0].max }]
      end

      # Most recently added source strings (their dev_locale row is inserted when
      # the string is first seen). created_at is the best proxy available today.
      @recent_copies = Escriba::Translation
        .for_locale(dev_locale)
        .order(created_at: :desc)
        .limit(8)

      # Lint summary across editable locales, by issue type (excludes plain
      # "missing" — that's covered per-locale by the completeness cards / Missing
      # filter). Links through to the Issues page.
      dev_rows = Escriba::Translation.for_locale(dev_locale).limit(SCAN_LIMIT).to_a
      dev_keys = dev_rows.map(&:key)
      @issue_counts = Hash.new(0)
      @locales.each do |locale|
        values = Escriba::Translation.where(locale: locale.to_s, key: dev_keys).index_by(&:key)
        dev_rows.each do |dev|
          translation_issues(dev, values[dev.key]).each do |issue|
            @issue_counts[issue.code] += 1 unless issue.code == :missing
          end
        end
      end
      @issue_total = @issue_counts.values.sum
    end
  end
end
