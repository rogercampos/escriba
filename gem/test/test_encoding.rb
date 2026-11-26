# frozen_string_literal: true

require "test_helper"
require "tmpdir"
require "open3"
require "rbconfig"

# Source files are UTF-8, whatever the locale of the process that
# reads them (a container or a cron job often runs with no LANG, so Ruby's
# default external encoding is US-ASCII). Each test runs Ruby in a child
# process with that encoding, as such a process would.
class TestEncoding < Minitest::Test
  def run_with_ascii_locale(script, dir)
    lib = File.expand_path("../lib", __dir__)
    out, err, status = Open3.capture3(RbConfig.ruby, "-E", "US-ASCII", "-I", lib, "-r", "escriba",
                                      "-e", "$stdout.binmode\n#{script}", dir)
    assert status.success?, err
    out.force_encoding(Encoding::UTF_8)
  end

  def test_extracts_non_ascii_copy_from_source_files
    Dir.mktmpdir do |dir|
      File.write(File.join(dir, "post.rb"), %(E18n.t("Añadir")))
      File.write(File.join(dir, "show.html.erb"), %(<%= E18n.t("Cancel·lar") %>))

      out = run_with_ascii_locale(<<~RUBY, dir)
        extractor = Escriba::SourceExtractor.new(paths: [ARGV[0]])
        extractor.failed_files.each { |failed| warn failed.message }
        extractor.strings.each { |entry| puts "\#{entry.key} \#{entry.source_copy}" }
      RUBY

      assert_equal ["#{Escriba::KeyDeriver.for_singular('Añadir')} Añadir",
                    "#{Escriba::KeyDeriver.for_singular('Cancel·lar')} Cancel·lar"].sort,
                   out.lines(chomp: true).sort
    end
  end
end
