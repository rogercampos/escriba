# frozen_string_literal: true

require "rails/railtie"

module Escriba
  class Railtie < ::Rails::Railtie
    initializer "escriba.install_backend" do
      I18n.backend = Escriba::Backend.new
    end

    rake_tasks do
      load File.expand_path("../tasks/escriba_tasks.rake", __dir__)
    end
  end
end
