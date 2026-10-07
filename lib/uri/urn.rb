# frozen_string_literal: false
# = uri/urn.rb
#
# License:: You can redistribute it and/or modify it under the same term as Ruby.
#
# See URI for general documentation
#

require_relative 'generic'

module URI

  #
  # The syntax of URNs (Uniform Resource Names) is defined in
  # {RFC 8141}[https://www.rfc-editor.org/rfc/rfc8141].
  #
  # A URN consists of an assigned-name ("urn:" + NID + ":" + NSS) followed,
  # in order, by an optional r-component ("?+"), an optional q-component
  # ("?=") and an optional f-component ("#"):
  #
  #   urn:example:foo-bar-baz-qux?+CCResolve:cc=uk?=op=map&lat=39.56#frag
  #   \_/ \_____/ \____________/ \_________________/ \_______________/ \__/
  #    |     |           |                  |                  |         |
  #  scheme NID        NSS          r-component          q-component  f
  #
  # Unlike URI::Generic, a URN has no hierarchical path: its NSS is an
  # opaque sequence of pchar (RFC 3986) and "/" characters, so no path
  # case normalization or dot-segment removal is ever performed.
  #
  class URN < Generic
    # An Array of the available components for URI::URN.
    COMPONENT = [
      :scheme,
      :nid,
      :nss,
      :r_component,
      :q_component,
      :fragment
    ].freeze

    # :stopdoc:

    # RFC 3986 productions
    PCT_ENCODED = '%\h\h'
    UNRESERVED  = "A-Za-z0-9\\-._~"
    SUB_DELIMS  = "!$&'()*+,;="
    PCHAR       = "(?:#{PCT_ENCODED}|[#{UNRESERVED}#{SUB_DELIMS}:@])"

    # NID = (alphanum) 0*30(ldh) (alphanum)   (RFC 8141 section 2)
    NID = /[A-Za-z0-9][A-Za-z0-9\-]{0,30}[A-Za-z0-9]/

    # NSS         = pchar *(pchar / "/")
    # r-component = pchar *( pchar / "/" / "?" )
    # q-component = pchar *( pchar / "/" / "?" )
    # f-component = fragment = *( pchar / "/" / "?" )
    NSS_CONTENT       = "#{PCHAR}(?:#{PCHAR}|/)*"
    RQ_CONTENT        = "#{PCHAR}(?:#{PCHAR}|[/?])*"

    NID_REGEXP  = /\A#{NID.source}\z/
    NSS_REGEXP  = /\A#{NSS_CONTENT}\z/
    RQ_REGEXP   = /\A#{RQ_CONTENT}\z/
    FRAG_REGEXP = %r{\A(?:#{PCHAR}|[/?])*\z}

    # The r-component group is lazy so that it ends at the first
    # "?=" sequence, which introduces the q-component.  A percent-encoded
    # question mark (%3F) is an ordinary pchar and never acts as a
    # delimiter.
    OPAQUE_REGEXP = /\A
      (?<nid>#{NID.source})
      :
      (?<nss>#{NSS_CONTENT})
      (?:\?\+(?<r>#{RQ_CONTENT}?))?
      (?:\?=(?<q>#{RQ_CONTENT}))?
    \z/x

    @equivalence_resolvers = {}

    class << self
      # Maps a downcased NID to a callable used for namespace-specific
      # (functional) URN equivalence tests.
      attr_reader :equivalence_resolvers
    end

    def self.inherited(subclass)
      subclass.instance_variable_set(:@equivalence_resolvers, {})
      super
    end

    # :startdoc:

    #
    # Registers a +callable+ (or the given block) implementing
    # namespace-specific (functional) equivalence rules for URNs with
    # the given +nid+.
    #
    # The callable receives two normalized URI::URN instances and must
    # return a truthy or falsey value.  It is only invoked when the two
    # URNs share the same NID and are not already equivalent according
    # to the syntax rules of RFC 8141 section 3.
    #
    #   URI::URN.register_equivalence_resolver('example') do |a, b|
    #     a.nss.downcase == b.nss.downcase
    #   end
    #
    def self.register_equivalence_resolver(nid, callable = nil, &block)
      resolver = callable || block
      unless resolver.respond_to?(:call)
        raise ArgumentError, "expected a callable (or a block) as resolver"
      end
      nid = nid.to_str.downcase
      unless /\A#{NID.source}\z/.match?(nid)
        raise InvalidComponentError, "bad NID component: #{nid.inspect}"
      end
      @equivalence_resolvers ||= {}
      @equivalence_resolvers[nid] = resolver
    end

    #
    # Creates a new URI::URN object from components, with syntax checking.
    #
    # The components can be provided as an Array in the order
    # <code>[nid, nss, r_component, q_component, fragment]</code> or as a
    # Hash with the component names as keys:
    #
    #   URI::URN.build(nid: 'example', nss: 'a123,z456')
    #   #=> #<URI::URN urn:example:a123,z456>
    #
    def self.build(args)
      tmp = Util.make_components_hash(self, args)
      tmp[:scheme] = 'urn'
      tmp[:opaque] = build_opaque(tmp[:nid], tmp[:nss],
                                 tmp[:r_component], tmp[:q_component])
      super(tmp)
    end

    # :nodoc:
    def self.build_opaque(nid, nss, r, q)
      allocate.tap do |urn|
        urn.send(:check_nid, nid)
        urn.send(:check_nss, nss)
        urn.send(:check_r_component, r)
        urn.send(:check_q_component, q)
      end
      opaque = String.new
      opaque << nid << ':' << nss
      opaque << '?+' << r if r
      opaque << '?=' << q if q
      opaque
    end
    private_class_method :build_opaque

    #
    # Creates a new URI::URN object from generic URI components with
    # syntax checking.  This is normally called from URI.parse.
    #
    def initialize(*)
      super

      unless /\Aurn\z/i.match?(@scheme.to_s)
        raise InvalidURIError,
          "bad URN (scheme must be \"urn\"): #{@scheme.inspect}"
      end
      if @query
        raise InvalidURIError,
          "bad URN (a bare \"?\" is not allowed; use \"?+\" or \"?=\")"
      end
      unless @opaque
        raise InvalidComponentError, "missing opaque part for URN"
      end

      @nid, @nss, @r_component, @q_component = parse_opaque(@opaque)
    end

    # The Namespace Identifier (NID) component of the URN.
    #
    # NIDs are case insensitive and are stored verbatim; use #normalize
    # to obtain the canonical lower-case form.
    attr_reader :nid

    # The Namespace Specific String (NSS) component of the URN.
    attr_reader :nss

    # The r-component of the URN (without its "?+" introducer), or nil.
    attr_reader :r_component

    # The q-component of the URN (without its "?=" introducer), or nil.
    attr_reader :q_component

    # Checks the NID +v+ against RFC 8141 section 2.
    def check_nid(v)
      return true if v.is_a?(String) && NID_REGEXP.match?(v)
      raise InvalidComponentError,
        "bad component(expected NID component): #{v.inspect}"
    end
    private :check_nid

    # Checks the NSS +v+ against RFC 8141 section 2.2.
    def check_nss(v)
      return true if v.is_a?(String) && NSS_REGEXP.match?(v)
      raise InvalidComponentError,
        "bad component(expected NSS component): #{v.inspect}"
    end
    private :check_nss

    # Checks the r-component +v+ against RFC 8141 section 2.3.1.
    def check_r_component(v)
      return true if v.nil?
      return true if v.is_a?(String) && RQ_REGEXP.match?(v) && !v.empty?
      raise InvalidComponentError,
        "bad component(expected r-component): #{v.inspect}"
    end
    private :check_r_component

    # Checks the q-component +v+ against RFC 8141 section 2.3.2.
    def check_q_component(v)
      return true if v.nil?
      return true if v.is_a?(String) && RQ_REGEXP.match?(v) && !v.empty?
      raise InvalidComponentError,
        "bad component(expected q-component): #{v.inspect}"
    end
    private :check_q_component

    # Checks the f-component +v+ against the RFC 3986 fragment production.
    def check_fragment(v)
      return true if v.nil?
      return true if v.is_a?(String) && FRAG_REGEXP.match?(v)
      raise InvalidComponentError,
        "bad component(expected f-component): #{v.inspect}"
    end
    private :check_fragment

    # Sets the NID component +v+ (with validation).
    def nid=(v)
      check_nid(v)
      @nid = v
      @opaque = compose_opaque
      v
    end

    # Sets the NSS component +v+ (with validation).
    #
    # No HTTP path rules (case folding or dot-segment removal) are
    # applied: the NSS is compared case-sensitively by default.
    def nss=(v)
      check_nss(v)
      @nss = v
      @opaque = compose_opaque
      v
    end

    # Sets the r-component +v+ (with validation).  Use nil to remove it.
    def r_component=(v)
      check_r_component(v)
      @r_component = v
      @opaque = compose_opaque
      v
    end

    # Sets the q-component +v+ (with validation).  Use nil to remove it.
    def q_component=(v)
      check_q_component(v)
      @q_component = v
      @opaque = compose_opaque
      v
    end

    # Sets the f-component +v+ (with validation).  Use nil to remove it.
    def fragment=(v)
      check_fragment(v)
      @fragment = v
      v
    end

    # A URN has no generic URI query component; raises InvalidComponentError.
    def query=(v)
      return @query = nil if v.nil?
      raise InvalidComponentError,
        "URN has no generic query component; use the q-component (\"?=\")"
    end

    # Sets the scheme component +v+.  Only the "urn" scheme is accepted.
    def scheme=(v)
      unless v.is_a?(String) && /\Aurn\z/i.match?(v)
        raise InvalidComponentError,
          "bad component(expected scheme component): #{v.inspect}"
      end
      set_scheme(v)
      @scheme.freeze
      v
    end

    # Replaces the whole opaque part ("NID:NSS[?+r][?=q]"), atomically.
    def opaque=(v)
      nid, nss, r, q = parse_opaque(v)
      @nid = nid
      @nss = nss
      @r_component = r
      @q_component = q
      set_opaque(compose_opaque)
      v
    end

    # Returns the normalized URN per RFC 8141 section 3.1:
    #
    # * the scheme and the NID are converted to lower case, and
    # * the hexadecimal digits A-F of percent-encoded triplets in the
    #   NSS are converted to upper case.
    #
    # Percent-encoded octets are not decoded, NSS characters keep their
    # case, and the r-, q- and f-components are left untouched.
    def normalize
      dup.normalize!
    end

    # Destructive version of #normalize.
    def normalize!
      set_scheme('urn')
      @scheme.freeze
      @nid = @nid.downcase
      @nss = @nss.gsub(/%(?<hex>\h\h)/) { "%#{$~[:hex].upcase}" }
      set_opaque(compose_opaque)
      self
    end

    #
    # Tests RFC 8141 section 3 URN-equivalence.
    #
    # Two URNs are equivalent when their assigned-name (scheme, NID and
    # NSS) octets match after the normalization performed by #normalize.
    # The r-component, q-component and f-component are ignored.
    #
    # If the assigned names differ but the (normalized) NIDs are equal,
    # the given block or +resolver+ callable may decide that the URNs are
    # nevertheless namespace-specifically (functionally) equivalent:
    #
    #   urn.equivalent?(other) do |a, b|
    #     a.nss.tr('-', '') == b.nss.tr('-', '')
    #   end
    #
    # A resolver for a NID can also be registered globally with
    # ::register_equivalence_resolver.
    #
    def equivalent?(oth, resolver = nil, &block)
      oth = URI.parse(oth) if oth.is_a?(String)
      return false unless URN === oth
      return true if self == oth

      nid = @nid.downcase
      return false unless nid == oth.nid.downcase

      callback = block || resolver || lookup_resolver(nid)
      return false unless callback

      callback.call(self.normalize, oth.normalize) ? true : false
    end

    # URNs are not hierarchical and cannot be merged.  Always raises
    # URI::BadURIError.
    def merge(*)
      raise BadURIError, "URN is not hierarchical and cannot be merged"
    end
    alias + merge

    # URNs are not hierarchical and cannot be turned into relative
    # references.  Always raises URI::BadURIError.
    def route_from(*)
      raise BadURIError, "URN is not hierarchical and cannot be relativized"
    end
    alias - route_from

    # Constructs String from URN.
    def to_s
      str = String.new
      str << @scheme << ':' << @opaque
      str << '#' << @fragment if @fragment
      str
    end
    alias to_str to_s

    #
    # Tests RFC 8141 section 3 URN-equivalence.  See #equivalent? for a
    # comparison that also consults namespace-specific rules.
    #
    def ==(oth)
      URN === oth &&
        normalize.assigned_name == oth.normalize.assigned_name
    end

    # The "urn:NID:NSS" part of the URN.
    def assigned_name
      "urn:#{@nid.downcase}:#{normalized_nss}"
    end

    private

    def lookup_resolver(nid)
      self.class.ancestors.each do |mod|
        next unless mod.is_a?(Class) && mod <= URN
        table = mod.instance_variable_get(:@equivalence_resolvers)
        return table[nid] if table && table.key?(nid)
      end
      nil
    end

    def normalized_nss
      @nss.gsub(/%(?<hex>\h\h)/) { "%#{$~[:hex].upcase}" }
    end

    def parse_opaque(str)
      unless str.is_a?(String) && (m = OPAQUE_REGEXP.match(str))
        raise InvalidComponentError,
          "bad component(expected URN assigned-name): #{str.inspect}"
      end
      [m[:nid], m[:nss], m[:r], m[:q]]
    end

    def compose_opaque
      opaque = String.new
      opaque << @nid << ':' << @nss
      opaque << '?+' << @r_component if @r_component
      opaque << '?=' << @q_component if @q_component
      opaque
    end
  end

  register_scheme 'URN', URN
end
