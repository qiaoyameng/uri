# frozen_string_literal: true
#--
# = uri/iri.rb
#
# Author:: Akira Yamada <akira@ruby-lang.org>
# License::
#   You can redistribute it and/or modify it under the same term as Ruby.
#
# See URI for general and URI.iri_to_uri for documentation
#

module URI
  # Splits an absolute IRI reference into its components. Unlike the
  # strict RFC 3986 parser, components may contain non-ASCII characters;
  # they are handled component by component by URI.iri_to_uri.
  IRI_REFERENCE = %r{\A
    (?:(?<scheme>[A-Za-z][A-Za-z0-9+.-]*):)?
    (?://(?<authority>[^/?#]*))?
    (?<path>[^?#]*)
    (?:\?(?<query>[^\#]*))?
    (?:\#(?<fragment>.*))?
  \z}mx
  private_constant :IRI_REFERENCE

  # ASCII characters that may appear literally in each URI component
  # (RFC 3986): unreserved / sub-delims, plus the component-specific
  # extras. Anything else is percent-encoded by URI.iri_to_uri.
  IRI_COMPONENT_CHARACTERS = {
    userinfo: /\A[A-Za-z0-9\-._~!$&'()*+,;:]\z/,
    path:     /\A[A-Za-z0-9\-._~!$&'()*+,;=:@\/]\z/,
    query:    /\A[A-Za-z0-9\-._~!$&'()*+,;=:@\/?]\z/,
    fragment: /\A[A-Za-z0-9\-._~!$&'()*+,;=:@\/?]\z/,
  }.each_value(&:freeze).freeze
  private_constant :IRI_COMPONENT_CHARACTERS

  # reg-name (RFC 3986): unreserved / sub-delims / pct-encoded
  IRI_REG_NAME = /\A(?:%\h\h|[A-Za-z0-9\-._~!$&'()*+,;=])*\z/
  private_constant :IRI_REG_NAME

  IRI_PORT = /\A\d*\z/
  private_constant :IRI_PORT

  # Characters that are safe to reveal when displaying a URI: decoding
  # anything else (reserved characters, "%" itself, controls, Unicode
  # format characters such as bidi overrides) could change component
  # boundaries or spoof the displayed text, so those stay encoded.
  IRI_DISPLAY_ASCII = /\A[A-Za-z0-9\-._~]\z/
  private_constant :IRI_DISPLAY_ASCII

  IRI_NONDISPLAY_UNICODE = /\p{C}/
  private_constant :IRI_NONDISPLAY_UNICODE

  # Converts the IRI (Internationalized Resource Identifier, RFC 3987)
  # string +iri+ into a strictly ASCII, RFC 3986 compliant URI string.
  #
  # This is the explicit entry point for internationalized input:
  # URI.parse remains strict and keeps rejecting non-ASCII characters.
  #
  # Each component is converted on its own, with UTF-8 based
  # percent-encoding:
  #
  # - +userinfo+, +path+, +query+ and +fragment+ are percent-encoded
  #   according to the character set allowed in that component.
  # - A non-ASCII host is converted with the caller-provided
  #   +idna_encoder+; only the host component is ever passed to it,
  #   never the whole address.
  # - An IP literal such as <tt>[::1]</tt> is passed through as-is.
  #
  # The +idna_encoder+ may be any callable (for example a lambda or a
  # method object) taking the host string and returning its ASCII
  # (punycode) form:
  #
  #   encoder = ->(host) { MyIDNA.to_ascii(host) }
  #   URI.iri_to_uri("https://bücher.de/搜索?q=1", idna_encoder: encoder)
  #   # => "https://xn--bcher-kva.de/%E6%90%9C%E7%B4%A2?q=1"
  #
  # Existing, valid percent-encoded triplets are preserved as-is and are
  # never encoded twice. No Unicode normalization is applied anywhere:
  # two canonically equivalent but differently encoded paths remain
  # distinct, because they may identify different resources.
  #
  # URI::InvalidURIError is raised when:
  #
  # - +iri+ is not an absolute IRI reference, or contains invalid UTF-8.
  # - A component contains a stray "%" that does not start a valid
  #   percent-encoded triplet.
  # - The host contains non-ASCII characters but no +idna_encoder+
  #   was given.
  # - The +idna_encoder+ result is not a plain ASCII host name
  #   (for example when it contains a port or a path separator).
  #
  # Related: URI.uri_to_display, URI.parse.
  def self.iri_to_uri(iri, idna_encoder: nil)
    begin
      iri = iri.to_str
    rescue NoMethodError
      raise InvalidURIError, "bad IRI (is not String?): #{iri.inspect}"
    end

    case iri.encoding
    when Encoding::ASCII_8BIT
      iri = iri.dup.force_encoding(Encoding::UTF_8)
    when Encoding::UTF_8, Encoding::US_ASCII
      # already suitable
    else
      begin
        iri = iri.encode(Encoding::UTF_8)
      rescue EncodingError => e
        raise InvalidURIError, "IRI cannot be transcoded to UTF-8: #{e.message}"
      end
    end
    unless iri.valid_encoding?
      raise InvalidURIError, "IRI contains invalid UTF-8: #{iri.dump}"
    end

    match = IRI_REFERENCE.match(iri)
    unless match && match[:scheme]
      raise InvalidURIError, "bad IRI (not an absolute IRI reference): #{iri.dump}"
    end

    userinfo = host = port = nil
    if authority = match[:authority]
      userinfo, host, port = split_iri_authority(authority)
      userinfo &&= escape_iri_component(:userinfo, userinfo)
      host = convert_iri_host(host, idna_encoder)
    end

    uri = +"#{match[:scheme]}:"
    if host
      uri << "//"
      uri << "#{userinfo}@" if userinfo
      uri << host
      uri << ":#{port}" if port
    end
    uri << escape_iri_component(:path, match[:path])
    uri << "?#{escape_iri_component(:query, match[:query])}" if match[:query]
    uri << "##{escape_iri_component(:fragment, match[:fragment])}" if match[:fragment]

    # Safety net: the result must be a strictly valid, ASCII-only URI.
    unless uri.ascii_only?
      raise InvalidURIError, "conversion did not produce an ASCII URI: #{uri.dump}"
    end
    RFC3986_PARSER.split(uri)
    uri
  end

  # Converts the ASCII URI string +uri+ (or an object whose #to_s is one,
  # such as a URI::Generic) into a UTF-8 string suitable for display.
  #
  # This is the reverse direction of URI.iri_to_uri, restricted to what
  # is safe to show: only percent-encoded triplets that decode to
  # displayable characters are revealed. Encoded reserved characters
  # (such as "%2F" or "%3F"), encoded "%" itself, ASCII controls, and
  # Unicode format characters (such as bidi overrides) are always left
  # encoded, so decoding can never move a component boundary or spoof
  # the displayed text. Runs of triplets that do not form valid UTF-8
  # are left encoded as well.
  #
  #   URI.uri_to_display("https://example.com/%E6%90%9C%E7%B4%A2?q=%E4%B8%AD")
  #   # => "https://example.com/搜索?q=中"
  #   URI.uri_to_display("https://example.com/a%2Fb")
  #   # => "https://example.com/a%2Fb"
  #
  # Note that the result is meant for human consumption only; parse the
  # original URI, not the displayed form. IDNA (punycode) host names are
  # shown as-is.
  #
  # URI::InvalidURIError is raised unless +uri+ is a valid, ASCII-only
  # URI reference.
  #
  # Related: URI.iri_to_uri.
  def self.uri_to_display(uri)
    uri = uri.to_s
    unless uri.ascii_only?
      raise InvalidURIError, "URI must be ASCII only: #{uri.dump}"
    end
    RFC3986_PARSER.split(uri) # raises InvalidURIError unless valid
    match = IRI_REFERENCE.match(uri)

    display = +""
    display << "#{match[:scheme]}:" if match[:scheme]
    if authority = match[:authority]
      userinfo, host, port = split_iri_authority(authority)
      display << "//"
      display << "#{decode_iri_for_display(userinfo)}@" if userinfo
      display << decode_iri_for_display(host)
      display << ":#{port}" if port
    end
    display << decode_iri_for_display(match[:path])
    display << "?#{decode_iri_for_display(match[:query])}" if match[:query]
    display << "##{decode_iri_for_display(match[:fragment])}" if match[:fragment]
    display
  end

  # Splits an IRI authority component into [userinfo, host, port],
  # each a string or nil. The host may still be an IP literal or
  # contain non-ASCII characters at this point.
  def self.split_iri_authority(authority) # :nodoc:
    userinfo = nil
    if at = authority.rindex("@")
      userinfo = authority[0...at]
      authority = authority[(at + 1)..]
    end

    if authority.start_with?("[")
      close = authority.index("]")
      unless close
        raise InvalidURIError, "unterminated IP literal in authority: #{authority.dump}"
      end
      host = authority[0..close]
      rest = authority[(close + 1)..]
      port = nil
      if rest && !rest.empty?
        unless rest.start_with?(":") && IRI_PORT.match?(rest[1..])
          raise InvalidURIError, "bad port in authority: #{authority.dump}"
        end
        port = rest[1..]
      end
      return [userinfo, host, port]
    end

    host = authority
    port = nil
    if authority.include?(":")
      host, port = authority.split(":", 2)
      unless IRI_PORT.match?(port)
        raise InvalidURIError, "bad port in authority: #{authority.dump}"
      end
    end
    [userinfo, host, port]
  end
  private_class_method :split_iri_authority

  # Returns the ASCII form of an IRI host component: IP literals and
  # ASCII reg-names are validated and passed through, non-ASCII host
  # names are converted with the caller-provided IDNA encoder.
  def self.convert_iri_host(host, idna_encoder) # :nodoc:
    if host.start_with?("[")
      unless host.ascii_only?
        raise InvalidURIError, "non-ASCII character in IP literal: #{host.dump}"
      end
      return host
    end

    if host.ascii_only?
      validate_iri_reg_name(host)
      return host
    end

    unless idna_encoder
      raise InvalidURIError,
            "an IDNA encoder is required to convert the non-ASCII host: #{host.dump}"
    end
    ascii = idna_encoder.call(host)
    unless ascii.is_a?(String) && !ascii.empty? && ascii.ascii_only?
      raise InvalidURIError,
            "IDNA encoder must return a non-empty ASCII string, got: #{ascii.inspect}"
    end
    if ascii.include?(":") || ascii.include?("/")
      raise InvalidURIError,
            "IDNA encoder returned a host containing a port or path separator: #{ascii.dump}"
    end
    validate_iri_reg_name(ascii)
    ascii
  end
  private_class_method :convert_iri_host

  def self.validate_iri_reg_name(host) # :nodoc:
    unless IRI_REG_NAME.match?(host)
      raise InvalidURIError, "invalid character in host: #{host.dump}"
    end
  end
  private_class_method :validate_iri_reg_name

  # Percent-encodes every character of +value+ that is not allowed
  # literally in the given IRI component. Valid percent-encoded
  # triplets are preserved; a stray "%" raises InvalidURIError.
  def self.escape_iri_component(component, value) # :nodoc:
    allowed = IRI_COMPONENT_CHARACTERS.fetch(component)
    value.gsub(/%\h\h|%|./m) do |token|
      if token.start_with?("%")
        unless token.length == 3
          raise InvalidURIError,
                "invalid %-encoding in #{component} component: #{value.dump}"
        end
        token
      elsif token.ascii_only? && allowed.match?(token)
        token
      else
        escape_iri_bytes(token)
      end
    end
  end
  private_class_method :escape_iri_component

  def self.escape_iri_bytes(string) # :nodoc:
    string.b.each_byte.map { |byte| "%%%02X" % byte }.join
  end
  private_class_method :escape_iri_bytes

  # Reveals the percent-encoded triplets of a URI component that decode
  # to displayable characters; everything else is left encoded.
  def self.decode_iri_for_display(component) # :nodoc:
    component.gsub(/(?:%\h\h)+/) do |run|
      bytes = run.scan(/%\h\h/).map { |triplet| triplet[1, 2].hex }.pack("C*")
      text = bytes.force_encoding(Encoding::UTF_8)
      if text.valid_encoding?
        text.each_char.map { |char|
          displayable_iri_char?(char) ? char : escape_iri_bytes(char)
        }.join
      else
        run
      end
    end
  end
  private_class_method :decode_iri_for_display

  def self.displayable_iri_char?(char) # :nodoc:
    if char.ascii_only?
      IRI_DISPLAY_ASCII.match?(char)
    else
      !IRI_NONDISPLAY_UNICODE.match?(char)
    end
  end
  private_class_method :displayable_iri_char?
end
