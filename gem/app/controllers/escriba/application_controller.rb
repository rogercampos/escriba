# frozen_string_literal: true

module Escriba
  class ApplicationController < ActionController::Base
    protect_from_forgery with: :exception

    layout "escriba/application"

    before_action :authenticate_escriba!

    helper_method :current_locale_param, :dev_locale

    private

    def authenticate_escriba!
      Escriba.config.authenticate_with&.call(self)
    end

    def current_locale_param
      param = params[:locale].presence
      param ? param.to_sym : dev_locale
    end

    def dev_locale
      Escriba.config.dev_locale
    end
  end
end
