# SimpleCov MUST be started before the app (and the gem) is loaded. Shares its
# config and coverage dir with gem/test so both suites merge into one report.
ENV["COVERAGE_COMMAND_NAME"] ||= "Dummy"
require_relative "../../gem/test/simplecov_setup"
EscribaCoverage.start!

ENV["RAILS_ENV"] ||= "test"
require_relative "../config/environment"
require "rails/test_help"

module ActiveSupport
  class TestCase
    # Run tests in parallel with specified workers
    parallelize(workers: :number_of_processors)

    # Each forked worker needs its own command name, otherwise workers overwrite
    # each other's entry in .resultset.json.
    parallelize_setup do |worker|
      SimpleCov.command_name "#{ENV.fetch("COVERAGE_COMMAND_NAME")}-#{worker}"
    end

    parallelize_teardown do
      SimpleCov.result
    end

    # Setup all fixtures in test/fixtures/*.yml for all tests in alphabetical order.
    fixtures :all

    # Add more helper methods to be used by all tests here...
  end
end
