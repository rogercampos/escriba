# frozen_string_literal: true

require "concurrent/map"

module Escriba
  class Cache
    NULL = Object.new.freeze

    def initialize
      @store = Concurrent::Map.new
    end

    def fetch(locale, key)
      cache_key = [locale.to_sym, key]
      cached = @store.compute_if_absent(cache_key) do
        value = yield
        value.nil? ? NULL : value
      end
      cached.equal?(NULL) ? nil : cached
    end

    def clear!
      @store.clear
    end

    def size
      @store.size
    end

    def key?(locale, key)
      @store.key?([locale.to_sym, key])
    end
  end
end
