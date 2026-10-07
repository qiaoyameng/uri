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
  # Uniform Resource Name (URN) scheme, as specified in RFC 8141.
  #
  # Unlike URI::Generic, a URN is not hierarchical: it has no host or path,
  # and reference resolution (URI#merge) is not applicable.
  #
  #   require 'uri'
  #
  #   urn = URI("urn:example:a123,z456?+abc?=xyz#7/upc")
  #   #=> #<URI::URN urn:example:a123,z456?+abc?=xyz#7/upc>
  #   urn.nid        #=> "example"
  #   urn.nss        #=> "a123,z456"
  #   urn.r          #=> "abc"
  #   urn.q          #=> "xyz"
  #   urn.fragment   #=> "7/upc"
  #
  class URN < Generic
    # An Array of the available components for URI::URN.
    COMPONENT = [
      :scheme,
      :nid,
      :nss,
      :r,
      :q,
      :fragment
    ].freeze

    # :stopdoc:

    # RFC 8141, Section 2:
    #
    #   NID        = (let-num) [ 1,30 ]
    #              / "X-" let-NUM-HYPHEN
    #              / "urn-" let-NUM-HYPHEN
    #
    # The NID is case-insensitive and, when present, must not start or end
    # with a hyphen nor contain "--" (RFC 8141, Section 2.1).
    # A formal NID is 2 to 30 characters long, starts with a letter,
    # contains only letters, digits and single hyphens, and neither
    # starts nor ends with a hyphen.
    NID_REGEXP = /\A(?:(?=.{2,30}\z)[A-Za-z](?:[A-Za-z0-9]|-(?=[A-Za-z0-9]))*|[Xx]-[A-Za-z0-9]*(?:-(?=[A-Za-z0-9])[A-Za-z0-9]*)*|[Uu][Rr][Nn]-[A-Za-z0-9]*(?:-(?=[A-Za-z0-9])[A-Za-z0-9]*)*)\z/

    # RFC 3986:
    #   pchar         = unreserved / pct-encoded / sub-delims / ":" / "@"
    #   unreserved    = ALPHA / DIGIT / "-" / "." / "_" / "~"
    #   sub-delims    = "!" / "$" / "&" / "'" / "(" / ")" / "*" / "+"
    #                 / "," / ";" / "="
    PCHAR = /(?:%\h\h|[A-Za-z0-9\-._~!$&'()*+,;=:@])/.freeze

    # RFC 8141: NSS = pchar *(pchar / "/")
    NSS_REGEXP = /\A#{PCHAR}(?:#{PCHAR}|\/)*\z/

    # RFC 8141: r-component = pchar *( pchar / "/" / "?" )
    #           q-component = pchar *( pchar / "/" / "?" )
    COMPONENT_REGEXP = /\A#{PCHAR}(?:#{PCHAR}|[\/?])*\z/

    # RFC 3986: fragment = *( pchar / "/" / "?" )
    FRAGMENT8141_REGEXP = /\A(?:#{PCHAR}|[\/?])*\z/

    UNRESERVED = /\A[A-Za-z0-9\-._~]\z/.freeze
    # :startdoc:

    #
    # Creates a new URI::URN object from components, with syntax checking.
    #
    # Components can be provided as an Array (+[nid, nss, r, q, fragment]+)
    # or as a Hash using the keys +:nid+, +:nss+, +:r+, +:q+ and
    # +:fragment+.
    #
    # Examples:
    #
    #   require 'uri'
    #
    #   URI::URN.build(['example', 'a123,z456', 'abc', 'xyz', '7/upc']).to_s
    #   #=> "urn:example:a123,z456?+abc?=xyz#7/upc"
    #
    #   URI::URN.build(nid: 'example', nss: 'a123,z456').to_s
    #   #=> "urn:example:a123,z456"
    #
    def self.build(args)
      tmp = Util.make_components_hash(self, args)

      nid = check_nid_value(tmp[:nid])
      nss = tmp[:nss]
      r = tmp[:r]
      q = tmp[:q]
      fragment = tmp[:fragment]

      check_nss_value(nss)
      check_component_value(r, :'r-component') unless r.nil?
      check_component_value(q, :'q-component') unless q.nil?
      check_fragment_value(fragment)

      opaque = "#{nid}:#{nss}"
      opaque << "?+#{r}" if r
      opaque << "?=#{q}" if q

      tmp[:opaque] = opaque
      tmp.delete(:nid)
      tmp.delete(:nss)
      tmp.delete(:r)
      tmp.delete(:q)

      super(tmp)
    end

    #
    # Creates a new URI::URN object from generic URI components with no
    # syntax checking.
    #
    # This method is usually called from URI.parse, which checks the
    # validity of each component.
    #
    def initialize(*arg)
      # The generic parsers fold everything after the first "?" into the
      # query component; move it back into the opaque part so that the URN
      # itself owns the "?+" / "?=" separators.
      if arg[6] && arg[7]
        arg = arg.dup
        arg[6] = "#{arg[6]}?#{arg[7]}"
        arg[7] = nil
      end

      super(*arg)

      unless @scheme.nil? || @scheme == 'urn'
        raise InvalidComponentError,
          "bad component(expected urn scheme): #{@scheme}"
      end

      parse_urn(@opaque)

      # Keep the generic opaque representation exactly in sync with the
      # parsed components (this also normalizes the NID case in it).
      update_opaque
    end

    # The Namespace Identifier (NID), normalized to lower case.
    attr_reader :nid

    # The Namespace Specific String (NSS).
    attr_reader :nss

    # The r-component (Resolution Parameters), or nil when absent.
    attr_reader :r

    # The q-component (Query Parameters), or nil when absent.
    attr_reader :q

    #
    # Parses the URN-specific part ("NID:NSS[?+R][?=Q]") into components.
    #
    # A percent-encoded separator (e.g. "%3F+") is never treated as a
    # component delimiter.
    #
    def self.parse_components(s)
      colon = s.index(':') or
        raise InvalidComponentError,
          "bad component(expected NID component): #{s.inspect}"

      nid = s[0, colon]
      nid = check_nid_value(nid)

      rest = s[(colon + 1)..-1]

      # RFC 8141 Section 2: the r-component is introduced by the first
      # "?+" and the q-component by the first "?=" that follows it.
      r_index = rest.index('?+')
      q_index = rest.index('?=')

      if r_index && (q_index.nil? || r_index < q_index)
        nss = rest[0, r_index]
        q_after = rest.index('?=', r_index + 2)
        if q_after
          r = rest[(r_index + 2)...q_after]
          q = rest[(q_after + 2)..-1]
        else
          r = rest[(r_index + 2)..-1]
          q = nil
        end
      elsif q_index
        nss = rest[0, q_index]
        r = nil
        q = rest[(q_index + 2)..-1]
      else
        nss = rest
        r = nil
        q = nil
      end

      check_nss_value(nss)
      check_component_value(r, :'r-component') unless r.nil?
      check_component_value(q, :'q-component') unless q.nil?

      [nid, nss, r, q]
    end

    # Checks the NID +v+ component for RFC 8141 compliance, returning
    # the normalized (lower case) NID.
    def self.check_nid_value(v)
      unless v.is_a?(String) && NID_REGEXP.match?(v)
        raise InvalidComponentError,
          "bad component(expected NID component): #{v.inspect}"
      end
      if v.downcase == 'urn'
        raise InvalidComponentError,
          "the NID \"urn\" is reserved: #{v.inspect}"
      end
      v.downcase
    end

    # Checks the NSS +v+ component for RFC 8141 compliance.
    def self.check_nss_value(v)
      unless v.is_a?(String) && NSS_REGEXP.match?(v)
        raise InvalidComponentError,
          "bad component(expected NSS component): #{v.inspect}"
      end
      true
    end

    # Checks an r-/q-component +v+ for RFC 8141 compliance.
    def self.check_component_value(v, name)
      unless v.is_a?(String) && !v.empty? && COMPONENT_REGEXP.match?(v)
        raise InvalidComponentError,
          "bad component(expected #{name} component): #{v.inspect}"
      end
      # A bare "?=" inside the r-component would be mistaken for the
      # q-component delimiter on the next parse, breaking round-tripping.
      # It has to be percent-encoded ("%3F=").
      if name == :'r-component' && v.include?('?=')
        raise InvalidComponentError,
          "bad component(expected r-component component): #{v.inspect}"
      end
      true
    end

    # Checks the fragment +v+ component for RFC 3986 compliance.
    def self.check_fragment_value(v)
      unless v.nil? || (v.is_a?(String) && FRAGMENT8141_REGEXP.match?(v))
        raise InvalidComponentError,
          "bad component(expected fragment component): #{v.inspect}"
      end
      true
    end

    #
    # == Description
    #
    # Public setter for the NID component +v+ (with validation).
    # The NID is case-insensitive and stored normalized to lower case.
    #
    def nid=(v)
      nid = self.class.check_nid_value(v)
      @nid = nid
      update_opaque
      v
    end

    #
    # == Description
    #
    # Public setter for the NSS component +v+ (with validation).
    # The NSS is case-sensitive and is never subjected to HTTP-style
    # path case or dot-segment normalization.
    #
    def nss=(v)
      self.class.check_nss_value(v)
      @nss = v
      update_opaque
      v
    end

    # Public setter for the r-component +v+ (with validation).
    # Use nil to remove the component.
    def r=(v)
      self.class.check_component_value(v, :'r-component') unless v.nil?
      @r = v
      update_opaque
      v
    end

    # Public setter for the q-component +v+ (with validation).
    # Use nil to remove the component.
    def q=(v)
      self.class.check_component_value(v, :'q-component') unless v.nil?
      @q = v
      update_opaque
      v
    end

    # Public setter for the fragment component +v+ (with validation).
    # Use nil to remove the component.
    def fragment=(v)
      self.class.check_fragment_value(v)
      @fragment = v
      v
    end

    # A URN is never hierarchical.
    def hierarchical?
      false
    end

    # A URN has no path; the NSS is accessed via #nss.
    def path
      nil
    end

    # The generic query component is unused; URN query data lives in #q.
    def query
      nil
    end

    # A URN does not use the generic query component; use #q instead.
    def query=(v)
      return if v.nil?
      raise InvalidURIError,
        "URN does not use the generic query component; use q= for the q-component"
    end

    # A URN does not have a hierarchical path; use #nss instead.
    def path=(v)
      return if v.nil?
      raise InvalidURIError,
        "URN does not use the path component; use nss= instead (#{v.inspect})"
    end

    #
    # Replaces the whole opaque part ("NID:NSS[?+R][?=Q]").
    #
    # The new value is fully validated and parsed into components
    # before any state changes, so a rejected value leaves the object
    # untouched.
    #
    def opaque=(v)
      nid, nss, r, q = self.class.parse_components(v)
      @nid = nid
      @nss = nss
      @r = r
      @q = q
      update_opaque
      v
    end

    # Only the "urn" scheme is accepted.
    def scheme=(v)
      check_scheme(v)
      unless v.nil? || v.downcase == 'urn'
        raise InvalidComponentError,
          "bad component(expected urn scheme): #{v}"
      end
      set_scheme(v)
      v
    end

    #
    # URNs are opaque and do not participate in hierarchical reference
    # resolution; see RFC 8141 and RFC 3986 Section 5.
    #
    def merge(oth)
      raise BadURIError, "cannot merge with a URN: #{self}"
    end
    alias + merge

    def merge!(oth)
      merge(oth)
    end

    #
    # Returns the normalized URN (RFC 8141 Section 3.1).
    #
    # Lexical normalization:
    # * the scheme and NID are converted to lower case;
    # * percent-encoding triplets are converted to upper case in the NSS,
    #   r-, q- and f-components;
    # * percent-encoded unreserved characters are decoded in those
    #   components.
    #
    # No case folding is applied to the NSS or the r-/q-components, and
    # no HTTP-style dot-segment removal is performed.
    #
    def normalize
      uri = dup
      uri.normalize!
      uri
    end

    # Destructive version of #normalize.
    def normalize!
      set_scheme(@scheme.downcase) if @scheme
      @nid = @nid.downcase if @nid
      @nss = lexical_normalize(@nss) if @nss
      @r = lexical_normalize(@r) if @r
      @q = lexical_normalize(@q) if @q
      @fragment = lexical_normalize(@fragment) if @fragment
      update_opaque
      self
    end

    #
    # URN "lexical equivalence" as defined in RFC 8141 Section 3:
    # two URNs are equivalent when their scheme, NID and NSS are equal
    # after the syntax-based normalizations of Section 3.1.
    #
    # The r-, q- and f-components are not part of URN identity and are
    # ignored.
    #
    # Equivalence which depends on the semantics of a particular
    # namespace is delegated to the given block/callback, which receives
    # the two URI::URN objects:
    #
    #   urn1.equivalent?(urn2) do |a, b|
    #     MyNamespace.equivalent?(a.nss, b.nss)
    #   end
    #
    def equivalent?(oth, &block)
      oth = URI.parse(oth) if oth.is_a?(String)
      return false unless oth.is_a?(URI::URN)
      return false unless scheme == oth.scheme
      return false unless nid == oth.nid

      return block.call(self, oth) ? true : false if block

      lexical_normalize(nss) == lexical_normalize(oth.nss)
    end

    private

    def parse_urn(s)
      unless s.is_a?(String) && !s.empty?
        raise InvalidComponentError,
          "bad component(expected opaque component): #{s.inspect}"
      end

      @nid, @nss, @r, @q = self.class.parse_components(s)
      self.class.check_fragment_value(@fragment)
    end

    # Rebuilds the opaque part from the URN components, keeping it
    # consistent whenever a setter changes a component.
    def update_opaque
      raise InvalidComponentError, "missing NID component" unless @nid
      raise InvalidComponentError, "missing NSS component" unless @nss
      s = "#{@nid}:#{@nss}"
      s << "?+#{@r}" if @r
      s << "?=#{@q}" if @q
      set_opaque(s)
      s
    end

    # RFC 8141 Section 3.1 syntax-based normalization of one component:
    # upper-case percent-triplets and decode percent-encoded unreserved
    # characters.
    def lexical_normalize(s)
      s.gsub(/%(\h\h)/) do
        byte = $1.to_i(16).chr
        if byte.match?(UNRESERVED)
          byte
        else
          "%#{$1.upcase}"
        end
      end
    end
  end

  register_scheme 'URN', URN
end
