require_relative "boot"

require "rails"
require "action_controller/railtie"
require "action_view/railtie"
require "rails/test_unit/railtie"

# Require the gems listed in Gemfile, including any gems
# you've limited to :test, :development, or :production.
Bundler.require(*Rails.groups)

module Dummy
  class Application < Rails::Application
    config.load_defaults 8.1

    config.autoload_lib(ignore: %w[assets tasks])

    # English is the copy in the source code; Spanish, Italian and French come
    # from config/locales/escriba.<locale>.yml, falling back to English.
    config.i18n.available_locales = %i[en es it fr]
    config.i18n.default_locale = :en
    config.i18n.fallbacks = true
  end
end
