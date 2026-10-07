# frozen_string_literal: false
# = uri/mailto.rb
#
# Author:: Akira Yamada <akira@ruby-lang.org>
# License:: You can redistribute it and/or modify it under the same term as Ruby.
#
# See URI for general documentation
#

require_relative 'generic'

module URI

  #
  # RFC6068, the mailto URL scheme.
  #
  class MailTo < Generic
    include RFC2396_REGEXP

    # A Default port of nil for URI::MailTo.
    DEFAULT_PORT = nil

    # An Array of the available components for URI::MailTo.
    COMPONENT = [ :scheme, :to, :headers ].freeze

    # :stopdoc:
    #  "hname" and "hvalue" are encodings of an RFC 822 header name and
    #  value, respectively. As with "to", all URL reserved characters must
    #  be encoded.
    #
    #  "#mailbox" is as specified in RFC 822 [RFC822]. This means that it
    #  consists of zero or more comma-separated mail addresses, possibly
    #  including "phrase" and "comment" components. Note that all URL
    #  reserved characters in "to" must be encoded: in particular,
    #  parentheses, commas, and the percent sign ("%"), which commonly occur
    #  in the "mailbox" syntax.
    #
    #  Within mailto URLs, the characters "?", "=", "&" are reserved.

    # ; RFC 6068
    # hfields      = "?" hfield *( "&" hfield )
    # hfield       = hfname "=" hfvalue
    # hfname       = *qchar
    # hfvalue      = *qchar
    # qchar        = unreserved / pct-encoded / some-delims
    # some-delims  = "!" / "$" / "'" / "(" / ")" / "*"
    #              / "+" / "," / ";" / ":" / "@"
    #
    # ; RFC3986
    # unreserved   = ALPHA / DIGIT / "-" / "." / "_" / "~"
    # pct-encoded  = "%" HEXDIG HEXDIG
    HEADER_REGEXP  = /\A(?<hfield>(?:%\h\h|[!$'-.0-;@-Z_a-z~])*=(?:%\h\h|[!$'-.0-;@-Z_a-z~])*)(?:&\g<hfield>)*\z/
    # practical regexp for email address
    # https://html.spec.whatwg.org/multipage/input.html#valid-e-mail-address
    EMAIL_REGEXP = /\A[a-zA-Z0-9.!\#$%&'*+\/=?^_`{|}~-]+@[a-zA-Z0-9](?:[a-zA-Z0-9-]{0,61}[a-zA-Z0-9])?(?:\.[a-zA-Z0-9](?:[a-zA-Z0-9-]{0,61}[a-zA-Z0-9])?)*\z/
    # :startdoc:

    #
    # == Description
    #
    # Creates a new URI::MailTo object from components, with syntax checking.
    #
    # Components can be provided as an Array or Hash. If an Array is used,
    # the components must be supplied as <code>[to, headers]</code>.
    #
    # If a Hash is used, the keys are the component names preceded by colons.
    #
    # The headers can be supplied as a pre-encoded string, such as
    # <code>"subject=subscribe&cc=address"</code>, or as an Array of Arrays
    # like <code>[['subject', 'subscribe'], ['cc', 'address']]</code>.
    #
    # Examples:
    #
    #    require 'uri'
    #
    #    m1 = URI::MailTo.build(['joe@example.com', 'subject=Ruby'])
    #    m1.to_s  # => "mailto:joe@example.com?subject=Ruby"
    #
    #    m2 = URI::MailTo.build(['john@example.com', [['Subject', 'Ruby'], ['Cc', 'jack@example.com']]])
    #    m2.to_s  # => "mailto:john@example.com?Subject=Ruby&Cc=jack@example.com"
    #
    #    m3 = URI::MailTo.build({:to => 'listman@example.com', :headers => [['subject', 'subscribe']]})
    #    m3.to_s  # => "mailto:listman@example.com?subject=subscribe"
    #
    def self.build(args)
      tmp = Util.make_components_hash(self, args)

      case tmp[:to]
      when Array
        tmp[:opaque] = tmp[:to].join(',')
      when String
        tmp[:opaque] = tmp[:to].dup
      else
        tmp[:opaque] = ''
      end

      if tmp[:headers]
        query =
          case tmp[:headers]
          when Array
            tmp[:headers].collect { |x|
              if x.kind_of?(Array)
                x[0] + '=' + x[1..-1].join
              else
                x.to_s
              end
            }.join('&')
          when Hash
            tmp[:headers].collect { |h,v|
              h + '=' + v
            }.join('&')
          else
            tmp[:headers].to_s
          end
        unless query.empty?
          tmp[:opaque] << '?' << query
        end
      end

      super(tmp)
    end

    #
    # == Description
    #
    # Creates a new URI::MailTo object from generic URL components with
    # no syntax checking.
    #
    # This method is usually called from URI::parse, which checks
    # the validity of each component.
    #
    def initialize(*arg)
      super(*arg)

      @to = nil
      @headers = []

      # The RFC3986 parser does not normally populate opaque
      @opaque = "?#{@query}" if @query && !@opaque

      unless @opaque
        raise InvalidComponentError,
          "missing opaque part for mailto URL"
      end
      to, header = @opaque.split('?', 2)
      # allow semicolon as a addr-spec separator
      # http://support.microsoft.com/kb/820868
      unless /\A(?:[^@,;]+@[^@,;]+(?:\z|[,;]))*\z/ =~ to
        raise InvalidComponentError,
          "unrecognised opaque part for mailtoURL: #{@opaque}"
      end

      if arg[10] # arg_check
        self.to = to
        self.headers = header
      else
        set_to(to)
        set_headers(header)
      end
    end

    # The primary e-mail address of the URL, as a String.
    attr_reader :to

    # E-mail headers set by the URL, as an Array of Arrays.
    attr_reader :headers

    # Returns structured mailto fields suitable for confirmation before
    # creating a message.
    #
    # +allowed_headers+ is the case-insensitive list of header field names
    # that may be returned.  The reserved +to+ and +body+ fields are handled
    # separately.  +duplicate_headers+ selects how repeated header fields are
    # combined:
    #
    # - +:raise+ (the default): raise URI::InvalidComponentError.
    # - +:first+: keep the first value.
    # - +:last+: keep the last value.
    # - +:join+: combine values with <code>", "</code>.
    # - a callable: call it with the lowercase field name and values.
    #
    # Fields are decoded using RFC 6068 percent-encoding, so +"+"+ remains a
    # literal plus sign.  CR and LF are rejected in addresses, header names,
    # and ordinary header values, while decoded newlines in +body+ are
    # preserved.
    def compose_fields(allowed_headers = nil,
                       duplicate_headers: :raise,
                       on_duplicate: duplicate_headers,
                       &duplicate_handler)
      on_duplicate = duplicate_handler if duplicate_handler
      allowed = Array(allowed_headers).map do |name|
        [name.to_s.downcase, name.to_s]
      end.to_h

      result = {
        to: [],
        headers: {},
        body: nil,
      }
      header_values = {}
      body_values = []
      validate_duplicate_header_policy(on_duplicate)

      add_addresses = ->(encoded) do
        encoded.split(',').each do |part|
          address = decode_mailto_component(part)
          reject_mail_line_break(address, "address")
          result[:to] << address unless address.empty?
        end
      end

      (@to || '').split(/[,;]/).each do |encoded|
        address = decode_mailto_component(encoded)
        reject_mail_line_break(address, "address")
        result[:to] << address unless address.empty?
      end

      @headers.each do |encoded_name, encoded_value|
        name = decode_mailto_component(encoded_name || '')
        reject_mail_line_break(name, "header name")
        value = decode_mailto_component(encoded_value || '')
        field_name = name.downcase

        case field_name
        when 'to'
          add_addresses.call(value)
        when 'body'
          body_values << value
        else
          unless allowed.include?(field_name)
            raise InvalidComponentError,
              "header field #{name.dump} is not allowed"
          end

          reject_mail_line_break(value, "header value")
          (header_values[field_name] ||= []) << value
        end
      end

      header_values.each do |field_name, values|
        if values.size == 1
          result[:headers][allowed[field_name]] = values.first
        else
          result[:headers][allowed[field_name]] =
            resolve_duplicate_header(field_name, values, on_duplicate)
        end
      end

      if body_values.size > 1
        result[:body] = resolve_duplicate_header(
          'body', body_values, on_duplicate
        )
      else
        result[:body] = body_values.first
      end

      result
    end

    # Checks the to +v+ component.
    def check_to(v)
      return true unless v
      return true if v.size == 0

      v.split(/[,;]/).each do |addr|
        # check url safety as path-rootless
        if /\A(?:%\h\h|[!$&-.0-;=@-Z_a-z~])*\z/ !~ addr
          raise InvalidComponentError,
            "an address in 'to' is invalid as URI #{addr.dump}"
        end

        # check addr-spec
        # don't s/\+/ /g
        addr.gsub!(/%\h\h/, URI::TBLDECWWWCOMP_)
        if EMAIL_REGEXP !~ addr
          raise InvalidComponentError,
            "an address in 'to' is invalid as uri-escaped addr-spec #{addr.dump}"
        end
      end

      true
    end
    private :check_to

    # Private setter for to +v+.
    def set_to(v)
      @to = v
    end
    protected :set_to

    # Setter for to +v+.
    def to=(v)
      check_to(v)
      set_to(v)
      v
    end

    # Checks the headers +v+ component against either
    # * HEADER_REGEXP
    def check_headers(v)
      return true unless v
      return true if v.size == 0
      if HEADER_REGEXP !~ v
        raise InvalidComponentError,
          "bad component(expected opaque component): #{v}"
      end

      true
    end
    private :check_headers

    # Private setter for headers +v+.
    def set_headers(v)
      @headers = []
      if v
        v.split('&').each do |x|
          @headers << x.split(/=/, 2)
        end
      end
    end
    protected :set_headers

    # Setter for headers +v+.
    def headers=(v)
      check_headers(v)
      set_headers(v)
      v
    end

    # Constructs String from URI.
    def to_s
      @scheme + ':' +
        if @to
          @to
        else
          ''
        end +
        if @headers.size > 0
          '?' + @headers.collect{|x| x.join('=')}.join('&')
        else
          ''
        end +
        if @fragment
          '#' + @fragment
        else
          ''
        end
    end

    # Returns the RFC822 e-mail text equivalent of the URL, as a String.
    #
    # Example:
    #
    #   require 'uri'
    #
    #   uri = URI.parse("mailto:ruby-list@ruby-lang.org?Subject=subscribe&cc=myaddr")
    #   uri.to_mailtext
    #   # => "To: ruby-list@ruby-lang.org\nSubject: subscribe\nCc: myaddr\n\n\n"
    #
    def to_mailtext
      to = URI.decode_uri_component(@to)
      head = ''
      body = ''
      @headers.each do |x|
        case x[0]
        when 'body'
          body = URI.decode_uri_component(x[1])
        when 'to'
          to << ', ' + URI.decode_uri_component(x[1])
        else
          head << URI.decode_uri_component(x[0]).capitalize + ': ' +
            URI.decode_uri_component(x[1])  + "\n"
        end
      end

      "To: #{to}
#{head}
#{body}
"
    end
    alias to_rfc822text to_mailtext

    def decode_mailto_component(component)
      URI.decode_uri_component(component)
    rescue ArgumentError
      raise InvalidComponentError,
        "invalid percent-encoding in mailto component: #{component.dump}"
    end
    private :decode_mailto_component

    def reject_mail_line_break(value, description)
      if /[\r\n]/.match?(value)
        raise InvalidComponentError,
          "CR/LF is not allowed in mailto #{description}: #{value.dump}"
      end
    end
    private :reject_mail_line_break

    def validate_duplicate_header_policy(policy)
      return if [:raise, :first, :last, :join].include?(policy)
      return if policy.respond_to?(:call)

      raise ArgumentError,
        "unsupported duplicate header policy: #{policy.inspect}"
    end
    private :validate_duplicate_header_policy

    def resolve_duplicate_header(name, values, policy)
      case policy
      when :raise
        raise InvalidComponentError,
          "duplicate mailto header field #{name.dump}"
      when :first
        values.first
      when :last
        values.last
      when :join
        values.join(', ')
      else
        policy.call(name, values)
      end
    end
    private :resolve_duplicate_header

  end

  register_scheme 'MAILTO', MailTo
end
