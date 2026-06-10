# frozen_string_literal: true

require "test_helper"

class EscribaPendingPublishTest < ActionDispatch::IntegrationTest
  setup do
    Escriba::Translation.delete_all
  end

  teardown do
    Escriba.config.last_published_at = nil
  end

  def create_string(locale:, value: nil)
    Escriba::Translation.create!(
      key: "c" * 16, locale: locale, source_copy: "Save", value: value
    )
  end

  test "rows edited after the last publish are flagged as pending deploy" do
    create_string(locale: "en")
    create_string(locale: "es", value: "Guardar")

    # The app booted before the rows were created, so they are pending.
    get "/escriba/translations", params: { locale: "es" }
    assert_response :success
    assert_includes response.body, "pending deploy"

    get "/escriba/dashboard"
    assert_includes response.body, "1 edit"
    assert_includes response.body, "pending deploy"

    # With a publish recorded after the edits, nothing is pending.
    Escriba.config.last_published_at = -> { 1.minute.from_now }

    get "/escriba/translations", params: { locale: "es" }
    assert_not_includes response.body, "pending deploy"

    get "/escriba/dashboard"
    assert_not_includes response.body, "pending deploy"
  end

  test "the footer reports the last publish time" do
    get "/escriba/dashboard"
    assert_includes response.body, "Last published"
  end
end
