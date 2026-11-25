# frozen_string_literal: true

require_relative "lib/escriba/version"

Gem::Specification.new do |spec|
  spec.name = "escriba"
  spec.version = Escriba::VERSION
  spec.authors = ["Roger Campos"]
  spec.email = ["roger@rogercampos.com"]

  spec.summary = "Translations for Rails without translation keys."
  spec.description = "Escriba lets you write real copy in source code (E18n.t(\"Save\")) and keeps its translations in one YAML file per locale, generated from the source and served through Rails' I18n."
  spec.homepage = "https://github.com/rogercampos/escriba"
  spec.license = "MIT"
  spec.required_ruby_version = ">= 4.0"

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
  spec.add_dependency "i18n", ">= 1.15"
  spec.add_dependency "prism", ">= 1.9" # static extraction of E18n.t calls
  spec.add_dependency "railties", ">= 8.1"

  # For more information and examples about making a new gem, check out our
  # guide at: https://bundler.io/guides/creating_gem.html
end
