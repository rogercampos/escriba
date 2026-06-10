# frozen_string_literal: true

module Escriba
  class Error < StandardError; end
  class ArgumentError < Error; end
  class AuthNotConfigured < Error; end
  class InvalidDumpFile < Error; end
end
