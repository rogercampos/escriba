# frozen_string_literal: true

require "rails/engine"

module Escriba
  class Engine < ::Rails::Engine
    isolate_namespace Escriba

    initializer "escriba.load_translation_model" do
      require "escriba/translation"
    end

    initializer "escriba.install_backend" do
      I18n.backend = Escriba::Backend.new
    end

    config.after_initialize do
      env = Rails.env
      next if env.development? || env.test?
      next if Escriba.config.authenticate_with

      raise Escriba::AuthNotConfigured,
        "Escriba requires Escriba.config.authenticate_with to be configured outside development/test."
    end
  end
end
