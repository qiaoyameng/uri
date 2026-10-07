# frozen_string_literal: true
#
# = uri/template.rb
#
# URI::Template implements RFC 6570 URI Template expansion up to
# Level 4: all operators, prefix length and explode modifiers, list
# and associative-array variables, and percent-encoding of Unicode
# values as UTF-8.
#
# See RFC 6570[https://www.rfc-editor.org/rfc/rfc6570] for details.

require_relative "common"

module URI
  # A URI::Template holds a URI template as defined in RFC 6570 and
  # expands it into a URI reference from a mapping of variables.
  #
  #   template = URI::Template.new("https://example.com/search{?q,lang}")
  #   template.expand(q: "cats", lang: "en")
  #   #=> "https://example.com/search?q=cats&lang=en"
  #
  # The expanded result is an ordinary URI reference and can be parsed
  # with URI.parse.
  #
  # The template is parsed when it is created; syntax errors raise
  # URI::Template::InvalidTemplate immediately, before any request is
  # made.
  class Template
    # Base class for errors raised while working with URI templates.
    class Error < URI::Error; end

    # Raised at construction time when the template string does not
    # conform to the RFC 6570 template grammar.  The offending character
    # range is available through #range.
    class InvalidTemplate < Error
      # A 2-element array +[start, end]+ of zero-based, half-open
      # character offsets into the template identifying the offending
      # part.
      attr_reader :range

      def initialize(message, range)
        @range = range
        super(message)
      end
    end

    # The original template pattern as a frozen String.
    attr_reader :pattern

    # Creates a new URI::Template from +pattern+.
    #
    # Raises InvalidTemplate if +pattern+ is syntactically invalid.
    def initialize(pattern)
      pattern = String.try_convert(pattern) or
        raise TypeError, "no implicit conversion of #{pattern.class} into String"
      @pattern = -pattern.dup
      @parts = parse(@pattern)
      @pattern.freeze
      deep_freeze(@parts)
    end

    # Expands the template using +variables+ and returns the resulting
    # String.
    #
    # +variables+ may be given as a Hash and/or keyword arguments;
    # keyword arguments take precedence over Hash entries with the same
    # name.  Symbol keys are accepted as well as string keys.
    #
    #   URI::Template.new("{/who}").expand(who: "fred") #=> "/fred"
    #
    # Scalar values are converted with +to_s+.  Arrays expand as lists
    # and Hashes as associative arrays, iterated in the order given by
    # the caller.  An empty string is a defined variable; a missing key,
    # nil, an empty Array or an empty Hash is undefined.
    def expand(variables = nil, **kwargs)
      values =
        if variables.nil?
          kwargs.transform_keys(&:to_s)
        else
          unless variables.respond_to?(:to_hash)
            raise TypeError,
                  "no implicit conversion of #{variables.class} into Hash"
          end
          variables.to_hash.merge(kwargs.transform_keys(&:to_s))
        end

      buffer = +""
      @parts.each do |part|
        part.is_a?(String) ? buffer << part : buffer << expand_expression(part, values)
      end
      buffer
    end

    # Returns the original template pattern.
    def to_str
      @pattern
    end

    # Returns the original template pattern; use #expand to produce a
    # URI reference.
    def to_s
      @pattern
    end

    # Expands the template and parses the result with URI.parse.
    def to_uri(variables = nil, **kwargs)
      URI.parse(expand(variables, **kwargs))
    end

    def inspect
      "#<#{self.class}: #{@pattern}>"
    end

    private

    # operator => [first, separator, named, if_empty, reserved]
    OPERATORS = {
      "+" => ["",  ",", false, "",  true],
      "#" => ["#", ",", false, "#", true],
      "." => [".", ".", false, ".", false],
      "/" => ["/", "/", false, "",  false],
      ";" => [";", ";", true,  "",  false],
      "?" => ["?", "&", true,  "=", false],
      "&" => ["&", "&", true,  "=", false],
      nil => ["",  ",", false, "",  false],
    }.freeze

    def expand_expression(expression, values)
      operator, varspecs = expression
      first, separator, named, if_empty, reserved = OPERATORS.fetch(operator)

      segments = []
      varspecs.each do |name, explode, prefix|
        pieces = expand_varspec(name, lookup(values, name), explode, prefix,
                                named, if_empty, reserved)
        segments.concat(pieces) if pieces
      end
      segments.empty? ? "" : first + segments.join(separator)
    end

    # Returns an Array of segments (several for exploded composites), or
    # nil when the variable is undefined.
    def expand_varspec(name, value, explode, prefix, named, if_empty, reserved)
      # Varnames already consist only of unreserved characters and
      # pct-encoded triplets, so they are emitted verbatim as keys.
      key = name

      case value
      when nil
        nil
      when Array
        return nil if value.empty?
        items = value.map { |item| encode_scalar(item, nil, reserved) }
        if explode
          items.map! { |item| named ? "#{key}=#{item}" : item }
          items
        else
          body = items.join(",")
          [named ? "#{key}=#{body}" : body]
        end
      when Hash
        return nil if value.empty?
        # Keys of associative arrays are always simple-encoded, even
        # with an operator that allows reserved characters in values.
        pairs = value.map do |k, v|
          [encode(k.to_s, false), encode_scalar(v, nil, reserved)]
        end
        if explode
          pairs.map { |k, v| "#{k}=#{v}" }
        else
          body = pairs.flat_map { |k, v| [k, v] }.join(",")
          [named ? "#{key}=#{body}" : body]
        end
      else
        string = value.to_s
        string = string[0, prefix] if prefix
        encoded = encode(string, reserved)
        segment =
          if named
            string.empty? ? "#{key}#{if_empty}" : "#{key}=#{encoded}"
          else
            encoded
          end
        [segment]
      end
    end

    def lookup(values, name)
      if values.key?(name)
        values[name]
      elsif name.include?("%") && values.key?(decode_varname(name))
        values[decode_varname(name)]
      elsif values.key?(name.to_sym)
        values[name.to_sym]
      end
    end

    # Percent-decodes a variable name, e.g. "Oof%21" to "Oof!".
    def decode_varname(name)
      decoded = +"".b
      bytes = name.b
      index = 0
      while index < bytes.bytesize
        byte = bytes.getbyte(index)
        if byte == 0x25 && index + 2 < bytes.bytesize &&
           hex_byte?(bytes.getbyte(index + 1)) &&
           hex_byte?(bytes.getbyte(index + 2))
          decoded << bytes.byteslice(index + 1, 2).hex
          index += 3
        else
          decoded << byte
          index += 1
        end
      end
      decoded.force_encoding(Encoding::UTF_8)
    end

    def encode_scalar(value, prefix, reserved)
      if value.nil?
        string = ""
      elsif value.is_a?(Array) || value.is_a?(Hash)
        raise ArgumentError,
              "nested composite values are not supported: #{value.inspect}"
      else
        string = value.to_s
      end
      string = string[0, prefix] if prefix
      encode(string, reserved)
    end

    UNRESERVED_BYTES = (
      (0x30..0x39).to_a + (0x41..0x5A).to_a + (0x61..0x7A).to_a +
      "-._~".bytes
    ).freeze

    RESERVED_EXTRA = ":/?#[]@!$&'()*+,;=".bytes.freeze

    # Percent-encodes +string+ (a UTF-8 String) byte by byte.  Only
    # unreserved characters are left intact unless +reserved+ is true,
    # in which case the RFC 3986 reserved set and valid pct-encoded
    # triplets are preserved as well.
    def encode(string, reserved)
      bytes = string.encode(Encoding::UTF_8).b
      allowed = reserved ? RESERVED_EXTRA : [].freeze
      output = +""
      index = 0
      while index < bytes.bytesize
        byte = bytes.getbyte(index)
        if UNRESERVED_BYTES.include?(byte) ||
           (reserved && allowed.include?(byte))
          output << byte
          index += 1
        elsif byte == 0x25 && reserved &&
              index + 2 < bytes.bytesize &&
              hex_byte?(bytes.getbyte(index + 1)) &&
              hex_byte?(bytes.getbyte(index + 2))
          output << bytes.byteslice(index, 3)
          index += 3
        elsif byte == 0x25
          output << "%25"
          index += 1
        else
          output << "%" << byte.to_s(16).upcase.rjust(2, "0")
          index += 1
        end
      end
      output.force_encoding(Encoding::US_ASCII)
    end

    def hex_byte?(byte)
      (byte >= 0x30 && byte <= 0x39) ||
        (byte >= 0x41 && byte <= 0x46) ||
        (byte >= 0x61 && byte <= 0x66)
    end

    # ---- parsing --------------------------------------------------------

    OPERATOR_CHARS = ["+", "#", ".", "/", ";", "?", "&"].freeze
    VARNAME_CHAR = /[A-Za-z0-9_]/

    def parse(pattern)
      parts = []
      index = 0
      while index < pattern.length
        char = pattern[index]
        if char == "{"
          close = pattern.index("}", index + 1)
          unless close
            raise_invalid("unclosed expression", [index, pattern.length])
          end
          if close == index + 1
            raise_invalid("empty expression", [index, close])
          end
          parts << parse_expression(pattern, index, close)
          index = close + 1
        elsif char == "}"
          raise_invalid("unexpected '}'", [index, index + 1])
        else
          start = index
          index = scan_literal(pattern, index)
          parts << pattern[start...index]
        end
      end
      parts
    end

    def parse_expression(pattern, open, close)
      position = open + 1
      operator = nil
      if OPERATOR_CHARS.include?(pattern[position])
        operator = pattern[position]
        position += 1
      end
      if position == close
        raise_invalid("expression contains only an operator",
                      [open, close])
      end

      varspecs = []
      loop do
        name_start = position
        name, position = scan_varname(pattern, position, close)
        unless name
          range_end = position > name_start ? position : [name_start + 1, close].min
          raise_invalid("invalid variable name",
                        [name_start, range_end])
        end

        explode = false
        prefix = nil
        if position < close && pattern[position] == "*"
          explode = true
          position += 1
        elsif position < close && pattern[position] == ":"
          colon = position
          position += 1
          digits_start = position
          digits = +""
          while position < close && pattern[position] =~ /[0-9]/
            digits << pattern[position]
            position += 1
          end
          if digits.empty?
            raise_invalid("missing prefix length after ':'",
                          [colon, [colon + 2, close].min])
          end
          if digits.start_with?("0") || digits.to_i > 9999
            raise_invalid("invalid prefix length: #{digits}",
                          [digits_start, position])
          end
          prefix = digits.to_i
        end

        if position == close
          varspecs << [name, explode, prefix]
          break
        elsif pattern[position] == ","
          position += 1
          if position == close
            raise_invalid("trailing comma in expression",
                          [close - 1, close])
          end
          varspecs << [name, explode, prefix]
        else
          raise_invalid(
            "unexpected character #{pattern[position].inspect} in expression",
            [position, position + 1])
        end
      end

      [operator, varspecs]
    end

    # Scans a varname beginning at +position+ (which must be before
    # +close+).  Returns [name, new_position] or [nil, position] when no
    # valid varname starts there.  Varnames consist of unreserved
    # characters and pct-encoded triplets, joined by single dots.
    def scan_varname(pattern, position, close)
      start = position
      dot = false
      while position < close
        char = pattern[position]
        if char =~ VARNAME_CHAR
          dot = false
          position += 1
        elsif char == "."
          if dot || position == start
            return [nil, position]
          end
          dot = true
          position += 1
        elsif char == "%" && position + 3 <= close &&
              pattern[position + 1] =~ /[0-9A-Fa-f]/ &&
              pattern[position + 2] =~ /[0-9A-Fa-f]/
          dot = false
          position += 3
        else
          break
        end
      end
      if position == start || dot
        [nil, position]
      else
        [pattern[start...position], position]
      end
    end

    # Scans a literal run beginning at +index+ and returns the position
    # just past it.
    def scan_literal(pattern, index)
      position = index
      while position < pattern.length
        char = pattern[position]
        break if char == "{" || char == "}"
        if char == "%"
          unless position + 3 <= pattern.length &&
                 pattern[position + 1] =~ /[0-9A-Fa-f]/ &&
                 pattern[position + 2] =~ /[0-9A-Fa-f]/
            raise_invalid("invalid percent encoding in literal",
                          [position, position + 1])
          end
          position += 3
          next
        end
        unless literal_char?(char)
          raise_invalid("illegal literal character #{char.inspect}",
                        [position, position + 1])
        end
        position += 1
      end
      position
    end

    def literal_char?(char)
      return true if char.ascii_only? && LITERAL_ALLOWED.include?(char.ord)
      codepoint = char.ord
      return false if codepoint < 0xA0
      ucschar?(codepoint) || iprivate?(codepoint)
    end

    LITERAL_ALLOWED = (
      (0x30..0x39).to_a + (0x41..0x5A).to_a + (0x61..0x7A).to_a +
      '-._~!#$&\'()*+,;=/:?@[]'.bytes
    ).freeze

    def ucschar?(cp)
      (0x00A0..0xD7FF).cover?(cp) ||
      (0xF900..0xFDCF).cover?(cp) ||
      (0xFDF0..0xFFEF).cover?(cp) ||
      (0x10000..0x1FFFD).cover?(cp) ||
      (0x20000..0x2FFFD).cover?(cp) ||
      (0x30000..0x3FFFD).cover?(cp)
    end

    def iprivate?(cp)
      (0xE000..0xF8FF).cover?(cp) ||
        (0xF0000..0xFFFFD).cover?(cp) ||
        (0x100000..0x10FFFD).cover?(cp)
    end

    def raise_invalid(message, range)
      raise InvalidTemplate.new(message, range)
    end

    def deep_freeze(object)
      case object
      when Array
        object.each { |item| deep_freeze(item) }
        object.freeze
      when String
        object.freeze
      end
    end
  end
end

if defined?(Ractor)
  %i[OPERATORS UNRESERVED_BYTES RESERVED_EXTRA OPERATOR_CHARS
     VARNAME_CHAR LITERAL_ALLOWED].each do |constant|
    Ractor.make_shareable(URI::Template.const_get(constant))
  end
end
