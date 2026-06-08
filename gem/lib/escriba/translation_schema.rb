# frozen_string_literal: true

module Escriba
  # The JSON Schema (draft 2020-12) describing the array an LLM must return when
  # bulk-translating. It is the single source of truth: TranslationPrompt embeds
  # it verbatim in the prompt, and TranslationJsonImporter validates the pasted
  # reply against it.
  #
  # The schema is parameterized by the locales it accepts. The prompt pins it to
  # the single target locale (so the model can't drift); the importer validates
  # against all importable locales (it doesn't know which one was generated).
  module TranslationSchema
    extend self

    PLURAL_FORMS = %w[zero one two few many other].freeze

    # locales - the locale codes allowed in the `locale` field (an Array).
    def for(locales:)
      {
        "$schema" => "https://json-schema.org/draft/2020-12/schema",
        "type" => "array",
        "items" => {
          "type" => "object",
          "additionalProperties" => false,
          "required" => %w[key locale translation],
          "properties" => {
            "key" => { "type" => "string", "pattern" => "^[a-f0-9]{16}$" },
            "locale" => { "enum" => locales.map(&:to_s) },
            "translation" => {
              "oneOf" => [
                { "type" => "string", "minLength" => 1 },
                {
                  "type" => "object",
                  "minProperties" => 1,
                  "additionalProperties" => false,
                  "properties" => PLURAL_FORMS.to_h { |form| [form, { "type" => "string" }] },
                },
              ],
            },
          },
        },
      }
    end
  end
end
