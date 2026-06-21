# frozen_string_literal: true

module Escriba
  class DashboardController < ApplicationController
    def index
      # "Known strings" = distinct keys in the catalog. The catalog is
      # populated by static extraction at deploy time (escriba:import_yml), so
      # this reflects every extractable E18n.t call, not just executed ones.
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
      # filter). Reads the per-row issues cached at write time, so only the
      # problematic rows' issues column is loaded. Links through to the Issues page.
      @issue_counts = Hash.new(0)
      Escriba::Translation
        .where(locale: @locales.map(&:to_s))
        .with_issues
        .pluck(:issues)
        .each do |list|
          Array(list).each { |issue| @issue_counts[issue["code"].to_sym] += 1 }
        end
      @issue_total = @issue_counts.values.sum

      # Edits newer than the last publish (deploy/restart) — running processes
      # may still serve the previous value for these. Dev-locale rows don't
      # count when the dev locale is served from source code.
      pending = Escriba::Translation.pending_publish
      pending = pending.where.not(locale: dev_locale.to_s) if dev_locale_from_code?
      @pending_count = pending.count
    end
  end
end
