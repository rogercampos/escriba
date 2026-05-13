# frozen_string_literal: true

# SimpleCov MUST be started before any application code is required
require "simplecov"

if ENV["CI"]
  require "simplecov_json_formatter"
  SimpleCov.formatter = SimpleCov::Formatter::JSONFormatter
else
  SimpleCov.formatter = SimpleCov::Formatter::HTMLFormatter
end

SimpleCov.start do
  root File.expand_path("..", __dir__)
  command_name "Minitest"

  add_filter "/test/"
  add_filter "/dummy/"

  add_group "Core", "lib/escriba"

  enable_coverage :branch
end

# Default to test env unless caller overrides (production-path tests do).
ENV["ESCRIBA_ENV"] ||= "test"

# Now load the application
$LOAD_PATH.unshift File.expand_path("../lib", __dir__)

require "active_record"
require "logger"
ActiveRecord::Base.logger = Logger.new(IO::NULL)
ActiveRecord::Base.establish_connection(adapter: "sqlite3", database: ":memory:")

ActiveRecord::Schema.verbose = false
ActiveRecord::Schema.define do
  create_table :escriba_translations do |t|
    t.string  :key,                 null: false, limit: 32
    t.string  :locale,              null: false, limit: 16
    t.text    :value
    t.text    :source_copy,         null: false
    t.text    :meaning
    t.text    :interpolation_names
    t.boolean :plural,              null: false, default: false
    t.timestamps
  end
  add_index :escriba_translations, [:key, :locale], unique: true
  add_index :escriba_translations, :key
end

require "escriba"
require "escriba/translation"

require "i18n/backend/fallbacks"
I18n.available_locales = %i[en es]
I18n.default_locale = :en
I18n.fallbacks = I18n::Locale::Fallbacks.new(es: %i[es en], en: [:en])
I18n.backend = Escriba::Backend.new

require "minitest/autorun"
require "webmock/minitest"

WebMock.disable_net_connect!(allow_localhost: true)
