# frozen_string_literal: true

require "rails/generators"

module Escriba
  module Generators
    class InstallGenerator < ::Rails::Generators::Base
      source_root File.expand_path("templates", __dir__)

      def copy_initializer
        template "escriba.rb", "config/initializers/escriba.rb"
      end

      def show_post_install_message
        say "\nNext steps:", :green
        say "  1. Write copy with E18n.t(\"...\") and run: bin/rails escriba:dump_yml"
        say "  2. Translate the blank entries in config/locales/escriba.<locale>.yml and commit them"
        say "  3. Add `bin/rails escriba:check` to your CI"
      end
    end
  end
end
