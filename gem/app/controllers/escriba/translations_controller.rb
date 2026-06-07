# frozen_string_literal: true

module Escriba
  class TranslationsController < ApplicationController
    LIST_LIMIT = 500
    FILTERS = %w[all missing issues].freeze

    def index
      @locale = current_locale_param
      @available_locales = editable_locales
      @query = params[:q].to_s.strip
      @filter = FILTERS.include?(params[:filter]) ? params[:filter] : "all"

      scope = Escriba::Translation.for_locale(dev_locale).order(:source_copy)
      scope = scope.where("source_copy LIKE ?", "%#{sanitize_like(@query)}%") if @query.present?
      dev_rows = scope.limit(LIST_LIMIT).to_a

      @values = Escriba::Translation
        .where(locale: @locale.to_s, key: dev_rows.map(&:key))
        .index_by(&:key)

      if @locale == dev_locale
        @counts = { all: dev_rows.size, missing: 0, issues: 0 }
        @dev_rows = dev_rows
      else
        classified = dev_rows.map { |dev| [dev, classify(dev, @values[dev.key])] }
        @counts = {
          all: dev_rows.size,
          missing: classified.count { |(_, c)| c == :missing },
          issues: classified.count { |(_, c)| c == :issues },
        }
        selected = case @filter
                   when "missing" then classified.select { |(_, c)| c == :missing }
                   when "issues"  then classified.select { |(_, c)| c == :issues }
                   else classified
                   end
        @dev_rows = selected.map(&:first)
      end
    end

    def show
      @key = params[:key]
      @rows_by_locale = Escriba::Translation
        .where(key: @key)
        .index_by { |r| r.locale.to_sym }
      @dev_row = @rows_by_locale[dev_locale]
      raise ActiveRecord::RecordNotFound unless @dev_row

      @available_locales = Escriba.config.available_locales
    end

    def edit
      @key = params[:key]
      @locale = params[:locale].to_sym
      return if reject_dev_locale_edit

      load_or_initialize_row
    end

    def update
      @key = params[:key]
      @locale = params[:locale].to_sym
      return if reject_dev_locale_edit

      load_or_initialize_row

      assign_value
      if @row.save
        if params[:commit_next].present? && (nxt = next_missing_key)
          redirect_to edit_translation_path(nxt, @locale),
            notice: "Saved. Changes go live on the next deploy."
        else
          redirect_to translation_path(@key, locale: @locale),
            notice: "Updated. Changes go live on the next deploy."
        end
      else
        render :edit, status: :unprocessable_entity
      end
    end

    private

    def reject_dev_locale_edit
      return false unless dev_locale_from_code? && @locale == dev_locale

      redirect_to translation_path(@key),
        alert: "The #{@locale} locale is managed in source code and cannot be edited."
      true
    end

    def classify(dev, target)
      issues = translation_issues(dev, target)
      return :ok if issues.empty?
      return :missing if issues.any? { |i| i.code == :missing }

      :issues
    end

    # The next dev string (alphabetical) with no value yet in @locale.
    def next_missing_key
      translated = Escriba::Translation
        .where(locale: @locale.to_s).where.not(value: nil).pluck(:key)

      Escriba::Translation
        .for_locale(dev_locale)
        .where.not(key: translated + [@key])
        .order(:source_copy)
        .limit(1)
        .pick(:key)
    end

    def sanitize_like(value)
      ActiveRecord::Base.sanitize_sql_like(value)
    end

    def load_or_initialize_row
      @dev_row = Escriba::Translation.find_by!(key: @key, locale: dev_locale.to_s)
      @row = Escriba::Translation.find_or_initialize_by(key: @key, locale: @locale.to_s)
      return if @row.persisted?

      @row.source_copy = @dev_row.source_copy
      @row.meaning = @dev_row.meaning
      @row.interpolation_names = @dev_row.interpolation_names
      @row.plural = @dev_row.plural
    end

    def assign_value
      if @row.plural
        forms = params.require(:translation).fetch(:value, {}).to_unsafe_h
        forms = forms.transform_keys(&:to_s).reject { |_, v| v.to_s.empty? }
        @row.value = forms
      else
        @row.value = params.require(:translation).fetch(:value, nil).presence
      end
    end
  end
end
