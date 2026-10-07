# frozen_string_literal: false
require 'test/unit'
require 'uri/urn'

class URI::TestURN < Test::Unit::TestCase
  def uri_components(uri)
    [uri.scheme, uri.nid, uri.nss,
     uri.r_component, uri.q_component, uri.fragment]
  end

  def test_scheme_registered
    assert_equal(URI::URN, URI.scheme_list['URN'])
    assert_kind_of(URI::URN, URI('urn:example:a'))
  end

  def test_components
    u = URI('urn:example:foo-bar-baz-qux?+CCResolve:cc=uk?=op=map&lat=39.56#frag')
    assert_equal('urn', u.scheme)
    assert_equal('example', u.nid)
    assert_equal('foo-bar-baz-qux', u.nss)
    assert_equal('CCResolve:cc=uk', u.r_component)
    assert_equal('op=map&lat=39.56', u.q_component)
    assert_equal('frag', u.fragment)
    assert_nil(u.host)
    assert_nil(u.port)
    assert_nil(u.path)
    assert_nil(u.query)
  end

  def test_component_list
    assert_equal([:scheme, :nid, :nss, :r_component, :q_component, :fragment],
                 URI::URN.component)
    u = URI('urn:example:nss?+r?=q#f')
    assert_equal(['example', 'nss', 'f'], u.select(:nid, :nss, :fragment))
    assert_raise(ArgumentError) { u.select(:host) }
  end

  def test_rfc8141_examples_round_trip
    # RFC 8141 sections 2.3 and 3.2
    samples = [
      'urn:example:a123,z456',
      'urn:example:foo-bar-baz-qux?+CCResolve:cc=uk',
      'urn:example:weather?=op=map&lat=39.56&lon=-104.85&datetime=1969-07-21T02:56:15Z',
      'urn:example:foo-bar-baz-qux#somepart',
      'urn:example:1/406/47452/2',
      'urn:example:apple:pear:plum:cherry',
      'urn:example:a123,z456?+abc',
      'urn:example:a123,z456?=xyz',
      'urn:example:a123,z456#789',
      'urn:EXAMPLE:a123%2cz456',
    ]
    samples.each do |s|
      u = URI(s)
      assert_kind_of(URI::URN, u)
      assert_equal(s, u.to_s, "round trip #{s.inspect}")
    end
  end

  def test_optional_component_combos
    assert_equal([nil, nil], components_of('urn:example:x')[3, 2])
    assert_equal(['r', nil], components_of('urn:example:x?+r')[3, 2])
    assert_equal([nil, 'q'], components_of('urn:example:x?=q')[3, 2])
    assert_equal(['r', 'q'], components_of('urn:example:x?+r?=q')[3, 2])
    assert_equal(['r', 'q'], components_of('urn:example:x?+r?=q#f')[3, 2])
    assert_equal([nil, 'q'], components_of('urn:example:x?=q#f')[3, 2])
    assert_equal('r', components_of('urn:example:x?+r#f')[3])
  end

  def test_empty_fragment
    assert_equal('', URI('urn:example:x#').fragment)
    assert_equal('urn:example:x#', URI('urn:example:x#').to_s)
  end

  def test_percent_encoded_delimiters_are_data
    # "%3F" and "%23" must never be treated as separators.
    u = URI('urn:example:a%3Fb?+r%3Fx%23?=q%3Fy#f%23z')
    assert_equal('a%3Fb', u.nss)
    assert_equal('r%3Fx%23', u.r_component)
    assert_equal('q%3Fy', u.q_component)
    assert_equal('f%23z', u.fragment)
    assert_equal('urn:example:a%3Fb?+r%3Fx%23?=q%3Fy#f%23z', u.to_s)
  end

  def test_literal_question_in_components
    u = URI('urn:example:nss?+a?b?=c?d#e?f')
    assert_equal('a?b', u.r_component)
    assert_equal('c?d', u.q_component)
    assert_equal('e?f', u.fragment)
    # "?+" after the r-component introducer is data; only "?=" ends it.
    u = URI('urn:example:nss?+x?+y%3F=z?=q')
    assert_equal('x?+y%3F=z', u.r_component)
    assert_equal('q', u.q_component)
    # A "?=" inside the f-component is data.
    assert_equal('z?=w', URI('urn:example:a#z?=w').fragment)
  end

  def test_nid_bounds
    assert_nothing_raised { parse('urn:ab:nss') }                       # 2 chars
    assert_nothing_raised do
      parse("urn:#{'a' * 32}:nss")                                      # 32 chars
    end
    invalid('urn:a:nss')                                                 # too short
    invalid('urn::nss')                                                  # empty
    invalid('urn:-ab:nss')                                               # leading "-"
    invalid('urn:ab-:nss')                                               # trailing "-"
    assert_nothing_raised { parse('urn:a-b:nss') }                        # 3 chars, valid
    invalid("urn:#{'a' * 33}:nss")                                       # too long
    invalid('urn:ab_c:nss')                                              # underscore
    invalid('urn:ab.c:nss')                                              # dot
  end

  def test_nss_rules
    assert_nothing_raised { parse('urn:example:a/b/c') }
    assert_nothing_raised { parse('urn:example:pchar!:$&\'()*+,;=@._~-') }
    invalid('urn:example:')          # empty NSS
    invalid('urn:example:a?b')       # bare "?" in the NSS
    assert_equal(['a', 'b'],
                 lambda { |x| [x.nss, x.fragment] }.call(URI('urn:example:a#b')))
    invalid('urn:example:a%2')       # truncated pct
    invalid('urn:example:a%2g')      # non-hex pct
  end

  def test_empty_optional_components
    invalid('urn:example:a?+')
    invalid('urn:example:a?=')
  end

  def test_ordering
    # A bare "?" not followed by "+" or "=" is a syntax error.
    invalid('urn:example:a?x')
    invalid('urn:example:a?')
  end

  def test_non_ascii_rejected
    assert_raise(URI::InvalidURIError) { URI("urn:example:\u{e9}") }
    assert_raise(URI::InvalidComponentError) do
      URI::URN.build(nid: 'example', nss: "\u{e9}")
    end
  end

  def test_build_array_and_hash
    u = URI::URN.build(['EXAMPLE', 'a123,z456', 'r', 'q', 'f'])
    assert_equal('urn:EXAMPLE:a123,z456?+r?=q#f', u.to_s)
    assert_equal(['EXAMPLE', 'a123,z456', 'r', 'q', 'f'],
                 uri_components(u)[1..])

    u = URI::URN.build(nid: 'example', nss: 'x/y', q_component: 'q')
    assert_equal('urn:example:x/y?=q', u.to_s)
    assert_nil(u.r_component)
  end

  def test_build_invalid
    assert_raise(URI::InvalidComponentError) do
      URI::URN.build(nid: 'x', nss: 'y')
    end
    assert_raise(URI::InvalidComponentError) do
      URI::URN.build(nid: 'example', nss: '')
    end
    assert_raise(URI::InvalidComponentError) do
      URI::URN.build(nid: 'example', nss: 'a', r_component: '')
    end
  end

  def test_build2_escapes
    u = URI::URN.build2(nid: 'example', nss: 'a b')
    assert_equal('urn:example:a%20b', u.to_s)
  end

  def test_normalize
    u = URI('URN:EXAMPLE:a123%2cz456?+rR?=qQ#fF')
    n = u.normalize
    assert_equal('urn:EXAMPLE:a123%2cz456?+rR?=qQ#fF', u.to_s,
                 'normalize does not mutate the receiver')
    assert_equal('urn:example:a123%2Cz456?+rR?=qQ#fF', n.to_s)
    assert_equal('urn:example:a123%2Cz456', n.assigned_name)
  end

  def test_normalize_bang
    u = URI('URN:Example:a%2fb/c')
    u.normalize!
    assert_equal('urn:example:a%2Fb/c', u.to_s)
  end

  def test_equivalence_rfc8141_section_3_2
    base = URI('urn:example:a123,z456')
    [
      'URN:example:a123,z456',
      'urn:EXAMPLE:a123,z456',
      'urn:example:a123,z456?+abc',
      'urn:example:a123,z456?=xyz',
      'urn:example:a123,z456#789',
      'urn:example:a123,z456?+abc?=xyz#789',
    ].each do |s|
      assert_equal(true, base == URI(s), "#{s} equivalent")
      assert_equal(true, base.eql?(base), 'eql? self')
    end

    [
      'urn:example:a123,z456/foo',       # "/" is significant
      'urn:example:a123%2Cz456',         # pct not decoded
      'urn:example:A123,z456',           # NSS case sensitive
      'urn:example:a123,Z456',
    ].each do |s|
      assert_equal(false, base == URI(s), "#{s} not equivalent")
    end

    assert(URI('urn:example:a123%2Cz456') ==
           URI('URN:EXAMPLE:a123%2cz456'))
    assert_equal(false, URI('urn:example:a') == URI('urn:isbn:a'))
  end

  def test_eql_and_hash
    a = URI('urn:example:nss?+r?=q#f')
    b = URI('urn:example:nss?+r?=q#f')
    assert(a.eql?(b))
    assert_equal(a.hash, b.hash)
    assert_equal(1, {a => 1}[b])
    # eql? is raw-sensitive for the optional components
    assert_not_equal(true, a.eql?(URI('urn:example:nss#f')))
  end

  def test_equivalent_with_block
    a = URI('urn:example:AbC')
    b = URI('urn:example:aBc?+x#f')
    assert_equal(false, a == b)
    assert_equal(true,
                 a.equivalent?(b) { |x, y| x.nss.downcase == y.nss.downcase })
    assert_equal(false,
                 a.equivalent?(URI('urn:isbn:abc')) { true })
    assert_equal(true,
                 a.equivalent?('urn:example:aBc?=z') do |x, y|
                   x.nss.downcase == y.nss.downcase
                 end)
  end

  def test_registered_equivalence_resolver
    klass = Class.new(URI::URN)
    nid = "x#{object_id}"
    URI.register_scheme(nid, klass)
    klass.register_equivalence_resolver(nid) { |x, y| x.nss.tr('-', '') == y.nss.tr('-', '') }
    assert_equal(true, klass.build(nid: nid, nss: 'a-b').equivalent?(
      klass.build(nid: nid, nss: 'ab')
    ))
    assert_equal(false, klass.build(nid: nid, nss: 'a-b').equivalent?(
      klass.build(nid: nid, nss: 'ac')
    ))
    assert_raise(ArgumentError) { klass.register_equivalence_resolver(nid) }
    assert_raise(URI::InvalidComponentError) do
      klass.register_equivalence_resolver('x') { }
    end
  end

  def test_setters_atomic
    u = URI('urn:example:nss?+r?=q#f')
    before = u.to_s
    assert_raise(URI::InvalidComponentError) { u.nss = 'bad nss!' }
    assert_raise(URI::InvalidComponentError) { u.nid = 'x' }
    assert_raise(URI::InvalidComponentError) { u.r_component = '' }
    assert_raise(URI::InvalidComponentError) { u.q_component = 'a#b' }
    assert_raise(URI::InvalidComponentError) { u.fragment = 'a#b' }
    assert_equal(before, u.to_s, 'object unchanged after rejected setters')
  end

  def test_setters_update_and_round_trip
    u = URI('urn:example:nss?+r?=q#f')
    u.nss = 'new/x'
    u.r_component = nil
    assert_equal('urn:example:new/x?=q#f', u.to_s)
    u.q_component = 'new?q'
    u.fragment = nil
    assert_equal('urn:example:new/x?=new?q', u.to_s)
    u.nid = 'ISBN'
    assert_equal('urn:ISBN:new/x?=new?q', u.to_s)
  end

  def test_opaque_setter_atomic
    u = URI('urn:example:a?+r')
    before = u.to_s
    assert_raise(URI::InvalidComponentError) { u.opaque = 'no-colon' }
    assert_equal(before, u.to_s)
    u.opaque = 'isbn:0-395-36341-1?=q'
    assert_equal('isbn', u.nid)
    assert_equal('0-395-36341-1', u.nss)
    assert_nil(u.r_component)
    assert_equal('q', u.q_component)
    assert_equal('urn:isbn:0-395-36341-1?=q', u.to_s)
  end

  def test_rejected_setters
    u = URI('urn:example:a')
    assert_raise(URI::InvalidComponentError) { u.query = 'x=1' }
    assert_raise(URI::InvalidComponentError) { u.scheme = 'http' }
    assert_raise(URI::InvalidURIError) { u.path = '/x' }
  end

  def test_not_hierarchical
    u = URI('urn:example:a')
    assert_not_equal(true, u.hierarchical?)
    assert(u.absolute?)
    assert_raise(URI::BadURIError) { u.merge('urn:example:b') }
    assert_raise(URI::BadURIError) { u.merge!(URI('urn:example:b')) }
    assert_raise(URI::BadURIError) { u + URI('urn:example:b') }
    assert_raise(URI::BadURIError) { u.route_from(URI('urn:example:b')) }
    assert_raise(URI::BadURIError) { URI.join('urn:example:a', 'b') }
  end

  def test_wrong_scheme_class
    assert_raise(URI::InvalidURIError, URI::InvalidComponentError) do
      URI::URN.new('http', nil, nil, nil, nil, nil, 'example:a', nil, nil,
                   URI::RFC3986_PARSER, true)
    end
  end

  private

  def parse(s)
    URI(s)
  end

  def invalid(s)
    assert_raise(URI::InvalidURIError, URI::InvalidComponentError,
                 "expected #{s.inspect} to be invalid") do
      URI(s)
    end
  end

  def components_of(s)
    u = URI(s)
    [u.scheme, u.nid, u.nss, u.r_component, u.q_component, u.fragment]
  end
end
