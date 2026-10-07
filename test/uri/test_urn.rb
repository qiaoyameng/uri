# frozen_string_literal: false
require 'test/unit'
require 'uri/urn'

class URI::TestURN < Test::Unit::TestCase
  def uri_to_ary(uri)
    uri.class.component.collect {|c| uri.send(c)}
  end

  def test_parse_components
    u = URI("urn:example:a123,z456?+abc?=xyz#7/upc")
    assert_instance_of(URI::URN, u)
    assert_equal("urn", u.scheme)
    assert_equal("example", u.nid)
    assert_equal("a123,z456", u.nss)
    assert_equal("abc", u.r)
    assert_equal("xyz", u.q)
    assert_equal("7/upc", u.fragment)
    assert_equal(nil, u.path)
    assert_equal(nil, u.query)
    assert_equal(nil, u.host)
    assert_equal(false, u.hierarchical?)
  end

  def test_parse_optional_components
    u = URI("urn:example:a123,z456")
    assert_equal(nil, u.r)
    assert_equal(nil, u.q)
    assert_equal(nil, u.fragment)

    u = URI("urn:example:a123,z456?+abc")
    assert_equal("abc", u.r)
    assert_equal(nil, u.q)

    u = URI("urn:example:a123,z456?=xyz")
    assert_equal(nil, u.r)
    assert_equal("xyz", u.q)
  end

  # RFC 8141, Appendix A examples
  def test_rfc_examples
    [
      "urn:example:a123,z456",
      "urn:example:a123,z456?+abc",
      "urn:example:a123,z456?=xyz",
      "urn:example:a123,z456#7/upc",
      "urn:example:a123,z456?+abc?=xyz#7/upc",
      "urn:example:foo-bar-baz-qux?+CCResolve:cc=uk",
      "urn:example:foo?=a=1&b=2",
      "urn:example:a%C2%A1b?=a=1&b=2",
      "urn:example:weather?=op=map&lat=39.56&lon=-104.85&datetime=1762-07-23T21:03:52Z",
    ].each do |s|
      assert_equal(s, URI(s).to_s, s)
      assert_equal(s, URI::RFC2396_PARSER.parse(s).to_s, "rfc2396: #{s}")
    end
  end

  def test_component_order
    # When "?=" comes first, "?+" is data inside the q-component
    # (there is no r-component), and the URN still round-trips.
    u = URI("urn:example:a?=q?+r")
    assert_equal(nil, u.r)
    assert_equal("q?+r", u.q)
    assert_equal("urn:example:a?=q?+r", u.to_s)
  end

  def test_encoded_separators_are_data
    # Percent-encoded "?" must not be treated as a delimiter.
    u = URI("urn:example:a%3F+b?+r%3F%3D?=q%3F%3D")
    assert_equal("a%3F+b", u.nss)
    assert_equal("r%3F%3D", u.r)
    assert_equal("q%3F%3D", u.q)
    assert_equal("urn:example:a%3F+b?+r%3F%3D?=q%3F%3D", u.to_s)

    u = URI("urn:example:nss%23?+r%23?=q%23#f%23")
    assert_equal("nss%23", u.nss)
    assert_equal("r%23", u.r)
    assert_equal("q%23", u.q)
    assert_equal("f%23", u.fragment)
  end

  def test_bare_question_in_components
    # "?" is an allowed data character in r/q/f components.
    u = URI("urn:example:a?=a=1?b")
    assert_equal("a=1?b", u.q)
    u = URI("urn:example:a?+x?y")
    assert_equal("x?y", u.r)

    # A bare "?=" introduces the q-component at parse time, so it can
    # never be part of the r-component; assigning it via the setter is
    # rejected to preserve round-tripping.
    u = URI("urn:example:a")
    assert_raise(URI::InvalidComponentError) { u.r = "x?=y" }
  end

  def test_empty_components_rejected
    assert_raise(URI::InvalidComponentError) { URI("urn:example:a?+") }
    assert_raise(URI::InvalidComponentError) { URI("urn:example:a?=") }
  end

  def test_nid_validation
    assert_raise(URI::InvalidComponentError) { URI("urn:123:a") }       # must start with a letter
    assert_raise(URI::InvalidComponentError) { URI("urn:foo--bar:a") }  # no "--"
    assert_raise(URI::InvalidComponentError) { URI("urn:-foo:a") }      # no leading "-"
    assert_raise(URI::InvalidComponentError) { URI("urn:foo-:a") }      # no trailing "-"
    assert_raise(URI::InvalidComponentError) { URI("urn:urn:a") }       # "urn" reserved
    assert_nothing_raised { URI("urn:x-experimental:a") }
    assert_nothing_raised { URI("urn:URN-1:a") }
    assert_nothing_raised { URI("urn:a0:a") }
    assert_nothing_raised { URI("urn:a-b:a") }
    assert_nothing_raised { URI("urn:abc-def-ghi:a") }
    assert_nothing_raised { URI("urn:x--doublehyphen:a") }
    nid30 = "a" + "b" * 29
    assert_nothing_raised { URI("urn:#{nid30}:a") }
    assert_raise(URI::InvalidComponentError) { URI("urn:#{nid30}b:a") }
  end

  def test_nid_case_normalized
    u = URI("URN:EXAMPLE:a")
    assert_equal("example", u.nid)
    assert_equal("urn:example:a", u.to_s)
  end

  def test_nss_is_case_sensitive
    assert_not_equal(URI("urn:example:A"), URI("urn:example:a"))
    # Dot segments have no special meaning in a URN.
    u = URI("urn:example:a/.././b")
    assert_equal("a/.././b", u.nss)
    assert_equal("a/.././b", u.normalize.nss)
  end

  def test_build
    u = URI::URN.build(["example", "a123,z456", "abc", "xyz", "7/upc"])
    assert_equal("urn:example:a123,z456?+abc?=xyz#7/upc", u.to_s)

    u = URI::URN.build(nid: "EXAMPLE", nss: "a")
    assert_equal("urn:example:a", u.to_s)

    assert_raise(URI::InvalidComponentError) do
      URI::URN.build(nid: "1bad", nss: "a")
    end

    assert_equal(
      [:scheme, :nid, :nss, :r, :q, :fragment],
      URI::URN.component
    )
  end

  def test_setters
    u = URI("urn:example:a?+r?=q#f")
    u.nid = "ISbn"
    u.nss = "B,C"
    assert_equal("urn:isbn:B,C?+r?=q#f", u.to_s)
    u.r = nil
    assert_equal(nil, u.r)
    assert_equal("urn:isbn:B,C?=q#f", u.to_s)
    u.q = nil
    assert_equal(nil, u.q)
    assert_equal("urn:isbn:B,C#f", u.to_s)
    u.fragment = nil
    assert_equal("urn:isbn:B,C", u.to_s)
  end

  def test_setter_rejection_is_atomic
    before = "urn:example:a?+r?=q#f"
    u = URI(before)
    assert_raise(URI::InvalidComponentError) { u.nid = "1bad" }
    assert_raise(URI::InvalidComponentError) { u.nss = "bad nss!" }
    assert_raise(URI::InvalidComponentError) { u.nss = "a?b" }
    assert_raise(URI::InvalidComponentError) { u.r = "" }
    assert_raise(URI::InvalidComponentError) { u.r = "x?=y" }
    assert_raise(URI::InvalidComponentError) { u.q = "bad q#" }
    assert_raise(URI::InvalidComponentError) { u.fragment = "bad f#" }
    assert_raise(URI::InvalidURIError) { u.path = "/x" }
    assert_raise(URI::InvalidURIError) { u.query = "x" }
    assert_raise(URI::InvalidComponentError) { u.opaque = "no-colon" }
    assert_raise(URI::InvalidComponentError) { u.scheme = "http" }
    assert_equal(before, u.to_s)
    assert_equal(["example", "a", "r", "q", "f"],
      uri_to_ary(u)[1..-1])
  end

  def test_opaque_setter
    u = URI("urn:example:a")
    u.opaque = "other:b?+r?=q"
    assert_equal("other", u.nid)
    assert_equal("b", u.nss)
    assert_equal("r", u.r)
    assert_equal("q", u.q)
    assert_equal("urn:other:b?+r?=q", u.to_s)
    u.fragment = "f"
    assert_equal("f", u.fragment)
    assert_equal("urn:other:b?+r?=q#f", u.to_s)
  end

  def test_lexical_equivalence
    # NID case and percent-encoding normalization (RFC 8141, Section 3.1).
    a = URI("URN:EXAMPLE:a%2f%7eb")
    b = URI("urn:example:a%2F~b")
    assert(a.equivalent?(b))
    assert(a == b)

    # NSS case is significant.
    assert_not_send([URI("urn:example:A"), :equivalent?, URI("urn:example:a")])

    # r/q/f components are not part of URN identity.
    a = URI("urn:example:x?+r1?=q1#f1")
    b = URI("urn:example:x?+r2?=q2#f2")
    assert(a.equivalent?(b))

    assert_not_send([URI("urn:foo:x"), :equivalent?, URI("urn:bar:x")])
    assert_not_send([URI("urn:example:x"), :equivalent?, URI("http://example/x")])
    assert_send([URI("urn:example:x"), :equivalent?, "urn:example:x"])
  end

  def test_namespace_specific_equivalence_callback
    a = URI("urn:isbn:0-486-27557-4")
    b = URI("urn:isbn:0486275574")
    assert_not_send([a, :equivalent?, b])
    assert(a.equivalent?(b) {|x, y| x.nss.delete("-") == y.nss.delete("-")})
    assert_equal(false, a.equivalent?(b) { false })
  end

  def test_no_hierarchical_merge
    u = URI("urn:example:a")
    assert_raise(URI::BadURIError) { u.merge("urn:example:b") }
    assert_raise(URI::BadURIError) { u + "urn:example:b" }
    assert_raise(URI::BadURIError) { u.merge!("urn:example:b") }
  end

  def test_normalize
    u = URI("URN:EXample:A%2f%7E?+R%2f?=Q%2f#F%2f").normalize
    assert_equal("urn", u.scheme)
    assert_equal("example", u.nid)
    assert_equal("A%2F~", u.nss)
    assert_equal("R%2F", u.r)
    assert_equal("Q%2F", u.q)
    assert_equal("F%2F", u.fragment)
  end

  def test_roundtrip_encoded_delimiters
    s = "urn:example:a%3F+b/c?+r%3F+%3D?=q%3F%3D+/z#f%23/?="
    assert_equal(s, URI(s).to_s)
  end

  def test_split
    values = URI.split("urn:example:a123,z456?+abc?=xyz#7/upc")
    assert_equal(
      ["urn", nil, nil, nil, nil, nil,
       "example:a123,z456?+abc?=xyz", nil, "7/upc"],
      values
    )
  end

  def test_scheme_list
    assert_equal(URI::URN, URI.scheme_list["URN"])
  end

  def test_invalid_non_urn_opaque
    # An opaquestring that cannot be split into NID:NSS is rejected
    # once it is claimed by the URN class.
    assert_raise(URI::InvalidComponentError) { URI("urn:123") }
  end
end
