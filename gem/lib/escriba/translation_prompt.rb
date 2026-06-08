# frozen_string_literal: true

require "json"

module Escriba
  # Builds a ready-to-paste prompt for bulk-translating a set of strings into one
  # locale with an LLM. The prompt bundles the translation rules, the JSON Schema
  # the reply must satisfy (from TranslationSchema, also used to validate the
  # reply), and the strings to translate as JSON input.
  class TranslationPrompt
    # A small built-in locale → language-name map for readable prompts; falls
    # back to the bare code for anything not listed.
    LANGUAGE_NAMES = {
      "en" => "English", "es" => "Spanish", "it" => "Italian", "fr" => "French",
      "de" => "German", "pt" => "Portuguese", "nl" => "Dutch", "ca" => "Catalan",
      "gl" => "Galician", "eu" => "Basque", "ru" => "Russian", "pl" => "Polish",
      "uk" => "Ukrainian", "ar" => "Arabic", "zh" => "Chinese", "ja" => "Japanese",
      "ko" => "Korean", "tr" => "Turkish", "sv" => "Swedish", "da" => "Danish",
      "nb" => "Norwegian", "fi" => "Finnish", "cs" => "Czech", "el" => "Greek",
    }.freeze

    def self.call(...)
      new(...).to_s
    end

    # locale     - target locale (symbol/string)
    # dev_locale - source locale (the dev rows' language)
    # rows       - the dev Translation rows to translate
    def initialize(locale:, dev_locale:, rows:)
      @locale = locale.to_sym
      @dev_locale = dev_locale.to_sym
      @rows = rows
    end

    def to_s
      <<~PROMPT
        You are a professional software localizer. Translate the user-facing
        strings below from #{language_name(@dev_locale)} (#{@dev_locale}) into
        #{language_name(@locale)} (#{@locale}).

        Rules:
        - Keep every interpolation placeholder exactly as written, e.g. `%{name}`.
          Never translate, rename, reorder away, or remove a placeholder; the set
          of placeholders in your translation must match the source.
        - Use the optional "meaning" field only as disambiguation context. Do not
          include it in your output.
        - When an entry has "plural": true, return an object with ALL plural forms
          that #{language_name(@locale)} requires under CLDR (these may differ
          from the source — add the forms the language needs), each a string.
          Otherwise return a single string.
        - Never change "key". Set "locale" to "#{@locale}" on every entry.
        - Return ONLY a JSON array that conforms to the JSON Schema below. No
          explanations, no Markdown, no code fences.

        JSON Schema your output must conform to:

        #{pretty(schema)}

        Strings to translate:

        #{pretty(input)}
      PROMPT
    end

    private

    def schema
      Escriba::TranslationSchema.for(locales: [@locale])
    end

    def input
      @rows.map do |row|
        item = {
          "key" => row.key,
          "source" => row.source_copy,
          "plural" => row.plural,
          "placeholders" => Array(row.interpolation_names),
        }
        item["meaning"] = row.meaning if row.meaning.present?
        item
      end
    end

    def language_name(locale)
      LANGUAGE_NAMES.fetch(locale.to_s, locale.to_s)
    end

    def pretty(data)
      JSON.pretty_generate(data)
    end
  end
end
