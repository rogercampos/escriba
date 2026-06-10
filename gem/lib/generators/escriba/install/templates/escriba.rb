# frozen_string_literal: true

Escriba.configure do |config|
  # The locale that source code copy represents. Defaults to :en.
  # config.dev_locale = :en

  # Always read the dev_locale from source code (skip the DB for it).
  # Use this when developers manage all source copy via PRs and no content
  # team needs to edit the dev_locale in the admin UI. Defaults to false.
  # config.dev_locale_from_code = true

  # Authentication callable invoked as a before_action in the engine's controllers.
  # REQUIRED outside development/test — Rails will refuse to boot if unset.
  # The callable receives the controller; halt by rendering or redirecting from it.
  #
  # config.authenticate_with = ->(controller) do
  #   controller.head :forbidden unless controller.current_user&.admin?
  # end

  # Locales the admin UI offers. Defaults to I18n.available_locales.
  # config.available_locales = %i[en es]

  # When edits were last published. The admin UI flags rows updated after this
  # as "pending deploy". Translations are cached per process, so the publish
  # gate is really a restart of the serving processes — the default (this
  # process' boot time) matches that under Kamal and most deploy tools. Set a
  # Time or a callable for an exact fleet-wide value, e.g. recorded by a Kamal
  # post-deploy hook (KAMAL_RECORDED_AT) or a build stamp baked into the image.
  # config.last_published_at = -> { Time.parse(File.read("/etc/deploy-stamp")) }
end
