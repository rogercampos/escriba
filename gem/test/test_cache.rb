# frozen_string_literal: true

require "test_helper"
require "concurrent/atomic/atomic_fixnum"

class TestCache < Minitest::Test
  def setup
    @cache = Escriba::Cache.new
  end

  def test_fetch_returns_block_value_on_first_call
    result = @cache.fetch(:en, "abc") { "Saved" }
    assert_equal "Saved", result
  end

  def test_fetch_returns_cached_value_on_second_call_and_does_not_re_yield
    @cache.fetch(:en, "abc") { "Saved" }
    yielded_again = false
    result = @cache.fetch(:en, "abc") { yielded_again = true; "Other" }
    assert_equal "Saved", result
    refute yielded_again
  end

  def test_fetch_caches_nil_values
    @cache.fetch(:es, "missing") { nil }
    yielded_again = false
    result = @cache.fetch(:es, "missing") { yielded_again = true; "should not be returned" }
    assert_nil result
    refute yielded_again
  end

  def test_fetch_distinguishes_by_locale
    @cache.fetch(:en, "abc") { "english" }
    @cache.fetch(:es, "abc") { "spanish" }
    assert_equal "english", @cache.fetch(:en, "abc") { "x" }
    assert_equal "spanish", @cache.fetch(:es, "abc") { "x" }
  end

  def test_fetch_distinguishes_by_key
    @cache.fetch(:en, "key1") { "one" }
    @cache.fetch(:en, "key2") { "two" }
    assert_equal "one", @cache.fetch(:en, "key1") { "x" }
    assert_equal "two", @cache.fetch(:en, "key2") { "x" }
  end

  def test_locale_is_normalized_to_symbol
    @cache.fetch("en", "abc") { "value" }
    assert_equal "value", @cache.fetch(:en, "abc") { "other" }
  end

  def test_key_predicate
    refute @cache.key?(:en, "abc")
    @cache.fetch(:en, "abc") { "value" }
    assert @cache.key?(:en, "abc")
  end

  def test_key_predicate_true_even_for_nil_value
    @cache.fetch(:en, "missing") { nil }
    assert @cache.key?(:en, "missing")
  end

  def test_clear_empties_the_cache
    @cache.fetch(:en, "abc") { "value" }
    @cache.clear!
    refute @cache.key?(:en, "abc")
    assert_equal 0, @cache.size
  end

  def test_concurrent_writes_to_same_key_only_yield_once
    @cache = Escriba::Cache.new
    barrier = Queue.new
    yield_count = Concurrent::AtomicFixnum.new(0)

    threads = 10.times.map do
      Thread.new do
        barrier.pop
        @cache.fetch(:en, "shared") do
          yield_count.increment
          sleep 0.01
          "value"
        end
      end
    end

    10.times { barrier << :go }
    threads.each(&:join)

    assert_equal 1, yield_count.value
  end
end
