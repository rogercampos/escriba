# frozen_string_literal: true

module Escriba
  class TranslationsController < ApplicationController
    def index
      @locale = current_locale_param
      @available_locales = Escriba.config.available_locales

      dev_rows = Escriba::Translation.for_locale(dev_locale).order(:source_copy)
      dev_rows = filter_missing(dev_rows) if params[:missing].present? && @locale != dev_locale

      @dev_rows = dev_rows.limit(500)
      @values = Escriba::Translation
        .where(locale: @locale.to_s, key: @dev_rows.map(&:key))
        .index_by(&:key)
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
      load_or_initialize_row
    end

    def update
      @key = params[:key]
      @locale = params[:locale].to_sym
      load_or_initialize_row

      assign_value
      if @row.save
        redirect_to translation_path(@key, locale: @locale),
          notice: "Updated. Changes go live on the next deploy."
      else
        render :edit, status: :unprocessable_entity
      end
    end

    private

    def filter_missing(dev_rows)
      translated_keys = Escriba::Translation
        .where(locale: @locale.to_s, key: dev_rows.pluck(:key))
        .where.not(value: nil)
        .pluck(:key)
      dev_rows.where.not(key: translated_keys)
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
