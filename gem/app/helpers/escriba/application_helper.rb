# frozen_string_literal: true

module Escriba
  module ApplicationHelper
    def render_source(row)
      render_value_hash_or_string(row.source_copy, plural: row.plural)
    end

    def render_value(row)
      render_value_hash_or_string(row.value, plural: row.plural)
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
