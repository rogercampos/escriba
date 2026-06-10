# frozen_string_literal: true

require "test_helper"
require "tmpdir"
require "fileutils"

class TestSourceExtractor < Minitest::Test
  def extract(code, file: "sample.rb")
    Dir.mktmpdir do |dir|
      path = File.join(dir, file)
      FileUtils.mkdir_p(File.dirname(path))
      File.write(path, code)
      extractor = Escriba::SourceExtractor.new(paths: [dir])
      return [extractor.strings, extractor.dynamic_calls]
    end
  end

  def test_extracts_singular_calls_with_the_runtime_key
    strings, dynamic = extract(<<~RUBY)
      class Thing
        def label = E18n.t("Save")
      end
    RUBY

    assert_empty dynamic
    assert_equal 1, strings.size
    entry = strings.first
    assert_equal Escriba::KeyDeriver.for_singular("Save"), entry.key
    assert_equal "Save", entry.source_copy
    refute entry.plural
    assert_equal 2, entry.line
  end

  def test_meaning_changes_the_key_and_is_recorded
    strings, = extract(%(E18n.t("Save", meaning: "to store")))

    assert_equal Escriba::KeyDeriver.for_singular("Save", meaning: "to store"), strings.first.key
    assert_equal "to store", strings.first.meaning
  end

  def test_records_interpolation_names
    strings, = extract(%(E18n.t("Hello %{name}", name: user.name)))

    assert_equal ["name"], strings.first.interpolation_names
  end

  def test_extracts_adjacent_literal_string_concatenation
    strings, dynamic = extract(<<~RUBY)
      E18n.t(
        "Run %{count} expert checks on any URL — security headers, " \\
        "SSL and DNS. Scheduled monitoring included.",
        count: total
      )
      E18n.t("One " "Two", meaning: "first " "part")
    RUBY

    assert_empty dynamic
    joined = "Run %{count} expert checks on any URL — security headers, SSL and DNS. Scheduled monitoring included."
    assert_equal [joined, "One Two"], strings.map(&:source_copy).sort_by(&:length).reverse
    assert_equal Escriba::KeyDeriver.for_singular(joined), strings.find { |s| s.source_copy == joined }.key
    assert_equal "first part", strings.find { |s| s.source_copy == "One Two" }.meaning
  end

  def test_concatenation_with_true_interpolation_is_still_dynamic
    strings, dynamic = extract(<<~'RUBY')
      E18n.t("Hello " "there #{name}")
    RUBY

    assert_empty strings
    assert_equal 1, dynamic.size
  end

  def test_extracts_plural_calls
    strings, dynamic = extract(%(E18n.t(one: "1 file", other: "%{count} files", count: n)))

    assert_empty dynamic
    entry = strings.first
    assert_equal Escriba::KeyDeriver.for_plural(one: "1 file", other: "%{count} files"), entry.key
    assert entry.plural
    assert_equal({ "one" => "1 file", "other" => "%{count} files" }, entry.source_copy)
    assert_equal ["count"], entry.interpolation_names
  end

  def test_matches_qualified_receivers
    strings, = extract(<<~RUBY)
      Escriba::E18n.t("One")
      ::E18n.t("Two")
    RUBY

    assert_equal %w[One Two], strings.map(&:source_copy).sort
  end

  def test_ignores_other_receivers
    strings, dynamic = extract(<<~RUBY)
      I18n.t("not.escriba")
      t("helper call")
      Foo.t("other")
    RUBY

    assert_empty strings
    assert_empty dynamic
  end

  def test_dynamic_copy_is_reported_not_extracted
    strings, dynamic = extract(<<~RUBY)
      E18n.t(some_variable)
      E18n.t("Hi \#{name}")
      E18n.t("Save", meaning: dynamic_meaning)
    RUBY

    assert_empty strings
    assert_equal [1, 2, 3], dynamic.map(&:line).sort
  end

  def test_extracts_nested_calls_and_dedupes_by_key
    strings, = extract(<<~RUBY)
      E18n.t("Outer %{x}", x: E18n.t("Inner"))
      E18n.t("Inner")
    RUBY

    assert_equal ["Inner", "Outer %{x}"], strings.map(&:source_copy).sort
  end

  def test_a_file_that_fails_to_compile_is_reported_and_does_not_abort_the_run
    Dir.mktmpdir do |dir|
      File.write(File.join(dir, "bad.erb"), "\xE9 <%= E18n.t(\"x\") %>".b)
      File.write(File.join(dir, "good.rb"), %(E18n.t("Still extracted")))
      extractor = Escriba::SourceExtractor.new(paths: [dir])

      assert_equal ["Still extracted"], extractor.strings.map(&:source_copy)
      assert_equal 1, extractor.failed_files.size
      assert_includes extractor.failed_files.first.file, "bad.erb"
    end
  end

  def test_extracts_from_erb_views
    strings, = extract(<<~ERB, file: "views/home.html.erb")
      <h1><%= E18n.t("From the view") %></h1>
      <p><% if cond %><%= E18n.t(one: "1 item", other: "%{count} items", count: n) %><% end %></p>
    ERB

    assert_equal 2, strings.size
    assert_includes strings.map(&:source_copy), "From the view"
  end
end
