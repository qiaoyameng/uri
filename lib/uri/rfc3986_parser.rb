# frozen_string_literal: true
module URI
  class RFC3986_Parser # :nodoc:
    # RFC 6874 zone identifier (ZoneID), as it appears in a URI.
    #
    # The leading delimiter "%25" is consumed by the host grammar; this
    # pattern only covers the ZoneID itself.  It accepts unreserved
    # characters (which always round-trip) and percent-encoded octets,
    # as recommended by Appendix B of RFC 6874.  An empty ZoneID and
    # malformed percent-escapes are rejected by RFC3986_Parser#split.
    ZONE_ID = /(?:%\h\h|[A-Za-z0-9\-._~])++/

    # URI defined in RFC3986
    IPV6ADDR = %r[
      (?:\h{1,4}:){6}
      (?<ls32>\h{1,4}:\h{1,4}
      | (?<IPv4address>(?<dec-octet>[1-9]\d|1\d{2}|2[0-4]\d|25[0-5]|\d)
          \.\g<dec-octet>\.\g<dec-octet>\.\g<dec-octet>)
      )
      | ::(?:\h{1,4}:){5}\g<ls32>
      | \h{1,4}?::(?:\h{1,4}:){4}\g<ls32>
      | (?:(?:\h{1,4}:)?\h{1,4})?::(?:\h{1,4}:){3}\g<ls32>
      | (?:(?:\h{1,4}:){,2}\h{1,4})?::(?:\h{1,4}:){2}\g<ls32>
      | (?:(?:\h{1,4}:){,3}\h{1,4})?::\h{1,4}:\g<ls32>
      | (?:(?:\h{1,4}:){,4}\h{1,4})?::\g<ls32>
      | (?:(?:\h{1,4}:){,5}\h{1,4})?::\h{1,4}
      | (?:(?:\h{1,4}:){,6}\h{1,4})?::
    ]x

    # Strict RFC 3986 host grammar: a zone identifier is not part of an
    # IP-literal, so URIs such as "http://[fe80::1%25eth0]/" are rejected.
    HOST = %r[
      (?<IP-literal>\[(?:
          (?<IPv6address>#{IPV6ADDR.source.delete(" \n")})
        | (?<IPvFuture>v\h++\.[!$&-.0-9:;=A-Z_a-z~]++)
        )\])
    | \g<IPv4address>
    | (?<reg-name>(?:%\h\h|[!$&-.0-9;=A-Z_a-z~])*+)
    ]x

    # RFC 6874 host grammar: an IPv6 address may carry a zone identifier
    # introduced by the literal delimiter "%25".  The zone is permitted
    # on an IPv6address only, never on IPvFuture, an IPv4 address or a
    # reg-name.
    HOST_RFC6874 = %r[
      (?<IP-literal>\[(?:
          (?<IPv6address>#{IPV6ADDR.source.delete(" \n")})
            (?:%25(?<ZoneID>#{ZONE_ID.source.delete(" \n")}))?
        | (?<IPvFuture>v\h++\.[!$&-.0-9:;=A-Z_a-z~]++)
        )\])
    | \g<IPv4address>
    | (?<reg-name>(?:%\h\h|[!$&-.0-9;=A-Z_a-z~])*+)
    ]x

    USERINFO = /(?:%\h\h|[!$&-.0-9:;=A-Z_a-z~])*+/

    SCHEME = %r[[A-Za-z][+\-.0-9A-Za-z]*+].source
    SEG = %r[(?:%\h\h|[!$&-.0-9:;=@A-Z_a-z~/])].source
    SEG_NC = %r[(?:%\h\h|[!$&-.0-9;=@A-Z_a-z~])].source
    FRAGMENT = %r[(?:%\h\h|[!$&-.0-9:;=@A-Z_a-z~/?])*+].source

    RFC3986_URI_FMT = %r[\A
    (?<seg>#{SEG}){0}
    (?<URI>
      (?<scheme>#{SCHEME}):
      (?<hier-part>//
        (?<authority>
          (?:(?<userinfo>#{USERINFO.source})@)?
          (?<host>__URI_HOST__)
          (?::(?<port>\d*+))?
        )
        (?<path-abempty>(?:/\g<seg>*+)?)
      | (?<path-absolute>/((?!/)\g<seg>++)?)
      | (?<path-rootless>(?!/)\g<seg>++)
      | (?<path-empty>)
      )
      (?:\?(?<query>[^\#]*+))?
      (?:\#(?<fragment>#{FRAGMENT}))?
    )\z]x

    RFC3986_RELATIVE_REF_FMT = %r[\A
    (?<seg>#{SEG}){0}
    (?<relative-ref>
      (?<relative-part>//
        (?<authority>
          (?:(?<userinfo>#{USERINFO.source})@)?
          (?<host>__URI_HOST__(?<!/))?
          (?::(?<port>\d*+))?
        )
        (?<path-abempty>(?:/\g<seg>*+)?)
      | (?<path-absolute>/\g<seg>*+)
      | (?<path-noscheme>#{SEG_NC}++(?:/\g<seg>*+)?)
      | (?<path-empty>)
      )
      (?:\?(?<query>[^#]*+))?
      (?:\#(?<fragment>#{FRAGMENT}))?
    )\z]x
    attr_reader :regexp

    # When +rfc6874+ is true the parser explicitly supports the
    # representation of scoped IPv6 addresses defined in
    # {RFC 6874}[https://www.rfc-editor.org/rfc/rfc6874.html], e.g.
    # "http://[fe80::1%25eth0]/".  When false (the default) such URIs
    # are rejected as required by strict RFC 3986.
    def initialize(rfc6874: false)
      @rfc6874 = rfc6874
      host = rfc6874 ? HOST_RFC6874 : HOST
      host_src = host.source.delete(" \n")
      @uri_regexp = Regexp.new(RFC3986_URI_FMT.source.sub("__URI_HOST__", host_src),
                               Regexp::EXTENDED)
      @relative_ref_regexp = Regexp.new(
        RFC3986_RELATIVE_REF_FMT.source.sub("__URI_HOST__", host_src),
        Regexp::EXTENDED)
      @regexp = default_regexp(host).each_value(&:freeze).freeze
    end

    # Returns whether this parser accepts RFC 6874 zone identifiers.
    def rfc6874?
      @rfc6874
    end

    def split(uri) #:nodoc:
      begin
        uri = uri.to_str
      rescue NoMethodError
        raise InvalidURIError, "bad URI (is not URI?): #{uri.inspect}"
      end
      uri.ascii_only? or
        raise InvalidURIError, "URI must be ascii only #{uri.dump}"
      if m = @uri_regexp.match(uri)
        query = m["query"]
        scheme = m["scheme"]
        opaque = m["path-rootless"]
        if opaque
          opaque << "?#{query}" if query
          [ scheme,
            nil, # userinfo
            nil, # host
            nil, # port
            nil, # registry
            nil, # path
            opaque,
            nil, # query
            m["fragment"]
          ]
        else # normal
          host = check_ipv6_zone(m["host"])
          [ scheme,
            m["userinfo"],
            host,
            m["port"],
            nil, # registry
            (m["path-abempty"] ||
             m["path-absolute"] ||
             m["path-empty"]),
            nil, # opaque
            query,
            m["fragment"]
          ]
        end
      elsif m = @relative_ref_regexp.match(uri)
        host = check_ipv6_zone(m["host"])
        [ nil, # scheme
          m["userinfo"],
          host,
          m["port"],
          nil, # registry,
          (m["path-abempty"] ||
           m["path-absolute"] ||
           m["path-noscheme"] ||
           m["path-empty"]),
          nil, # opaque
          m["query"],
          m["fragment"]
        ]
      else
        raise InvalidURIError, "bad URI (is not URI?): #{uri.inspect}"
      end
    end

    def parse(uri) # :nodoc:
      URI.for(*self.split(uri), self)
    end

    def join(*uris) # :nodoc:
      uris[0] = convert_to_uri(uris[0])
      uris.inject :merge
    end

    # Compatibility for RFC2396 parser
    def extract(str, schemes = nil, &block) # :nodoc:
      warn "URI::RFC3986_PARSER.extract is obsolete. Use URI::RFC2396_PARSER.extract explicitly.", uplevel: 1 if $VERBOSE
      RFC2396_PARSER.extract(str, schemes, &block)
    end

    # Compatibility for RFC2396 parser
    def make_regexp(schemes = nil) # :nodoc:
      warn "URI::RFC3986_PARSER.make_regexp is obsolete. Use URI::RFC2396_PARSER.make_regexp explicitly.", uplevel: 1 if $VERBOSE
      RFC2396_PARSER.make_regexp(schemes)
    end

    # Compatibility for RFC2396 parser
    def escape(str, unsafe = nil) # :nodoc:
      warn "URI::RFC3986_PARSER.escape is obsolete. Use URI::RFC2396_PARSER.escape explicitly.", uplevel: 1 if $VERBOSE
      unsafe ? RFC2396_PARSER.escape(str, unsafe) : RFC2396_PARSER.escape(str)
    end

    # Compatibility for RFC2396 parser
    def unescape(str, escaped = nil) # :nodoc:
      warn "URI::RFC3986_PARSER.unescape is obsolete. Use URI::RFC2396_PARSER.unescape explicitly.", uplevel: 1 if $VERBOSE
      escaped ? RFC2396_PARSER.unescape(str, escaped) : RFC2396_PARSER.unescape(str)
    end

    @@to_s = Kernel.instance_method(:to_s)
    if @@to_s.respond_to?(:bind_call)
      def inspect
        @@to_s.bind_call(self)
      end
    else
      def inspect
        @@to_s.bind(self).call
      end
    end

    private

    def default_regexp(host = HOST) # :nodoc:
      {
        SCHEME: %r[\A#{SCHEME}\z]o,
        USERINFO: %r[\A#{USERINFO}\z]o,
        HOST: %r[\A#{host}\z]x,
        ABS_PATH: %r[\A/#{SEG}*+\z]o,
        REL_PATH: %r[\A(?!/)#{SEG}++\z]o,
        QUERY: %r[\A(?:%\h\h|[!$&-.0-9:;=@A-Z_a-z~/?])*+\z],
        FRAGMENT: %r[\A#{FRAGMENT}\z]o,
        OPAQUE: %r[\A(?:[^/].*)?\z],
        PORT: /\A[\x09\x0a\x0c\x0d ]*+\d*[\x09\x0a\x0c\x0d ]*\z/,
      }
    end

    # Validates the host captured from a parsed URI and, when RFC 6874
    # support is enabled, percent-decodes its zone identifier exactly
    # once.  The decoded zone is not returned here; it is recovered from
    # the (still serialized) host by URI::Generic when the URI object is
    # constructed.  No network interface lookup or DNS resolution is
    # performed.
    def check_ipv6_zone(host)
      return host unless host && @rfc6874
      # A "%25" zone delimiter is only legal inside an IPv6 IP-literal.
      unless host.start_with?('[')
        if host.include?('%25')
          raise InvalidURIError,
            "zone identifier is only allowed with an IPv6 host: #{host.inspect}"
        end
        return host
      end

      close = host.rindex(']') or
        raise InvalidURIError, "bad URI (is not URI?): #{host.inspect}"
      inner = host[1...close]
      delimiter = inner.index('%25') or return host

      # The grammar attaches a zone only to IPv6address; reaching here
      # with a zone on an IPvFuture literal is therefore invalid.
      unless inner.start_with?(/[0-9A-Fa-f:]/) && inner[0...delimiter] =~ /:/
        raise InvalidURIError,
          "zone identifier is only allowed with an IPv6 host: #{host.inspect}"
      end

      zone = inner[(delimiter + 3)..-1]
      if zone.empty? || zone !~ /\A#{ZONE_ID}\z/o
        raise InvalidURIError,
          "bad IPv6 zone identifier in host component: #{host.inspect}"
      end

      host
    end
    private :check_ipv6_zone

    def convert_to_uri(uri)
      if uri.is_a?(URI::Generic)
        uri
      elsif uri = String.try_convert(uri)
        parse(uri)
      else
        raise ArgumentError,
          "bad argument (expected URI object or URI string)"
      end
    end

  end # class Parser
end # module URI
