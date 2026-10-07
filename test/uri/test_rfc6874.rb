# frozen_string_literal: false
#
# Tests for the explicitly supported representation of scoped IPv6
# addresses defined by RFC 6874 (https://www.rfc-editor.org/rfc/rfc6874):
# URIs such as "http://[fe80::1%25eth0]/".
#
# Every test in this file runs purely in memory: parsing neither queries
# network interfaces nor performs any DNS resolution.
require 'test/unit'
require 'uri'

class URI::TestRFC6874 < Test::Unit::TestCase
  def parser
    URI::RFC6874_PARSER
  end

  def test_exposed_constant
    assert_equal true, URI::RFC6874_PARSER.rfc6874?
    assert_equal false, URI::DEFAULT_PARSER.rfc6874?
  end

  def test_parse_separates_components
    uri = parser.parse("http://[fe80::1%25eth0]/")

    # Host used for URI serialization (brackets, encoded delimiter).
    assert_equal "[fe80::1%25eth0]", uri.host
    # Bracket-less IPv6 address, without any zone.
    assert_equal "fe80::1", uri.hostname
    # Already-decoded zone identifier, kept as its own component.
    assert_equal "eth0", uri.zone
    # Socket-oriented form with a literal percent sign.
    assert_equal "fe80::1%eth0", uri.scoped_hostname
    assert_equal "http://[fe80::1%25eth0]/", uri.to_s
  end

  def test_parse_keyword_option
    uri = URI.parse("http://[fe80::1%25eth0]/", parser: parser)
    assert_equal "eth0", uri.zone
    assert_equal "[fe80::1%25eth0]", uri.host
  end

  def test_custom_parser_instance
    custom = URI::RFC3986_Parser.new(rfc6874: true)
    assert_equal true, custom.rfc6874?
    uri = custom.parse("http://[fe80::1%25eth0]/")
    assert_equal "eth0", uri.zone
  end

  def test_strict_parser_rejects_zone_by_default
    assert_raise(URI::InvalidURIError) do
      URI.parse("http://[fe80::1%25eth0]/")
    end
    assert_raise(URI::InvalidURIError) do
      URI::RFC3986_Parser.new.parse("http://[fe80::1%25eth0]/")
    end
  end

  def test_strict_parser_rejects_serialized_zone_on_setters
    uri = URI.parse("http://[::1]/")
    assert_raise(URI::InvalidComponentError) do
      uri.host = "[fe80::1%25eth0]"
    end
    assert_raise(URI::InvalidComponentError) do
      uri.hostname = "fe80::1%25eth0"
    end
    assert_nil uri.zone
  end

  def test_strict_parser_rejects_serialized_zone_on_construction
    assert_raise(URI::InvalidComponentError) do
      URI::HTTP.new("http", nil, "[fe80::1%25eth0]", nil, nil,
                    "/", nil, nil, nil, URI::DEFAULT_PARSER, true)
    end
    assert_raise(URI::InvalidComponentError) do
      URI::HTTP.new("http", nil, "[fe80::1%25eth0]", nil, nil,
                    "/", nil, nil, nil, URI::DEFAULT_PARSER, false)
    end
  end

  def test_constructor_accepts_separated_address_and_zone
    uri = URI::HTTP.build(host: "[fe80::1]", zone: "eth0")
    assert_equal "[fe80::1]", uri.instance_variable_get(:@host)
    assert_equal "[fe80::1%25eth0]", uri.host
    assert_equal "fe80::1", uri.hostname
    assert_equal "eth0", uri.zone
    assert_equal "fe80::1%eth0", uri.scoped_hostname
    assert_equal "http://[fe80::1%25eth0]", uri.to_s
  end

  def test_constructor_separated_zone_works_in_strict_mode
    # A separated address/zone is structural input, not a serialized URI,
    # so it is accepted even with the strict (RFC 6874 disabled) parser.
    uri = URI::HTTP.build(host: "[fe80::1]", zone: "eth0")
    assert_equal "eth0", uri.zone
    assert_equal "http://[fe80::1%25eth0]", uri.to_s
  end

  def test_zone_keyword_on_new
    uri = URI::Generic.new("http", nil, "[fe80::1]", nil, nil,
                           "/", nil, nil, nil, parser, true, zone: "eth0")
    assert_equal "eth0", uri.zone
    assert_equal "fe80::1", uri.hostname
  end

  def test_zone_is_percent_decoded_exactly_once
    uri = parser.parse("http://[fe80::1%25%65th0]/")
    assert_equal "eth0", uri.zone
    assert_equal "http://[fe80::1%25eth0]/", uri.to_s
  end

  def test_encoded_percent_sign_in_zone
    # "%2525" inside the zone decodes once to a literal "%".
    uri = parser.parse("http://[fe80::1%25a%2525b]/")
    assert_equal "a%25b", uri.zone
    assert_equal "http://[fe80::1%25a%2525b]/", uri.to_s
  end

  def test_zone_interface_name_case_is_preserved
    uri = parser.parse("http://[fe80::1%25ETH0]/")
    assert_equal "ETH0", uri.zone
    assert_equal "[fe80::1%25ETH0]", uri.host
  end

  def test_empty_zone_is_rejected
    assert_raise(URI::InvalidURIError) do
      parser.parse("http://[fe80::1%25]/")
    end
    assert_raise(URI::InvalidComponentError) do
      URI::HTTP.build(host: "[fe80::1]", zone: "")
    end
  end

  def test_malformed_escape_in_zone_is_rejected
    assert_raise(URI::InvalidURIError) do
      parser.parse("http://[fe80::1%25et%2]/")
    end
    assert_raise(URI::InvalidURIError) do
      parser.parse("http://[fe80::1%25%2]/")
    end
  end

  def test_zone_on_non_ipv6_host_is_rejected
    assert_raise(URI::InvalidURIError) do
      parser.parse("http://example.com%25eth0/")
    end
    assert_raise(URI::InvalidURIError) do
      parser.parse("http://1.2.3.4%25eth0/")
    end
    assert_raise(URI::InvalidURIError) do
      parser.parse("http://[v1.fe80::1%25eth0]/")
    end
    assert_raise(URI::InvalidComponentError) do
      URI::HTTP.build(host: "example.com", zone: "eth0")
    end
    assert_raise(URI::InvalidComponentError) do
      URI::HTTP.build(host: "1.2.3.4", zone: "eth0")
    end
    assert_raise(URI::InvalidComponentError) do
      URI::HTTP.build(zone: "eth0", path: "/")
    end
    assert_raise(URI::InvalidComponentError) do
      URI::Generic.new("http", nil, "example.com", nil, nil, "/",
                       nil, nil, nil, URI::DEFAULT_PARSER, false, zone: "eth0")
    end
    assert_raise(URI::InvalidComponentError) do
      URI::Generic.new("http", nil, nil, nil, nil, "/",
                       nil, nil, nil, URI::DEFAULT_PARSER, false, zone: "eth0")
    end
  end

  def test_regular_percent_encoded_reg_name_still_works
    uri = parser.parse("http://ex%41mple.com/")
    assert_equal "ex%41mple.com", uri.host
    assert_nil uri.zone
  end

  def test_zone_structural_characters_cannot_break_out
    uri = URI::HTTP.build(host: "[fe80::1]", zone: "eth0]:80%")
    serialized = uri.to_s
    assert_equal "http://[fe80::1%25eth0%5D%3A80%25]", serialized
    reparsed = parser.parse(serialized + "/")
    assert_equal "eth0]:80%", reparsed.zone
    assert_equal 80, reparsed.port
  end

  def test_zone_setter_requires_ipv6_host
    uri = URI::HTTP.build(host: "example.com")
    assert_raise(URI::InvalidComponentError) { uri.zone = "eth0" }
  end

  def test_zone_setter_and_removal
    uri = URI.parse("http://[fe80::1]/")
    uri.zone = "eth0"
    assert_equal "http://[fe80::1%25eth0]/", uri.to_s
    assert_equal "fe80::1%eth0", uri.scoped_hostname

    uri.zone = nil
    assert_nil uri.zone
    assert_equal "http://[fe80::1]/", uri.to_s
    assert_equal "fe80::1", uri.scoped_hostname
  end

  def test_assigning_host_clears_zone
    uri = parser.parse("http://[fe80::1%25eth0]/")
    uri.host = "[::1]"
    assert_nil uri.zone
    assert_equal "[::1]", uri.host

    uri.zone = "en1"
    uri.hostname = "::2"
    assert_nil uri.zone
    assert_equal "[::2]", uri.host
  end

  def test_port_and_path_coexist_with_zone
    uri = parser.parse("http://[fe80::1%25eth0]:8080/path?query")
    assert_equal 8080, uri.port
    assert_equal "/path", uri.path
    assert_equal "query", uri.query
    assert_equal "eth0", uri.zone
    assert_equal "/path?query", uri.request_uri
  end

  def test_normalize_does_not_merge_different_zones
    eth0 = parser.parse("http://[fe80::1%25eth0]/").normalize
    en1  = parser.parse("http://[fe80::1%25en1]/").normalize
    assert_not_equal eth0, en1
    assert_equal "eth0", eth0.zone
    assert_equal "en1", en1.zone
  end

  def test_normalize_downcases_address_but_not_zone
    uri = parser.parse("http://[FE80::1%25eTh0]/").normalize
    assert_equal "[fe80::1%25eTh0]", uri.host
    assert_equal "eTh0", uri.zone
  end

  def test_normalize_same_address_and_zone_compare_equal
    a = parser.parse("http://[FE80::1%25eth0]/")
    b = parser.parse("http://[fe80::1%25eth0]/")
    assert_equal a.normalize, b.normalize
  end

  def test_route_resolution_respects_zone
    uri = parser.parse("http://[fe80::1%25eth0]/")
    assert_equal "./", uri.route_from("http://[fe80::1%25eth0]/x").to_s
    cross = uri.route_from("http://[fe80::1%25en1]/x")
    assert_equal "//[fe80::1%25eth0]/", cross.to_s
  end

  def test_merge_preserves_zone
    base = parser.parse("http://[fe80::1%25eth0]/a/b")
    assert_equal "http://[fe80::1%25eth0]/a/c", base.merge("c").to_s
    merged = base.merge("//[fe80::1%25en1]/z")
    assert_equal "en1", merged.zone
    assert_equal "http://[fe80::1%25en1]/z", merged.to_s
  end

  def test_relative_reference_with_zone
    uri = parser.parse("//[fe80::1%25eth0]/p")
    assert_nil uri.scheme
    assert_equal "eth0", uri.zone
    assert_equal "[fe80::1%25eth0]", uri.host
  end

  def test_scoped_hostname_without_zone
    assert_equal "::1", URI.parse("http://[::1]/").scoped_hostname
    assert_equal "example.com", URI.parse("http://example.com/").scoped_hostname
    assert_nil URI::Generic.build(scheme: "http", path: "/").scoped_hostname
  end

  def test_ftp_with_zone
    uri = URI::FTP.build(host: "[fe80::1]", zone: "eth0", path: "pub")
    assert_equal "eth0", uri.zone
    assert_equal "fe80::1%eth0", uri.scoped_hostname
    assert_equal "ftp://[fe80::1%25eth0]/pub", uri.to_s
  end

  def test_file_with_zone
    uri = URI::File.build(host: "[fe80::1]", zone: "eth0", path: "/x")
    assert_equal "eth0", uri.zone
    assert_equal "file://[fe80::1%25eth0]/x", uri.to_s
  end

  def test_serialized_zone_remains_valid_host_grammar
    uri = URI::HTTP.build(host: "[fe80::1]", zone: "a]b:c%")
    assert_match(parser.regexp[:HOST], uri.host)
  end

  def test_parsing_does_not_touch_interfaces_or_dns
    # Parsing must stay entirely in memory: no interface enumeration and
    # no name resolution is performed.
    called = []
    originals = {}
    stubs = {
      [IPSocket, :getaddress]  => ->(*) { called << :getaddress; raise SocketError },
      [Addrinfo, :getaddrinfo] => ->(*) { called << :getaddrinfo; raise SocketError },
      [Socket, :getifaddrs]    => ->(*) { called << :getifaddrs; [] },
    }
    verbose = $VERBOSE
    $VERBOSE = nil
    begin
      stubs.each do |(mod, name), block|
        originals[[mod, name]] = mod.singleton_class.instance_method(name)
        mod.singleton_class.send(:define_method, name, block)
      end
    ensure
      $VERBOSE = verbose
    end

    uri = assert_nothing_raised do
      parser.parse("http://[fe80::1%25eth0]:8080/")
    end
    assert_equal "eth0", uri.zone
    assert_equal "fe80::1%eth0", uri.scoped_hostname
    assert_empty called
  ensure
    if defined?(originals)
      verbose = $VERBOSE
      $VERBOSE = nil
      begin
        originals.each do |(mod, name), unbound|
          mod.singleton_class.send(:define_method, name, unbound)
        end
      ensure
        $VERBOSE = verbose
      end
    end
  end
end
