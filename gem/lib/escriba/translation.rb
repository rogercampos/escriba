# frozen_string_literal: true

require "active_record"

module Escriba
  class Translation < ActiveRecord::Base
    self.table_name = "escriba_translations"

    serialize :value, coder: JSON
    serialize :source_copy, coder: JSON
    serialize :interpolation_names, coder: JSON

    validates :key, presence: true, length: { maximum: 32 }
    validates :locale, presence: true, length: { maximum: 16 }
    validates :source_copy, presence: true
    validates :key, uniqueness: { scope: :locale }

    scope :for_locale, ->(locale) { where(locale: locale.to_s) }
    scope :for_key,    ->(key)    { where(key: key) }

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
  end
end
