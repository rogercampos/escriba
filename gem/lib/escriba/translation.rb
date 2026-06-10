# frozen_string_literal: true

require "active_record"

module Escriba
  class Translation < ActiveRecord::Base
    self.table_name = "escriba_translations"

    serialize :value, coder: JSON
    serialize :source_copy, coder: JSON
    serialize :interpolation_names, coder: JSON
    serialize :issues, coder: JSON

    validates :key, presence: true, length: { maximum: 32 }
    validates :locale, presence: true, length: { maximum: 16 }
    validates :source_copy, presence: true
    validates :key, uniqueness: { scope: :locale }

    before_save :refresh_issues

    scope :for_locale, ->(locale) { where(locale: locale.to_s) }
    scope :for_key,    ->(key)    { where(key: key) }
    scope :with_issues, -> { where.not(issues: nil) }

    # The cached lint issues as TranslationValidator::Issue structs (the shape
    # the views expect). Never includes :missing — a missing translation is
    # `value IS NULL` (or no row at all), not a cached issue.
    def issue_list
      Array(issues).map do |issue|
        Escriba::TranslationValidator::Issue.new(code: issue["code"].to_sym, message: issue["message"])
      end
    end

    def self.upsert_dev_locale(key, dev_locale, source)
      now = Time.current
      attrs = {
        key: key,
        locale: dev_locale.to_s,
        value: source[:value].is_a?(Hash) ? source[:value].transform_keys(&:to_s) : source[:value],
        source_copy: source[:value].is_a?(Hash) ? source[:value].transform_keys(&:to_s) : source[:value],
        meaning: source[:meaning],
        interpolation_names: source[:interpolation_names],
        plural: source[:plural],
        created_at: now,
        updated_at: now,
      }
      insert_all([attrs], unique_by: %i[key locale])
    end

    private

    # Lint the value at write time and cache the result, so list pages can
    # filter/count by `issues IS NOT NULL` instead of re-validating the whole
    # catalog per request. Every validation input lives on the row itself
    # (source_copy & co. are content-addressed by the key, so only the value
    # ever changes), which is what makes a per-row cache sound.
    def refresh_issues
      if locale.to_s == Escriba.config.dev_locale.to_s
        self.issues = nil
        return
      end

      list = Escriba::TranslationValidator.call(
        value: value,
        source_copy: source_copy,
        source_interpolations: interpolation_names,
        plural: plural,
      )

      if list.any? { |i| i.code == :missing }
        # Blank values (e.g. a plural hash with every form cleared) normalize
        # to NULL, keeping `value IS NULL` ⇔ "missing" true for SQL callers.
        self.value = nil
        self.issues = nil
      else
        self.issues = list.empty? ? nil : list.map { |i| { "code" => i.code.to_s, "message" => i.message } }
      end
    end
  end
end
