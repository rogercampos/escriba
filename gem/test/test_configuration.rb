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

  def test_configure_block_yields_config
    Escriba.configure { |c| c.dev_locale = :de }

    assert_equal :de, Escriba.config.dev_locale
  end

  def test_available_locales_default_to_i18n
    assert_equal I18n.available_locales, Escriba.config.available_locales
  end

  def test_available_locales_can_be_explicitly_set
    Escriba.configure { |c| c.available_locales = %i[en es fr] }

    assert_equal %i[en es fr], Escriba.config.available_locales
  end

  def test_translated_locales_are_the_available_ones_but_the_dev_locale
    Escriba.configure { |c| c.available_locales = %w[en es fr] }

    assert_equal %i[es fr], Escriba.translated_locales
  end

  def test_reset_config_restores_defaults
    Escriba.configure { |c| c.dev_locale = :de }
    Escriba.reset_config!

    assert_equal :en, Escriba.config.dev_locale
  end
end
