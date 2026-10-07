# frozen_string_literal: true
#--
# = uri/template.rb
#
# URI Template expansion according to RFC 6570 (Level 4).
#
# See URI::Template for documentation.
#++

module URI
  # Raised when a URI Template is syntactically malformed or cannot be
  # expanded with the supplied variable values according to RFC 6570.
  class InvalidTemplateError < Error
    # Zero-based character offset of the offending part in the template.
    attr_reader :offset

    # Length in characters of the offending part.
    attr_reader :length

    def initialize(message, offset = nil, length = 1) # :nodoc:
      if offset
        super("#{message} at position #{offset}")
      else
        super(message)
      end
      @offset = offset
      @length = length
    end
  end

  # A URI Template as defined by RFC 6570 (Level 4).
  #
  # A template is a string with expressions delimited by braces, such as
  # <code>http://example.com/search{?q,lang}</code>.  Expressions are
  # expanded by #expand using a set of variable values; the resulting
  # URI reference can be parsed with the regular URI() kernel method.
  #
  # All Level 4 operators are supported:
  #
  #   {var}            simple expansion
  #   {+var}           reserved characters are passed through
  #   {#var}           fragment expansion
  #   {.var}           label expansion, dot prefixed
  #   {/var}           path segment expansion
  #   {;var}           path-style parameter expansion
  #   {?var}           form-style query expansion
  #   {&var}           form-style query continuation
  #
  # Variables may be strings, arrays (lists) or hashes (associative
  # arrays).  Arrays and hashes may be expanded with the explode
  # modifier (<code>{list*}</code>); strings may be truncated with the
  # prefix modifier (<code>{var:3}</code>), measured in Unicode
  # characters.  Percent-encoding is performed on UTF-8 bytes.
  #
  # Syntax errors are detected when the template is created, not when it
  # is expanded:
  #
  #   URI::Template.new("http://example.com/{var")
  #   # raises URI::InvalidTemplateError
  #
  # Expanded variable values are never treated as templates themselves,
  # so braces and other special characters in values are safely
  # percent-encoded.
  class Template
    # :stopdoc:
    # operator => [first, separator, named, ifemp, allow_reserved]
    OPERATORS = {
      nil => ['',  ',', false, '',  false],
      '+' => ['',  ',', false, '',  true],
      '#' => ['#', ',', false, '',  true],
      '.' => ['.', '.', false, '',  false],
      '/' => ['/', '/', false, '',  false],
      ';' => [';', ';', true,  '',  false],
      '?' => ['?', '&', true,  '=', false],
      '&' => ['&', '&', true,  '=', false],
    }.freeze

    OPERATOR_CHARS = OPERATORS.keys.compact.freeze

    # RFC 3986 "reserved" set (gen-delims and sub-delims).  Note that
    # "%" is deliberately absent: percent signs in variable values are
    # always encoded, even by reserved expansions such as {+var}.
    RESERVED_BYTES = ":/?#[]@!$&'()*+,;=".bytes.freeze

    # Non-ASCII code points allowed in literal parts: the ucschar and
    # iprivate productions of RFC 6570.
    UCS_LITERAL_RANGES = [
      0xA0..0xD7FF,
      0xE000..0xF8FF,
      0xF900..0xFDCF,
      0xFDF0..0xFFEF,
      0x10000..0x1FFFD, 0x20000..0x2FFFD, 0x30000..0x3FFFD,
      0x40000..0x4FFFD, 0x50000..0x5FFFD, 0x60000..0x6FFFD,
      0x70000..0x7FFFD, 0x80000..0x8FFFD, 0x90000..0x9FFFD,
      0xA0000..0xAFFFD, 0xB0000..0xBFFFD, 0xC0000..0xCFFFD,
      0xD0000..0xDFFFD,
      0xF0000..0xFFFFD,
      0x100000..0x10FFFD,
    ].freeze
    Ractor.make_shareable(OPERATORS) if defined?(Ractor)
    Ractor.make_shareable(OPERATOR_CHARS) if defined?(Ractor)
    Ractor.make_shareable(RESERVED_BYTES) if defined?(Ractor)
    Ractor.make_shareable(UCS_LITERAL_RANGES) if defined?(Ractor)
    # :startdoc:

    # Returns the original template string.
    attr_reader :pattern

    # Creates a new URI::Template from +pattern+.
    #
    # Raises URI::InvalidTemplateError if +pattern+ is not a valid
    # RFC 6570 Level 4 template.
    def initialize(pattern)
      unless pattern.is_a?(String)
        raise TypeError, "no implicit conversion of #{pattern.class} into String"
      end
      @pattern = pattern.dup.freeze
      @parts = parse(@pattern)
      Ractor.make_shareable(self) if defined?(Ractor)
    end

    # Expands the template using +variables+.
    #
    # +variables+ is a Hash mapping variable names to String, Array or
    # Hash values.  Keys missing from the hash (or mapped to +nil+) are
    # treated as undefined and omitted.  Arrays must contain strings and
    # hashes must use string keys and values; hashes are expanded in
    # their iteration order.  Any other value raises
    # URI::InvalidTemplateError.
    #
    # Keyword arguments may be used instead of (or together with) a
    # Hash:
    #
    #   t = URI::Template.new("http://example.com/{who}")
    #   t.expand(who: "fred")
    #     #=> "http://example.com/fred"
    #
    # Returns a String containing the expanded URI reference.
    def expand(variables = nil, **keywords)
      unless variables.nil? || variables.is_a?(Hash)
        raise TypeError, "variables must be a Hash"
      end
      data = {}
      (variables || {}).each_pair { |name, value| data[name.to_s] = value }
      keywords.each_pair       { |name, value| data[name.to_s] = value }

      result = String.new(encoding: Encoding::UTF_8)
      @parts.each do |kind, payload, extra|
        if kind == :literal
          result << payload
          next
        end

        operator, varspecs = payload, extra
        config = OPERATORS[operator]
        pieces = []
        varspecs.each do |name, explode, maxlen|
          next unless data.key?(name)
          value = data[name]
          next if value.nil?
          contribution = expand_value(value, name, config, explode, maxlen)
          pieces << contribution unless contribution.nil?
        end
        unless pieces.empty?
          result << config[0]
          result << pieces.join(config[1])
        end
      end
      result
    end

    # Returns the original template string.
    def to_s
      @pattern
    end

    def inspect # :nodoc:
      "#<URI::Template #{@pattern}>"
    end

    def ==(other) # :nodoc:
      other.is_a?(Template) && pattern == other.pattern
    end
    alias eql? ==

    def hash # :nodoc:
      [Template, @pattern].hash
    end

    private

    # Parses the template into an array of [:literal, str] and
    # [:expression, operator, varspecs] parts.
    def parse(string)
      parts = []
      literal = String.new
      index = 0
      size = string.length
      while index < size
        char = string[index]
        case char
        when '{'
          parts << [:literal, literal.dup] unless literal.empty?
          literal.clear
          expression, index = parse_expression(string, index)
          parts << expression
        when '%'
          unless hexdigit?(string[index + 1]) && hexdigit?(string[index + 2])
            raise malformed("invalid percent-encoding", index)
          end
          literal << string[index, 3]
          index += 3
        when '}'
          raise malformed("unexpected '}' without matching '{'", index)
        else
          if literal_char?(char)
            literal << char
            index += 1
          else
            raise malformed("unexpected character #{char.inspect}", index)
          end
        end
      end
      parts << [:literal, literal] unless literal.empty?
      parts
    end

    def parse_expression(string, start)
      index = start + 1
      operator = nil
      if OPERATOR_CHARS.include?(string[index])
        operator = string[index]
        index += 1
      end

      varspecs = []
      loop do
        name = String.new
        while (char = string[index])
          if char =~ /\A[A-Za-z0-9_]\z/
            name << char
            index += 1
          elsif char == '.' && !name.empty? &&
              (string[index + 1] =~ /\A[A-Za-z0-9_%]\z/)
            name << char
            index += 1
          elsif char == '%'
            unless hexdigit?(string[index + 1]) && hexdigit?(string[index + 2])
              raise malformed("invalid percent-encoding in variable name", index)
            end
            name << string[index, 3]
            index += 3
          else
            break
          end
        end
        if name.empty?
          if string[index] == '}' || string[index].nil?
            raise malformed("empty expression", start)
          end
          raise malformed("expected variable name", index)
        end

        explode = false
        maxlen = nil
        case string[index]
        when ':'
          index += 1
          digits_start = index
          digits = String.new
          while digits.length < 5 && string[index] =~ /\A[0-9]\z/
            digits << string[index]
            index += 1
          end
          if digits.empty? || digits.start_with?('0')
            raise malformed("expected prefix length (1-9999)", digits_start)
          end
          if digits.length > 4
            raise malformed("prefix length must not exceed 9999", digits_start, digits.length)
          end
          maxlen = digits.to_i
        when '*'
          explode = true
          index += 1
        end

        varspecs << [name, explode, maxlen].freeze

        case string[index]
        when ','
          index += 1
        when '}'
          index += 1
          break
        when nil
          raise malformed("unclosed expression", start)
        else
          raise malformed("unexpected character #{string[index].inspect}", index)
        end
      end

      [[:expression, operator, varspecs.freeze], index]
    end

    def expand_value(value, name, config, explode, maxlen)
      _first, _sep, named, ifemp, reserved = config

      if value.respond_to?(:to_str)
        string = as_utf8(value.to_str)
        string = prefix(string, maxlen) if maxlen
        encoded = encode(string, reserved)
        if named
          encoded.empty? ? name + ifemp : name + '=' + encoded
        else
          encoded
        end
      elsif value.is_a?(Array)
        # The prefix modifier is defined only for strings; per the
        # expansion algorithm it has no effect on list values.
        elements = value.map { |element| encode(as_utf8(as_string(element, name)), explode && reserved) }
        expand_list(name, elements, config, explode)
      elsif value.is_a?(Hash)
        # The prefix modifier is defined only for strings; per the
        # expansion algorithm it has no effect on associative arrays.
        pairs = value.map do |key, val|
          [encode(as_utf8(as_string(key, name)), false),
           encode(as_utf8(as_string(val, name)), explode && reserved)]
        end
        expand_map(name, pairs, config, explode)
      else
        raise InvalidTemplateError.new(
          "variable #{name.inspect} must contain a String, Array or Hash value")
      end
    end

    def expand_list(name, elements, config, explode)
      _first, sep, named, ifemp, _reserved = config
      if elements.empty?
        return explode_empty_composite(name, config, explode)
      end
      unless explode
        joined = elements.join(',')
        return named ? name_named(name, joined, ifemp) : joined
      end
      parts = elements.map do |element|
        if named
          element.empty? ? name + ifemp : name + '=' + element
        else
          element
        end
      end
      parts.join(sep)
    end

    def expand_map(name, pairs, config, explode)
      _first, sep, named, ifemp, _reserved = config
      if pairs.empty?
        return explode_empty_composite(name, config, explode)
      end
      unless explode
        joined = pairs.flatten.join(',')
        return named ? name_named(name, joined, ifemp) : joined
      end
      parts = pairs.map do |key, value|
        if named
          value.empty? ? key + ifemp : key + '=' + value
        else
          key + '=' + value
        end
      end
      parts.join(sep)
    end

    def name_named(name, value, ifemp)
      value.empty? ? name + ifemp : name + '=' + value
    end

    def explode_empty_composite(name, config, explode)
      # An empty composite contributes nothing to the expansion, apart
      # from exploded form-style query expressions, which still carry
      # the variable name ("{?list*}" with [] gives "?list=").
      if explode
        config[3] == '=' ? name + '=' : nil
      else
        nil
      end
    end

    def as_string(value, name)
      unless value.respond_to?(:to_str)
        raise InvalidTemplateError.new(
          "variable #{name.inspect} must contain String values")
      end
      value.to_str
    end

    # Returns +string+ encoded as UTF-8 (transcoding if needed).
    def as_utf8(string)
      if string.encoding == Encoding::UTF_8
        string
      elsif string.encoding.ascii_compatible? && string.ascii_only?
        string.dup.force_encoding(Encoding::UTF_8)
      else
        string.encode(Encoding::UTF_8)
      end
    end

    # Truncates to +maxlen+ Unicode characters.
    def prefix(string, maxlen)
      string[0, maxlen]
    end

    # Percent-encodes +string+ using UTF-8 bytes.
    #
    # When +reserved+ is true the reserved set of RFC 3986 is passed
    # through, as required by the + and # operators.
    def encode(string, reserved)
      bytes = string.b
      output = String.new(encoding: Encoding::BINARY)
      index = 0
      length = bytes.bytesize
      while index < length
        byte = bytes.getbyte(index)
        if unreserved_byte?(byte) || (reserved && RESERVED_BYTES.include?(byte))
          output << byte
          index += 1
        else
          output << '%' << format('%02X', byte)
          index += 1
        end
      end
      output.force_encoding(Encoding::UTF_8)
    end

    def unreserved_byte?(byte)
      (0x41..0x5A).cover?(byte) || # A-Z
        (0x61..0x7A).cover?(byte) || # a-z
        (0x30..0x39).cover?(byte) || # 0-9
        byte == 0x2D || byte == 0x2E || byte == 0x5F || byte == 0x7E # - . _ ~
    end

    def hexdigit?(char)
      char =~ /\A[0-9A-Fa-f]\z/
    end

    # Characters allowed literally outside an expression (RFC 6570
    # "literals"), apart from percent-encoded triplets.
    def literal_char?(char)
      c = char.ord
      case c
      when 0x21, 0x23..0x24, 0x26..0x3B, 0x3D, 0x3F..0x5B, 0x5D..0x60,
           0x61..0x7A, 0x7E
        true
      else
        UCS_LITERAL_RANGES.any? { |range| range.cover?(c) }
      end
    end

    def malformed(message, offset, length = 1)
      InvalidTemplateError.new(message, offset, length)
    end
  end
end
