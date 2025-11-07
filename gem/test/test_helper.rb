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

# Now load the application
$LOAD_PATH.unshift File.expand_path("../lib", __dir__)

require "escriba"
require "minitest/autorun"
require "webmock/minitest"

WebMock.disable_net_connect!(allow_localhost: true)
