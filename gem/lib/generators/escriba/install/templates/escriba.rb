# frozen_string_literal: true

Escriba.configure do |config|
  # The locale that source code copy represents. Defaults to :en.
  # config.dev_locale = :en

  # Authentication callable invoked as a before_action in the engine's controllers.
  # REQUIRED outside development/test — Rails will refuse to boot if unset.
  # The callable receives the controller; halt by rendering or redirecting from it.
  #
  # config.authenticate_with = ->(controller) do
  #   controller.head :forbidden unless controller.current_user&.admin?
  # end

  # Locales the admin UI offers. Defaults to I18n.available_locales.
  # config.available_locales = %i[en es]
end
