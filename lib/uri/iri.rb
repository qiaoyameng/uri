# frozen_string_literal: true
#--
# = uri/iri.rb
#
# Internationalized Resource Identifier support (RFC 3987).
#
# Author:: Akira Yamada <akira@ruby-lang.org>
# License:: You can redistribute it and/or modify it under the same term as Ruby.
#
# See URI for general documentation
#

require_relative 'generic'

module URI

  #
  # Internationalized Resource Identifier (IRI) support.
  #
  # Unlike URI.parse, which stays strict and rejects non-ASCII input, the
  # methods here provide an explicit conversion between an IRI that may
  # contain Unicode characters and a plain ASCII URI.
  #
  # Unicode is handled per component.  The host is converted through an
  # IDNA encoder supplied by the caller; the userinfo, path, query and
  # fragment components are percent-encoded as UTF-8.  The path is never
  # Unicode-normalized.
  #
  class IRI

    # RFC 3986, section 2.3.
    UNRESERVED =
      ("A".."Z").to_a.join + ("a".."z").to_a.join + "0123456789" + "-._~"
    # RFC 3986, section 2.2.
    SUB_DELIMS = "!$&'()*+,;="

    # Characters that may appear literally in the userinfo component.
    USERINFO_CHARS = "#{UNRESERVED}#{SUB_DELIMS}:".freeze
    # Characters that may appear literally in the path component.
    # The slash is a path delimiter and stays literal.
    PATH_CHARS = "#{UNRESERVED}#{SUB_DELIMS}:@/".freeze
    # Characters that may appear literally in the query component.
    QUERY_CHARS = "#{UNRESERVED}#{SUB_DELIMS}:@/?".freeze
    # Characters that may appear literally in the fragment component.
    FRAGMENT_CHARS = "#{UNRESERVED}#{SUB_DELIMS}:@/?".freeze
    # Characters that may appear literally in the opaque component.
    OPAQUE_CHARS = "#{UNRESERVED}#{SUB_DELIMS}:@/?".freeze

    COMPONENT_CHARS = {
      userinfo: USERINFO_CHARS,
      path:     PATH_CHARS,
      query:    QUERY_CHARS,
      fragment: FRAGMENT_CHARS,
      opaque:   OPAQUE_CHARS,
    }.freeze
    private_constant :UNRESERVED, :SUB_DELIMS,
                     :USERINFO_CHARS, :PATH_CHARS, :QUERY_CHARS,
                     :FRAGMENT_CHARS, :OPAQUE_CHARS, :COMPONENT_CHARS

    #
    # Converts the given IRI +iri+ into a URI consisting of ASCII
    # characters only.
    #
    #   require 'uri/iri'
    #
    #   idna = ->(domain) { SimpleIDN.to_ascii(domain) }
    #   URI::IRI.encode("https://例子.测试/路/径?key=值#片", idna: idna)
    #   # => "https://xn--fsqu00a.xn--0zwm56d/%E8%B7%AF/%E5%BE%84?key=%E5%80%BC#%E7%89%87"
    #
    # Each component is processed separately:
    #
    # - The host is passed to the +idna+ callable.  Only the host is passed;
    #   the port, slashes and the rest of the address never reach it.  The
    #   returned value must be ASCII and must not contain a port or a
    #   slash, otherwise URI::InvalidURIError is raised.
    # - userinfo, path, query and fragment non-ASCII characters are
    #   encoded as their UTF-8 bytes.
    # - Existing valid percent triplets are preserved as-is; a stray
    #   percent sign is rejected.
    # - The path is not Unicode-normalized.
    #
    # Raises URI::InvalidURIError when the input cannot be converted.
    #
    def self.encode(iri, idna: nil, &block)
      encoder = idna || block
      if encoder && !encoder.respond_to?(:call)
        raise InvalidURIError, "IDNA encoder must respond to #call"
      end

      iri =
        if iri.is_a?(String)
          iri.dup
        else
          begin
            iri.to_str
          rescue NoMethodError
            raise InvalidURIError, "bad IRI (is not IRI?): #{iri.inspect}"
          end
        end
      components = split(iri)

      encoded = encode_components(components, encoder)
      uri_str = build(encoded)

      begin
        URI.parse(uri_str)
      rescue InvalidURIError
        raise
      rescue Error => error
        raise InvalidURIError, "invalid IRI: #{error.message}"
      end
      unless uri_str.ascii_only?
        raise InvalidURIError, "IRI conversion produced non-ASCII URI"
      end
      uri_str
    end

    #
    # Converts the given IRI +iri+ into an ASCII URI (see ::encode) and
    # parses it into a URI object.
    #
    #   uri = URI::IRI.parse("https://例子.测试/路", idna: idna)
    #   uri.host #=> "xn--fsqu00a.xn--0zwm56d"
    #
    def self.parse(iri, idna: nil, &block)
      URI.parse(encode(iri, idna: idna, &block))
    end

    #
    # Returns a human-readable form of the given URI, decoding only
    # percent triplets that represent displayable characters.
    #
    # Percent triplets for reserved characters (such as the path
    # delimiter <tt>%2F</tt>) are never decoded, so component boundaries
    # cannot change.  An encoded slash stays encoded:
    #
    #   URI::IRI.decode("http://example.com/a%2Fb/%E8%B7%AF")
    #   # => "http://example.com/a%2Fb/路"
    #
    # The host is not decoded; displaying an internationalized host is
    # the job of a Unicode-to-IDNA decoder, which is intentionally not
    # invoked here.
    #
    def self.decode(uri)
      uri = URI.parse(uri) unless uri.is_a?(URI::Generic)

      result = +''
      if uri.scheme
        result << uri.scheme
        result << ':'
      end

      if uri.opaque
        result << decode_component(uri.opaque)
      else
        if uri.host || %w[file postgres].include?(uri.scheme)
          result << '//'
        end
        if uri.userinfo
          result << decode_component(uri.userinfo)
          result << '@'
        end
        result << uri.host if uri.host
        if uri.port && uri.port != uri.default_port
          result << ':'
          result << uri.port.to_s
        end
        path = uri.path || ''
        if (uri.host || uri.port) && !path.empty? && !path.start_with?('/')
          result << '/'
        end
        result << decode_component(path)
        if uri.query
          result << '?'
          result << decode_component(uri.query)
        end
      end
      if uri.fragment
        result << '#'
        result << decode_component(uri.fragment)
      end
      result
    end

    class << self
      private

      # Splits an IRI into the same component shape produced by
      # RFC3986_Parser#split, but allows non-ASCII characters.
      def split(iri)
        fragment = nil
        if index = iri.index('#')
          fragment = iri[(index + 1)..-1]
          iri = iri[0...index]
        end

        scheme = nil
        if iri =~ /\A([A-Za-z][+\-.0-9A-Za-z]*):(.*)\z/m
          scheme = $1
          remainder = $2
        else
          remainder = iri
        end

        authority = nil
        path = nil
        opaque = nil
        query = nil

        if remainder.start_with?('//')
          rest = remainder[2..-1]
          authority_end = rest.index(%r{[/?]}m) || rest.bytesize
          authority = rest[0...authority_end]
          tail = rest[authority_end..-1] || ''
          if q = tail.index('?')
            path = q.zero? ? '' : tail[0...q]
            query = tail[(q + 1)..-1]
          else
            path = tail
          end
        elsif scheme
          if q = remainder.index('?')
            opaque = remainder[0...q]
            query = remainder[(q + 1)..-1]
          else
            opaque = remainder
          end
        else
          if q = remainder.index('?')
            path = remainder[0...q]
            query = remainder[(q + 1)..-1]
          else
            path = remainder
          end
        end

        userinfo, host, port = split_authority(authority)

        [scheme, userinfo, host, port, nil, path, opaque, query, fragment]
      end

      def split_authority(authority)
        return [nil, nil, nil] if authority.nil?

        if at = authority.rindex('@')
          userinfo = authority[0...at]
          hostport = authority[(at + 1)..-1]
        else
          userinfo = nil
          hostport = authority
        end

        host, port = split_host_port(hostport)
        [userinfo, host, port]
      end

      def split_host_port(hostport)
        if hostport.start_with?('[')
          close = hostport.index(']') or
            raise InvalidURIError, "bad host component: #{hostport.dump}"
          host = hostport[0..close]
          tail = hostport[(close + 1)..-1]
          if tail && !tail.empty?
            port = strip_port(tail)
          else
            port = nil
          end
        else
          colon = hostport.index(':')
          if colon
            host = hostport[0...colon]
            port = strip_port(hostport[colon..-1])
          else
            host = hostport
            port = nil
          end
        end
        [host, port]
      end

      def strip_port(tail)
        tail.start_with?(':') or
          raise InvalidURIError, "bad port component: #{tail.dump}"
        port = tail[1..-1]
        unless port.empty? || port.ascii_only? && port =~ /\A[0-9]*\z/
          raise InvalidURIError, "bad port component: #{port.dump}"
        end
        port.empty? ? nil : port
      end

      def encode_components(components, encoder)
        scheme, userinfo, host, port, _registry,
          path, opaque, query, fragment = components

        unless scheme.nil? || scheme.ascii_only?
          raise InvalidURIError, "bad scheme component: #{scheme.dump}"
        end

        encoded_userinfo =
          encode_component(userinfo, :userinfo)
        encoded_host = encode_host(host, encoder)
        encoded_path =
          encode_component(path, :path)
        encoded_opaque =
          encode_component(opaque, :opaque)
        encoded_query =
          encode_component(query, :query)
        encoded_fragment =
          encode_component(fragment, :fragment)

        [scheme, encoded_userinfo, encoded_host, port, nil,
         encoded_path, encoded_opaque, encoded_query, encoded_fragment]
      end

      def encode_component(component, kind)
        return nil if component.nil?

        unless component.ascii_only?
          begin
            component = component.encode(Encoding::UTF_8)
          rescue EncodingError
            raise InvalidURIError,
                  "component cannot be encoded as UTF-8: #{component.dump}"
          end
        end
        bytes = component.b
        unless bytes.dup.force_encoding(Encoding::UTF_8).valid_encoding?
          raise InvalidURIError,
                "bad UTF-8 sequence in #{kind} component: #{component.dump}"
        end
        raise InvalidURIError, "stray % in #{kind} component: #{component.dump}" if
          bytes.match?(/%(?!\h\h)/)

        allowed = COMPONENT_CHARS.fetch(kind).b
        out = +''
        index = 0
        total = bytes.bytesize
        while index < total
          if bytes.getbyte(index) == 0x25 && # '%'
             index + 3 <= total &&
             ascii_hex?(bytes.getbyte(index + 1)) &&
             ascii_hex?(bytes.getbyte(index + 2))
            out << bytes.byteslice(index, 3)
            index += 3
          else
            byte = bytes.getbyte(index)
            if byte < 0x80 && allowed.include?(byte.chr.b)
              out << byte
            else
              out << ('%%%02X' % byte)
            end
            index += 1
          end
        end
        out.force_encoding(Encoding::US_ASCII)
      end

      def ascii_hex?(byte)
        (0x30..0x39).cover?(byte) || # 0-9
          (0x41..0x46).cover?(byte) || # A-F
          (0x61..0x66).cover?(byte)    # a-f
      end

      def encode_host(host, encoder)
        return nil if host.nil?

        if host.start_with?('[')
          unless host.ascii_only?
            raise InvalidURIError,
                  "IP literal host must be ASCII: #{host.dump}"
          end
          return host
        end

        if host.ascii_only?
          return host
        end

        unless encoder
          raise InvalidURIError,
                "non-ASCII host needs an IDNA encoder: #{host.dump}"
        end

        encoded = begin
          encoder.call(host)
        rescue StandardError => error
          raise InvalidURIError,
                "IDNA encoder failed for #{host.dump}: #{error.message}"
        end

        unless encoded.is_a?(String)
          raise InvalidURIError,
                "IDNA encoder must return a String, got #{encoded.class}"
        end
        unless encoded.ascii_only?
          raise InvalidURIError,
                "IDNA encoder returned non-ASCII host: #{encoded.dump}"
        end
        if encoded.include?('/') || encoded.include?(':')
          raise InvalidURIError,
                "IDNA encoder returned host with port or slash: #{encoded.dump}"
        end
        unless RFC3986_PARSER.regexp[:HOST].match?("\A#{encoded}\z")
          raise InvalidURIError,
                "IDNA encoder returned invalid host: #{encoded.dump}"
        end
        encoded
      end

      def build(components)
        scheme, userinfo, host, port, _registry,
          path, opaque, query, fragment = components

        str = +''
        str << scheme << ':' if scheme
        if opaque
          str << opaque
        else
          if host || %w[file postgres].include?(scheme)
            str << '//'
          end
          if userinfo
            str << userinfo
            str << '@'
          end
          str << host unless host.nil?
          str << ':' << port if port
          str << path if path
        end
        str << '?' << query if query
        str << '#' << fragment if fragment
        str
      end

      def decode_component(component)
        return nil if component.nil?

        result = +''
        scan = component.b
        until scan.empty?
          if scan.start_with?('%') && scan.bytesize >= 3 &&
             ascii_hex?(scan.getbyte(1)) && ascii_hex?(scan.getbyte(2))
            result << decode_percent_run(scan)
            consumed = percent_run_length(scan)
            scan = scan.byteslice(consumed..-1)
          else
            result << scan.getbyte(0).chr
            scan = scan.byteslice(1..-1)
          end
        end
        result.force_encoding(Encoding::UTF_8)
      end

      def percent_run_length(scan)
        length = 0
        index = 0
        while index + 2 <= scan.bytesize - 1 &&
              scan.getbyte(index) == 0x25 &&
              ascii_hex?(scan.getbyte(index + 1)) &&
              ascii_hex?(scan.getbyte(index + 2))
          length += 3
          index += 3
        end
        length
      end

      def decode_percent_run(scan)
        bytes = +''
        run_length = percent_run_length(scan)
        index = 0
        while index < run_length
          bytes << scan.byteslice(index + 1, 2).to_i(16).chr.force_encoding(Encoding::ASCII_8BIT)
          index += 3
        end

        bytes.force_encoding(Encoding::ASCII_8BIT)
        utf8 = bytes.dup.force_encoding(Encoding::UTF_8)
        unless utf8.valid_encoding?
          return scan.byteslice(0, run_length).force_encoding(Encoding::US_ASCII)
        end

        out = +''
        encoded_pos = 0
        utf8.each_codepoint do |codepoint|
          char_bytes = codepoint.chr(Encoding::UTF_8).bytesize
          if displayable?(codepoint)
            out << codepoint
          else
            out << scan.byteslice(encoded_pos, char_bytes * 3)
          end
          encoded_pos += char_bytes * 3
        end
        out
      end

      # RFC 3987 ucschar / iprivate, minus controls, surrogates and
      # noncharacters, plus the ASCII unreserved set.
      def displayable?(codepoint)
        return true if codepoint <= 0x7E &&
                        codepoint.chr =~ /[-\.0-9A-Z_a-z~]/n
        return false if codepoint < 0xA0
        return false if (0xD800..0xDFFF).cover?(codepoint)
        return false if (0xFDD0..0xFDEF).cover?(codepoint)
        return false if codepoint & 0xFFFE == 0xFFFE
        true
      end
    end
  end
end
