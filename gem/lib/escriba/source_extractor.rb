# frozen_string_literal: true

require "prism"

module Escriba
  # Statically extracts E18n.t calls from the source tree with Prism, deriving
  # the same keys the runtime would. This is what makes the YAML dump complete
  # for brand-new code: strings land in the catalog without ever having been
  # executed (the database only learns about a string the first time it runs).
  #
  # Escriba keys are content-hashes of literal copy, so any call whose copy
  # (and meaning) are plain string literals is fully resolvable statically.
  # Calls with dynamic arguments can't be — they are collected in #dynamic_calls
  # so callers can report them.
  class SourceExtractor
    ExtractedString = Struct.new(:key, :source_copy, :meaning, :plural, :interpolation_names, :file, :line,
      keyword_init: true)
    DynamicCall = Struct.new(:file, :line, keyword_init: true)
    FailedFile = Struct.new(:file, :message, keyword_init: true)

    GLOB = "**/*.{rb,erb}"

    def initialize(paths:)
      @paths = Array(paths)
      @strings = nil
      @dynamic_calls = []
      @failed_files = []
    end

    def strings
      extract
      @strings
    end

    def dynamic_calls
      extract
      @dynamic_calls
    end

    # Files that couldn't be processed (e.g. an .erb with invalid UTF-8 makes
    # ERB compilation raise). They are skipped — one bad file must not abort
    # the whole extraction — and reported here so callers can surface them.
    def failed_files
      extract
      @failed_files
    end

    private

    def extract
      return if @strings

      sink = {}
      files.each { |file| extract_file(file, sink) }
      @strings = sink.values
    end

    def files
      @paths.flat_map { |path| Dir[File.join(path, GLOB)].sort }
    end

    def extract_file(file, sink)
      result = Prism.parse(ruby_source(file))
      return unless result.success?

      result.value.accept(Visitor.new(file, sink, @dynamic_calls))
    rescue StandardError => e
      @failed_files << FailedFile.new(file: file, message: e.message)
    end

    def ruby_source(file)
      raw = File.read(file)
      return raw unless file.end_with?(".erb")

      compile_erb(raw)
    end

    def compile_erb(template)
      require "erubi"
      Erubi::Engine.new(template).src
    rescue LoadError
      require "erb"
      ERB.new(template, trim_mode: "-").src
    end

    class Visitor < Prism::Visitor
      def initialize(file, sink, dynamic_calls)
        @file = file
        @sink = sink
        @dynamic_calls = dynamic_calls
        super()
      end

      def visit_call_node(node)
        record(node) if e18n_t?(node)
        super # arguments may nest further E18n.t calls
      end

      private

      def e18n_t?(node)
        node.name == :t && e18n_receiver?(node.receiver)
      end

      def e18n_receiver?(receiver)
        case receiver
        when Prism::ConstantReadNode then receiver.name == :E18n
        when Prism::ConstantPathNode then receiver.name == :E18n
        else false
        end
      end

      def record(node)
        args = node.arguments&.arguments || []
        kwargs = args.last.is_a?(Prism::KeywordHashNode) ? literal_kwargs(args.last) : {}
        return dynamic!(node) if kwargs.nil?

        positional = args.grep_v(Prism::KeywordHashNode)
        meaning = kwargs[:meaning]
        forms = kwargs.slice(*KeyDeriver::PLURAL_FORM_KEYS)

        entry = if forms.any?
                  plural_entry(forms, meaning)
                elsif positional.size == 1 && (copy = literal_string(positional.first))
                  singular_entry(copy, meaning)
                end
        return dynamic!(node) unless entry

        entry.file = @file
        entry.line = node.location.start_line
        @sink[entry.key] ||= entry
      end

      # The string value of a node when it is fully static: a plain literal,
      # or adjacent-literal concatenation ("a " \ "b"), which Prism represents
      # as an InterpolatedStringNode whose parts are all plain literals. True
      # interpolation ("a #{x}") has non-literal parts and returns nil.
      def literal_string(node)
        case node
        when Prism::StringNode
          node.unescaped
        when Prism::InterpolatedStringNode
          parts = node.parts
          parts.map(&:unescaped).join if parts.all? { |part| part.is_a?(Prism::StringNode) }
        end
      end

      # The literal string values of the call's keyword arguments. Returns nil
      # when a keyword relevant to key derivation (a plural form or :meaning)
      # has a non-literal value; other keywords (count:, interpolations) are
      # runtime-only and simply ignored.
      def literal_kwargs(node)
        kwargs = {}
        node.elements.each do |assoc|
          next unless assoc.is_a?(Prism::AssocNode) && assoc.key.is_a?(Prism::SymbolNode)

          name = assoc.key.unescaped.to_sym
          next unless KeyDeriver::PLURAL_FORM_KEYS.include?(name) || name == :meaning

          value = literal_string(assoc.value)
          return nil unless value

          kwargs[name] = value
        end
        kwargs
      end

      def singular_entry(copy, meaning)
        ExtractedString.new(
          key: KeyDeriver.for_singular(copy, meaning: meaning),
          source_copy: copy,
          meaning: meaning,
          plural: false,
          interpolation_names: KeyDeriver.interpolation_names(copy),
        )
      end

      def plural_entry(forms, meaning)
        return nil unless forms.key?(:other)

        ExtractedString.new(
          key: KeyDeriver.for_plural(meaning: meaning, **forms),
          source_copy: forms.transform_keys(&:to_s),
          meaning: meaning,
          plural: true,
          interpolation_names: forms.values.flat_map { |v| KeyDeriver.interpolation_names(v) }.uniq,
        )
      end

      def dynamic!(node)
        @dynamic_calls << DynamicCall.new(file: @file, line: node.location.start_line)
        nil
      end
    end
  end
end
