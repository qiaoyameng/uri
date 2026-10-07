# frozen_string_literal: false
require 'test/unit'
require 'uri'

# Tests for the optional RFC 6874 compatibility mode.
#
# This library explicitly supports the RFC 6874 representation of IPv6
# zone identifiers in URIs, e.g. "http://[fe80::1%25eth0]/".  All tests
# here run entirely in memory: parsing and serialization are pure string
# operations that never query network interfaces and never perform DNS
# requests.
class URI::TestRFC6874 < Test::Unit::TestCase
  PARSER = URI::RFC3986_Parser.new(rfc6874: true)

  def parse(str)
    PARSER.parse(str)
  end

  def test_parser_mode
    assert_not_predicate URI::RFC3986_Parser.new, :rfc6874?
    assert_not_predicate URI::RFC3986_PARSER, :rfc6874?
    assert_predicate PARSER, :rfc6874?
  end

  def test_strict_rejection_without_mode
    assert_raise(URI::InvalidURIError) { URI.parse("http://[fe80::1%25eth0]/") }
    assert_raise(URI::InvalidURIError) { URI("http://[fe80::1%25eth0]/") }
    assert_raise(URI::InvalidURIError) { URI::RFC3986_Parser.new.parse("http://[fe80::1%25eth0]/") }

    uri = URI.parse("http://[::1]/")
    assert_raise(URI::InvalidComponentError) { uri.host = "[fe80::1%25eth0]" }
    assert_raise(URI::InvalidComponentError) { uri.hostname = "fe80::1%25eth0" }
  end

  def test_parse_distinguishes_components
    uri = parse("http://[fe80::1%25eth0]:8080/path")
    assert_equal "[fe80::1%25eth0]", uri.host       # serialized form, for URIs
    assert_equal "fe80::1", uri.hostname            # bare IPv6 address
    assert_equal "eth0", uri.zone_id                # decoded zone identifier
    assert_equal "fe80::1%eth0", uri.scoped_host    # scoped form, for sockets
    assert_equal 8080, uri.port
    assert_equal "http://[fe80::1%25eth0]:8080/path", uri.to_s
  end

  def test_zone_id_case_is_preserved
    assert_equal "Eth0", parse("http://[fe80::1%25Eth0]/").zone_id
    assert_equal "[fe80::1%25Eth0]", parse("http://[fe80::1%25Eth0]/").host
  end

  def test_zone_id_is_decoded_exactly_once
    assert_equal "Ath0", parse("http://[fe80::1%25%41th0]/").zone_id
    # "%2541" decodes to "%41", not recursively to "A"
    assert_equal "a%41", parse("http://[fe80::1%25a%2541]/").zone_id
  end

  def test_scoped_host_without_zone
    assert_equal "::1", URI.parse("http://[::1]/").scoped_host
    assert_equal "example.com", URI.parse("http://example.com/").scoped_host
    assert_nil URI.parse("http://example.com/").zone_id
  end

  def test_reg_name_percent_encoding_is_not_a_zone
    uri = parse("http://example.com%25eth0/")
    assert_equal "example.com%25eth0", uri.host
    assert_equal "example.com%25eth0", uri.hostname
    assert_nil uri.zone_id
    assert_equal "example.com%25eth0", uri.scoped_host
  end

  def test_empty_zone_is_rejected
    assert_raise(URI::InvalidURIError) { parse("http://[fe80::1%25]/") }
    assert_raise(URI::InvalidURIError) { parse("http://[%25]/") }
  end

  def test_invalid_escape_in_zone_is_rejected
    assert_raise(URI::InvalidURIError) { parse("http://[fe80::1%25eth%2]/") }
    assert_raise(URI::InvalidURIError) { parse("http://[fe80::1%25eth%zz]/") }
    assert_raise(URI::InvalidURIError) { parse("http://[fe80::1%25eth%]/") }
  end

  def test_zone_on_non_ipv6_host_is_rejected
    assert_raise(URI::InvalidURIError) { parse("http://[1.2.3.4%25eth0]/") }
    assert_raise(URI::InvalidURIError) { parse("http://[v1.2%25eth0]/") }
    assert_raise(URI::InvalidURIError) { parse("http://[example.com%25eth0]/") }
  end

  def test_build_with_separate_address_and_zone
    uri = URI::HTTP.build(scheme: "http", host: "fe80::1", zone_id: "eth0")
    assert_equal "[fe80::1%25eth0]", uri.host
    assert_equal "fe80::1", uri.hostname
    assert_equal "eth0", uri.zone_id
    assert_equal "fe80::1%eth0", uri.scoped_host
    assert_equal "http://[fe80::1%25eth0]", uri.to_s
  end

  def test_build_zone_cannot_escape_component
    uri = URI::HTTP.build(scheme: "http", host: "fe80::1", zone_id: "eth0]:8080%[")
    assert_equal "[fe80::1%25eth0%5D%3A8080%25%5B]", uri.host
    assert_equal "eth0]:8080%[", uri.zone_id
    assert_equal 80, uri.port
    assert_equal "http://[fe80::1%25eth0%5D%3A8080%25%5B]", uri.to_s
    # the serialized form round-trips back to the same zone identifier
    assert_equal "eth0]:8080%[", parse(uri.to_s).zone_id
  end

  def test_build_rejects_invalid_components
    assert_raise(URI::InvalidComponentError) { URI::HTTP.build(host: "example.com", zone_id: "eth0") }
    assert_raise(URI::InvalidComponentError) { URI::HTTP.build(host: "192.0.2.1", zone_id: "eth0") }
    assert_raise(URI::InvalidComponentError) { URI::HTTP.build(host: "not an address!", zone_id: "eth0") }
    assert_raise(URI::InvalidComponentError) { URI::HTTP.build(host: "fe80::1", zone_id: "") }
    assert_raise(URI::InvalidComponentError) { URI::HTTP.build(host: nil, zone_id: "eth0") }
    assert_raise(URI::InvalidComponentError) { URI::HTTP.build(host: "fe80::1", zone_id: nil) }
  end

  def test_normalize_preserves_zone_case
    uri = parse("HTTP://[FE80::1%25Eth0]/")
    assert_equal "http://[fe80::1%25Eth0]/", uri.normalize.to_s
  end

  def test_normalize_does_not_merge_different_zones
    eth0 = parse("http://[fe80::1%25eth0]/")
    assert_equal eth0, parse("http://[FE80::1%25eth0]/")
    assert_not_equal eth0, parse("http://[fe80::1%25eth1]/")
    assert_not_equal eth0, parse("http://[fe80::1%25Eth0]/")
    assert_not_equal eth0, parse("http://[fe80::1]/")
  end

  def test_roundtrip
    str = "http://[fe80::1%25eth0]/path?q=1"
    assert_equal str, parse(str).to_s
    assert_equal parse(str), parse(parse(str).to_s)
  end
end
