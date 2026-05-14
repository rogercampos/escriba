# frozen_string_literal: true

require "test_helper"

class TestConfiguration < Minitest::Test
  def setup
    Escriba.reset_config!
  end

  def teardown
    Escriba.reset_config!
  end

  def test_default_dev_locale_is_en
    assert_equal :en, Escriba.config.dev_locale
  end

  def test_default_authenticate_with_is_nil
    assert_nil Escriba.config.authenticate_with
  end

  def test_default_dev_locale_from_code_is_false
    refute Escriba.config.dev_locale_from_code
  end

  def test_can_set_dev_locale_from_code
    Escriba.configure { |c| c.dev_locale_from_code = true }
    assert Escriba.config.dev_locale_from_code
  end

  def test_configure_block_yields_config
    Escriba.configure do |c|
      c.dev_locale = :de
      c.authenticate_with = ->(_controller) { true }
    end

    assert_equal :de, Escriba.config.dev_locale
    assert_respond_to Escriba.config.authenticate_with, :call
  end

  def test_available_locales_falls_back_to_dev_locale_when_no_i18n_and_unset
    cfg = Escriba::Configuration.new
    cfg.dev_locale = :fr

    if defined?(I18n)
      assert_equal I18n.available_locales, cfg.available_locales
    else
      assert_equal [:fr], cfg.available_locales
    end
  end

  def test_available_locales_can_be_explicitly_set
    Escriba.configure do |c|
      c.available_locales = %i[en es fr]
    end
    assert_equal %i[en es fr], Escriba.config.available_locales
  end

  def test_reset_config_restores_defaults
    Escriba.configure { |c| c.dev_locale = :de }
    Escriba.reset_config!
    assert_equal :en, Escriba.config.dev_locale
  end
end
