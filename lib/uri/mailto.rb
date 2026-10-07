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

    # Returns the decoded mailto fields without creating or sending a message.
    #
    # The returned Hash contains:
    #
    # +:to+:: An Array of recipient mailboxes, in the order in which they
    #         appeared in the URI.
    # +:headers+:: An Array of +[field_name, field_value]+ pairs for the
    #              case-insensitive field names included in
    #              +allowed_headers+.
    # +:body+:: The decoded message body, or an empty String.
    #
    # Only +to+ and +body+ are recognized without being listed in
    # +allowed_headers+. Percent-decoding follows RFC 6068, so a literal
    # <tt>'+'</tt> is preserved instead of being converted to a space.
    #
    # Repeated +to+ fields are merged into the recipient Array. Repeated
    # occurrences of another header are handled with +duplicate_headers+.
    # The default policy, +:raise+, rejects duplicates. Other built-in
    # policies are +:first+, +:last+, +:all+, +:array+, and +:join+. A
    # callable may also be supplied; it receives the field name and an
    # Array of values and should return a String or an Array of Strings.
    #
    # CR and LF are rejected in recipient addresses and ordinary header
    # fields, while line breaks in +body+ are retained. This method does
    # not mutate the URI.
    def compose_fields(allowed_header_list = nil,
                       allowed_headers: nil,
                       duplicate_headers: :raise,
                       &duplicate_header_policy)
      permitted_header_names =
        permitted_header_names(allowed_header_list || allowed_headers)
      duplicate_policy = duplicate_header_policy || duplicate_headers

      recipients = []
      body_values = []
      header_entries = []
      header_entry_by_name = {}

      add_recipients(@to, recipients)

      @headers.each do |encoded_name, encoded_value|
        name = decode_mailto_component(encoded_name)
        value = decode_mailto_component(encoded_value.to_s)
        normalized_name = name.downcase

        case normalized_name
        when 'to'
          add_recipients(encoded_value, recipients)
        when 'body'
          body_values << value
        else
          unless permitted_header_names.include?(normalized_name)
            raise InvalidComponentError,
              "header #{name.dump} is not allowed"
          end
          reject_header_line_break('header field name', name)
          reject_header_line_break(name, value)

          entry = header_entry_by_name[normalized_name]
          unless entry
            entry = { name: name, values: [] }
            header_entry_by_name[normalized_name] = entry
            header_entries << entry
          end
          entry[:values] << value
        end
      end

      headers = header_entries.flat_map do |entry|
        resolve_duplicate_header(entry[:name], entry[:values],
                                 duplicate_policy)
      end
      body = resolve_duplicate_body(body_values, duplicate_policy)

      { to: recipients, headers: headers, body: body }
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
      to = URI.decode_www_form_component(@to)
      head = ''
      body = ''
      @headers.each do |x|
        case x[0]
        when 'body'
          body = URI.decode_www_form_component(x[1])
        when 'to'
          to << ', ' + URI.decode_www_form_component(x[1])
        else
          head << URI.decode_www_form_component(x[0]).capitalize + ': ' +
            URI.decode_www_form_component(x[1])  + "\n"
        end
      end

      "To: #{to}
#{head}
#{body}
"
    end
    alias to_rfc822text to_mailtext

    def permitted_header_names(headers)
      headers = [headers] if headers.is_a?(String) || headers.is_a?(Symbol)
      unless headers.nil? || headers.is_a?(Array)
        raise ArgumentError, 'allowed headers must be an Array, String, or Symbol'
      end

      (headers || []).map do |name|
        name = name.to_s
        if name.match?(/[\r\n]/)
          raise InvalidComponentError,
            "CR/LF is not allowed in allowed header field name: #{name.dump}"
        end
        name.downcase
      end
    end
    private :permitted_header_names

    def decode_mailto_component(component)
      URI.decode_uri_component(component)
    rescue ArgumentError
      raise InvalidComponentError,
        "invalid percent-encoding in mailto component: #{component.dump}"
    end
    private :decode_mailto_component

    def add_recipients(encoded_recipients, recipients)
      encoded_recipients.to_s.split(/[,;]/).each do |encoded_recipient|
        recipient = decode_mailto_component(encoded_recipient)
        next if recipient.empty?

        reject_header_line_break('to', recipient)
        check_mailbox(recipient)
        recipients << recipient
      end
    end
    private :add_recipients

    def check_mailbox(mailbox)
      address = mailbox
      if mailbox.end_with?('>')
        less_than = mailbox.index('<')
        unless less_than
          raise InvalidComponentError,
            "an address in 'to' is invalid: #{mailbox.dump}"
        end

        address = mailbox[(less_than + 1)...-1]
      end

      unless EMAIL_REGEXP.match?(address)
        raise InvalidComponentError,
          "an address in 'to' is invalid: #{mailbox.dump}"
      end
    end
    private :check_mailbox

    def reject_header_line_break(name, value)
      if value.match?(/[\r\n]/)
        raise InvalidComponentError,
          "CR/LF is not allowed in #{name.dump}"
      end
      value
    end
    private :reject_header_line_break

    def normalize_duplicate_policy(policy)
      policy.is_a?(String) ? policy.to_sym : policy
    end
    private :normalize_duplicate_policy

    def resolve_duplicate_header(name, values, policy)
      return [[name, values.first]] if values.size == 1

      policy = normalize_duplicate_policy(policy)
      case policy
      when :raise, :error
        raise InvalidComponentError,
          "duplicate header #{name.dump} is not allowed"
      when :first, :ignore
        [[name, values.first]]
      when :last
        [[name, values.last]]
      when :all, :keep
        values.map { |value| [name, value] }
      when :array
        [[name, values]]
      when :join, :concatenate
        [[name, values.join(', ')]]
      else
        if policy.respond_to?(:call)
          result = policy.call(name, values)
          values = Array(result)
          values.each do |value|
            unless value.is_a?(String)
              raise ArgumentError,
                "duplicate header policy must return a String or Array of Strings"
            end
            reject_header_line_break(name, value)
          end
          return values.map { |value| [name, value] }
        end

        raise ArgumentError, "invalid duplicate header policy: #{policy.inspect}"
      end
    end
    private :resolve_duplicate_header

    def resolve_duplicate_body(values, policy)
      return values.first || '' if values.size <= 1

      policy = normalize_duplicate_policy(policy)
      case policy
      when :raise, :error
        raise InvalidComponentError,
          "duplicate body field is not allowed"
      when :first, :ignore
        values.first
      when :last
        values.last
      when :all, :keep, :array, :join, :concatenate
        values.join("\r\n")
      else
        if policy.respond_to?(:call)
          result = policy.call('body', values)
          result = Array(result).join("\r\n") unless result.is_a?(String)
          return result
        end

        raise ArgumentError, "invalid duplicate header policy: #{policy.inspect}"
      end
    end
    private :resolve_duplicate_body
  end

  register_scheme 'MAILTO', MailTo
end
