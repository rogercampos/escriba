# frozen_string_literal: true

module Escriba
  # Validates a translation's value against the source string it translates
  # (its interpolations and plural forms). Pure and side-effect-free;
  # `escriba:check` runs it over every value in the YAML files.
  #
  # A plural needs its "other" form, and, when given the forms its locale uses
  # (Escriba.plural_forms), each of those: I18n serves "other" for a count
  # whose form is missing, so Polish would show "3 stron" instead of "3 strony".
  class TranslationValidator
    Issue = Struct.new(:code, :message, keyword_init: true)

    # Every code but :missing (an untranslated value, which is allowed).
    ERROR_CODES = %i[unknown_interpolation missing_interpolation missing_plural_other missing_plural_form].freeze

    def self.call(...)
      new(...).issues
    end

    # value                 - the translation: a String (singular) or a Hash of
    #                         CLDR plural forms (plural). Blank => missing.
    # source_copy           - the dev-locale source: String or Hash of forms.
    # source_interpolations - Array of interpolation names in the source. When
    #                         omitted it is derived from source_copy.
    # plural                - whether this is a plural string.
    # plural_forms          - the plural forms the value's locale uses, as
    #                         strings; nil when unknown.
    def initialize(value:, source_copy:, source_interpolations: nil, plural: false, plural_forms: nil)
      @value = value
      @source_copy = source_copy
      @plural = plural
      @plural_forms = Array(plural_forms).map(&:to_s)
      @source_interpolations = Array(source_interpolations || derive_source_interpolations).map(&:to_s)
    end

    def issues
      return [issue(:missing, "No translation yet.")] if blank_value?

      list = []
      list << issue(:missing_plural_other, %(Missing the required "other" plural form.)) if @plural && !present?(forms["other"])
      list.concat(locale_form_issues)
      list.concat(interpolation_issues)
      list
    end

    def valid?
      issues.empty?
    end

    private

    def issue(code, message)
      Issue.new(code: code, message: message)
    end

    def blank_value?
      if @plural
        forms.values.none? { |v| present?(v) }
      else
        !present?(@value)
      end
    end

    def forms
      @forms ||= @value.is_a?(Hash) ? @value.transform_keys(&:to_s) : {}
    end

    def locale_form_issues
      return [] unless @plural

      missing = @plural_forms - ["other"] - forms.select { |_, v| present?(v) }.keys
      return [] if missing.empty?

      [issue(:missing_plural_form,
        "Missing the plural form(s) #{missing.join(", ")} this locale uses (until filled in, " \
        "those counts show the \"other\" form).")]
    end

    def interpolation_issues
      out = []
      used = used_interpolations

      unknown = used - @source_interpolations
      out << issue(:unknown_interpolation, "Unknown interpolation #{format_vars(unknown)} — absent from the source string.") unless unknown.empty?

      # The "one" plural form legitimately drops %{count}, so a missing-variable
      # check is only meaningful for singular strings.
      unless @plural
        missing = @source_interpolations - used
        out << issue(:missing_interpolation, "Missing interpolation #{format_vars(missing)} from the source string.") unless missing.empty?
      end

      out
    end

    def used_interpolations
      texts = @plural ? forms.values : [@value]
      texts.compact.flat_map { |t| Escriba::KeyDeriver.interpolation_names(t.to_s) }.uniq
    end

    def derive_source_interpolations
      if @source_copy.is_a?(Hash)
        @source_copy.values.flat_map { |v| Escriba::KeyDeriver.interpolation_names(v.to_s) }.uniq
      else
        Escriba::KeyDeriver.interpolation_names(@source_copy.to_s)
      end
    end

    def present?(value)
      value.is_a?(String) ? !value.strip.empty? : !value.nil?
    end

    def format_vars(names)
      names.map { |n| "%{#{n}}" }.join(", ")
    end
  end
end
