# frozen_string_literal: true

module Escriba
  module ApplicationHelper
    def render_source(row)
      render_value_hash_or_string(row.source_copy, plural: row.plural)
    end

    def render_value(row)
      render_value_hash_or_string(row.value, plural: row.plural)
    end

    # Plain-text (no markup) rendering of a source string, for compact/truncated
    # contexts like the dashboard lists and the Issues table.
    def source_text(row)
      value = row.source_copy
      if row.plural && value.is_a?(Hash)
        value.map { |k, v| "#{k}: #{v}" }.join(" · ")
      else
        value.to_s
      end
    end

    SEVERITY_CLASSES = {
      error: "bg-red-50 text-red-700 ring-1 ring-inset ring-red-600/10",
      warning: "bg-amber-50 text-amber-700 ring-1 ring-inset ring-amber-600/10",
    }.freeze

    # Render lint issues as small badges. By default the "missing" code is
    # skipped (the list/table already shows a "—" for missing values).
    def render_issue_badges(issues, skip_missing: true)
      issues = issues.reject { |i| i.code == :missing } if skip_missing
      return if issues.empty?

      safe_join(issues.map { |issue|
        severity = Escriba::TranslationValidator::ERROR_CODES.include?(issue.code) ? :error : :warning
        content_tag(:span, issue_label(issue.code),
          class: "inline-flex items-center rounded px-1.5 py-0.5 text-xs font-medium #{SEVERITY_CLASSES[severity]}",
          title: issue.message)
      }, " ")
    end

    def issue_label(code)
      {
        missing: "missing",
        untranslated: "untranslated",
        unknown_interpolation: "bad interpolation",
        missing_interpolation: "missing interpolation",
        missing_plural_other: "missing plural",
      }.fetch(code, code.to_s)
    end

    def completeness_percent(translated, total)
      return 0 if total.zero?

      ((translated.to_f / total) * 100).round
    end

    private

    def render_value_hash_or_string(value, plural:)
      if plural && value.is_a?(Hash)
        safe_join(value.map { |k, v| content_tag(:div, "#{k}: #{v}") })
      else
        value.to_s
      end
    end
  end
end
