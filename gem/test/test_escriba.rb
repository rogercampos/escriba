# frozen_string_literal: true

require "test_helper"

class TestEscriba < Minitest::Test
  def test_that_it_has_a_version_number
    refute_nil ::Escriba::VERSION
  end
end
