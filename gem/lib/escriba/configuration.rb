# frozen_string_literal: true

module Escriba
  class Configuration
    attr_accessor :dev_locale
    attr_writer :available_locales

    def initialize
      @dev_locale = :en
      @available_locales = nil
    end

    def available_locales
      return @available_locales if @available_locales
      return I18n.available_locales if defined?(I18n)

      [dev_locale]
    end
  end
end
