# frozen_string_literal: true

require "rails/generators"
require "rails/generators/active_record"

module Escriba
  module Generators
    class InstallGenerator < ::Rails::Generators::Base
      include ::Rails::Generators::Migration

      source_root File.expand_path("templates", __dir__)

      def self.next_migration_number(dir)
        ::ActiveRecord::Generators::Base.next_migration_number(dir)
      end

      def copy_initializer
        template "escriba.rb", "config/initializers/escriba.rb"
      end

      def create_migration_file
        migration_template "create_escriba_translations.rb.tt",
          "db/migrate/create_escriba_translations.rb"
      end

      def show_post_install_message
        say "\nNext steps:", :green
        say "  1. Mount the engine in config/routes.rb:"
        say "       mount Escriba::Engine => \"/escriba\"\n"
        say "  2. Configure authentication for production in config/initializers/escriba.rb"
        say "  3. Run: bin/rails db:migrate"
      end
    end
  end
end
