# frozen_string_literal: true

# SimpleCov MUST be started before any application code is required
require_relative "simplecov_setup"
EscribaCoverage.start!

$LOAD_PATH.unshift File.expand_path("../lib", __dir__)

# Rails sets this when it loads, so the gem always runs with it. Set it here
# too, or files are read in the shell's locale (US-ASCII when LANG is unset).
Encoding.default_external = Encoding::UTF_8

require "escriba"

# Rails sets this when it boots, so it is what the gem always runs with. Set it
# here too, or the tests that read files with non-ASCII copy depend on the
# shell's locale (with no LANG, Ruby defaults to US-ASCII).
Encoding.default_external = Encoding::UTF_8

I18n.available_locales = %i[en es]
I18n.default_locale = :en
I18n.fallbacks = I18n::Locale::Fallbacks.new(es: %i[es en], en: [:en])
I18n.backend = Escriba::Backend.new

require "minitest/autorun"
