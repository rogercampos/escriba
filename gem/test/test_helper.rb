# frozen_string_literal: true

# SimpleCov MUST be started before any application code is required
require_relative "simplecov_setup"
EscribaCoverage.start!

$LOAD_PATH.unshift File.expand_path("../lib", __dir__)

require "escriba"

I18n.available_locales = %i[en es]
I18n.default_locale = :en
I18n.fallbacks = I18n::Locale::Fallbacks.new(es: %i[es en], en: [:en])
I18n.backend = Escriba::Backend.new

require "minitest/autorun"
