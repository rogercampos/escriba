# frozen_string_literal: true

require "concurrent/map"

module Escriba
  class Cache
    NULL = Object.new.freeze

    def initialize
      @store = Concurrent::Map.new
      @catalogs = Concurrent::Map.new
    end

    def fetch(locale, key)
      cache_key = [locale.to_sym, key]
      cached = @store.compute_if_absent(cache_key) do
        value = yield
        value.nil? ? NULL : value
      end
      cached.equal?(NULL) ? nil : cached
    end

    # The database values of one locale, by key: loaded once per locale (the
    # block runs on the first call), so a cold process makes one query per
    # locale instead of one per key. Shares the cache's lifetime: clear! and
    # Escriba.reset_cache! drop it along with the per-key values.
    def catalog(locale)
      @catalogs.compute_if_absent(locale.to_sym) { yield }
    end

    def clear!
      @store.clear
      @catalogs.clear
    end

    def size
      @store.size
    end

    def key?(locale, key)
      @store.key?([locale.to_sym, key])
    end
  end
end
