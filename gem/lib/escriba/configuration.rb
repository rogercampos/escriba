# frozen_string_literal: true

module Escriba
  class Configuration
    attr_accessor :dev_locale, :authenticate_with, :dev_locale_from_code
    attr_writer :available_locales

    def initialize
      @dev_locale = :en
      @authenticate_with = nil
      @dev_locale_from_code = false
      @available_locales = nil
    end

    def available_locales
      return @available_locales if @available_locales
      return I18n.available_locales if defined?(I18n)

      [dev_locale]
    end
  end
end
