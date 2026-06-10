# frozen_string_literal: true

require_relative "lib/escriba/version"

Gem::Specification.new do |spec|
  spec.name = "escriba"
  spec.version = Escriba::VERSION
  spec.authors = ["Roger Campos"]
  spec.email = ["roger@rogercampos.com"]

  spec.summary = "Translations for Rails without translation keys."
  spec.description = "Escriba lets you write real copy in source code (E18n.t(\"Save\")) and manages translations via a DB-backed admin UI, while keeping all of Rails' I18n machinery."
  spec.homepage = "https://github.com/rogercampos/escriba"
  spec.license = "MIT"
  spec.required_ruby_version = ">= 3.1.0"

  spec.metadata["homepage_uri"] = spec.homepage
  spec.metadata["source_code_uri"] = spec.homepage

  # Specify which files should be added to the gem when it is released.
  # The `git ls-files -z` loads the files in the RubyGem that have been added into git.
  gemspec = File.basename(__FILE__)
  spec.files = IO.popen(%w[git ls-files -z], chdir: __dir__, err: IO::NULL) do |ls|
    ls.readlines("\x0", chomp: true).reject do |f|
      (f == gemspec) ||
        f.start_with?(*%w[bin/ test/ spec/ features/ .git .github appveyor Gemfile])
    end
  end
  spec.bindir = "exe"
  spec.executables = spec.files.grep(%r{\Aexe/}) { |f| File.basename(f) }
  spec.require_paths = ["lib"]

  # Runtime dependencies
  spec.add_dependency "concurrent-ruby", "~> 1.0"
  spec.add_dependency "csv", ">= 3.0" # no longer a default gem on Ruby 3.4+
  spec.add_dependency "i18n", ">= 1.6"
  spec.add_dependency "json_schemer", ">= 2.0" # validates LLM-produced translation JSON
  spec.add_dependency "pagy", "~> 43.0" # admin UI relies on the v43 API (Pagy::Method)
  spec.add_dependency "activerecord", ">= 7.0"
  spec.add_dependency "railties", ">= 7.0"

  # Development dependencies for testing
  spec.add_development_dependency "mocha", "~> 2.1"
  spec.add_development_dependency "webmock", "~> 3.18"
  spec.add_development_dependency "sqlite3", ">= 2.1"
  spec.add_development_dependency "capybara", "~> 3.40"
  spec.add_development_dependency "selenium-webdriver", "~> 4.0"
  spec.add_development_dependency "puma", "~> 6.0"
  spec.add_development_dependency "factory_bot", "~> 6.4"

  # For more information and examples about making a new gem, check out our
  # guide at: https://bundler.io/guides/creating_gem.html
end
