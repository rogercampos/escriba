# frozen_string_literal: true

Escriba.configure do |config|
  # The locale of the copy written in source code. Defaults to :en. It is
  # always served from the code itself; every other locale from
  # config/locales/escriba.<locale>.yml.
  # config.dev_locale = :en

  # The locales the app supports, the dev locale included: escriba:dump_yml
  # writes one file for each of the others. Defaults to I18n.available_locales.
  # config.available_locales = %i[en es]
end
