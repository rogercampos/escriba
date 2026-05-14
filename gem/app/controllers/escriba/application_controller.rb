# frozen_string_literal: true

module Escriba
  class ApplicationController < ActionController::Base
    protect_from_forgery with: :exception

    layout "escriba/application"

    before_action :authenticate_escriba!

    helper_method :current_locale_param, :dev_locale, :editable_locales, :dev_locale_from_code?

    private

    def authenticate_escriba!
      Escriba.config.authenticate_with&.call(self)
    end

    def current_locale_param
      param = params[:locale].presence
      return param.to_sym if param

      default_index_locale
    end

    def default_index_locale
      return dev_locale unless dev_locale_from_code?

      (editable_locales.map(&:to_sym) - [dev_locale]).first || dev_locale
    end

    def editable_locales
      locales = Escriba.config.available_locales
      return locales unless dev_locale_from_code?

      locales.reject { |l| l.to_sym == dev_locale }
    end

    def dev_locale
      Escriba.config.dev_locale
    end

    def dev_locale_from_code?
      Escriba.config.dev_locale_from_code
    end
  end
end
