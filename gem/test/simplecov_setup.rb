# frozen_string_literal: true

# Shared SimpleCov configuration for every suite that exercises the gem.
#
# Call EscribaCoverage.start! before any application code is loaded (including
# the dummy app's environment), otherwise SimpleCov cannot instrument what is
# already loaded.
#
# Two suites report into gem/coverage and are merged into one report:
#   * gem/test    -> command name "Minitest"  (`rake test` from gem/)
#   * dummy/test  -> command name "Dummy"     (`rake test_dummy` from gem/)
#
# Set COVERAGE_COMMAND_NAME to name a suite.
module EscribaCoverage
  GEM_ROOT = File.expand_path("..", __dir__)

  def self.start!
    require "simplecov"

    if ENV["CI"]
      require "simplecov_json_formatter"
      SimpleCov.formatter = SimpleCov::Formatter::JSONFormatter
    else
      SimpleCov.formatter = SimpleCov::Formatter::HTMLFormatter
    end

    SimpleCov.start do
      root GEM_ROOT
      coverage_dir File.join(GEM_ROOT, "coverage")
      command_name ENV.fetch("COVERAGE_COMMAND_NAME", "Minitest")

      # Merge the gem suite and the dummy app suite into a single report.
      merging true
      merge_timeout 3600

      # Only the gem itself is measured.
      add_filter "/test/"
      add_filter "/dummy/"

      add_group "Core", "lib/escriba"

      enable_coverage :branch
    end
  end
end
