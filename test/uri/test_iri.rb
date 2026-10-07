# frozen_string_literal: false
require 'test/unit'
require 'uri'

class URI::TestIRI < Test::Unit::TestCase
  IDNA = ->(host) {
    {
      "bücher.de" => "xn--bcher-kva.de",
      "例え.jp" => "xn--r8jz45g.jp",
    }.fetch(host)
  }

  def test_iri_to_uri_ascii_passthrough
    uri = "http://user:pass@example.com:8080/path?q=1#frag"
    assert_equal uri, URI.iri_to_uri(uri)
  end

  def test_iri_to_uri_unicode_host_via_encoder
    assert_equal "https://xn--bcher-kva.de/",
                 URI.iri_to_uri("https://bücher.de/", idna_encoder: IDNA)
  end

  def test_iri_to_uri_encoder_receives_host_only
    received = []
    encoder = ->(host) { received << host; "xn--r8jz45g.jp" }
    uri = URI.iri_to_uri("http://user@例え.jp:8080/パス?クエリ=1#フラグ",
                         idna_encoder: encoder)
    assert_equal ["例え.jp"], received
    assert_equal "http://user@xn--r8jz45g.jp:8080/" \
                 "%E3%83%91%E3%82%B9?%E3%82%AF%E3%82%A8%E3%83%AA=1#%E3%83%95%E3%83%A9%E3%82%B0",
                 uri
  end

  def test_iri_to_uri_encoder_not_called_for_ascii_host
    encoder = ->(host) { flunk "encoder must not be called for ASCII host" }
    assert_equal "http://example.com/", URI.iri_to_uri("http://example.com/", idna_encoder: encoder)
    assert_equal "http://xn--bcher-kva.de/",
                 URI.iri_to_uri("http://xn--bcher-kva.de/", idna_encoder: encoder)
  end

  def test_iri_to_uri_unicode_host_without_encoder
    assert_raise(URI::InvalidURIError) { URI.iri_to_uri("https://bücher.de/") }
  end

  def test_iri_to_uri_rejects_bad_encoder_results
    assert_raise(URI::InvalidURIError) {
      URI.iri_to_uri("https://bücher.de/", idna_encoder: ->(host) { "evil.com:8080" })
    }
    assert_raise(URI::InvalidURIError) {
      URI.iri_to_uri("https://bücher.de/", idna_encoder: ->(host) { "evil.com/path" })
    }
    assert_raise(URI::InvalidURIError) {
      URI.iri_to_uri("https://bücher.de/", idna_encoder: ->(host) { "bücher.de" })
    }
    assert_raise(URI::InvalidURIError) {
      URI.iri_to_uri("https://bücher.de/", idna_encoder: ->(host) { "" })
    }
    assert_raise(URI::InvalidURIError) {
      URI.iri_to_uri("https://bücher.de/", idna_encoder: ->(host) { nil })
    }
  end

  def test_iri_to_uri_path_query_fragment
    assert_equal "http://example.com/%E4%B8%AD%E6%96%87?q=%C3%A9#%E2%82%AC",
                 URI.iri_to_uri("http://example.com/中文?q=é#€")
  end

  def test_iri_to_uri_userinfo
    assert_equal "http://%E7%94%A8%E6%88%B7:%E5%AF%86%E7%A0%81@example.com/",
                 URI.iri_to_uri("http://用户:密码@example.com/")
  end

  def test_iri_to_uri_component_specific_escaping
    # "@" is allowed in paths, "?" is allowed in queries, but both are
    # encoded where they are not allowed.
    assert_equal "http://example.com/a@b/c:d", URI.iri_to_uri("http://example.com/a@b/c:d")
    assert_equal "http://example.com/?a/b?c", URI.iri_to_uri("http://example.com/?a/b?c")
    assert_equal "http://example.com/a%5Bb", URI.iri_to_uri("http://example.com/a[b")
    assert_equal "http://example.com/%20%22%3C%3E%5E%60%7B%7C%7D",
                 URI.iri_to_uri("http://example.com/ \"<>^`{|}")
  end

  def test_iri_to_uri_preserves_valid_triplets
    assert_equal "http://example.com/%E4%B8%AD%2f%2F",
                 URI.iri_to_uri("http://example.com/%E4%B8%AD%2f%2F")
    assert_equal "http://example.com/?q=%2F%25",
                 URI.iri_to_uri("http://example.com/?q=%2F%25")
  end

  def test_iri_to_uri_rejects_stray_percent
    assert_raise(URI::InvalidURIError) { URI.iri_to_uri("http://example.com/100%") }
    assert_raise(URI::InvalidURIError) { URI.iri_to_uri("http://example.com/%2") }
    assert_raise(URI::InvalidURIError) { URI.iri_to_uri("http://example.com/%zz") }
    assert_raise(URI::InvalidURIError) { URI.iri_to_uri("http://example.com/?q=%") }
    assert_raise(URI::InvalidURIError) { URI.iri_to_uri("http://example.com/#%x") }
    assert_raise(URI::InvalidURIError) { URI.iri_to_uri("http://exa%mple.com/") }
  end

  def test_iri_to_uri_rejects_invalid_utf8
    assert_raise(URI::InvalidURIError) { URI.iri_to_uri("http://example.com/\xE4\xB8".dup.force_encoding(Encoding::UTF_8)) }
    assert_raise(URI::InvalidURIError) { URI.iri_to_uri("http://example.com/\xFF\xFE".b) }
  end

  def test_iri_to_uri_accepts_binary_string_with_valid_utf8
    assert_equal "http://example.com/%E4%B8%AD",
                 URI.iri_to_uri("http://example.com/\xE4\xB8\xAD".b)
  end

  def test_iri_to_uri_no_normalization
    nfc = URI.iri_to_uri("http://example.com/é")       # U+00E9
    nfd = URI.iri_to_uri("http://example.com/é")      # U+0065 U+0301
    assert_equal "http://example.com/%C3%A9", nfc
    assert_equal "http://example.com/e%CC%81", nfd
    assert_not_equal nfc, nfd
  end

  def test_iri_to_uri_ip_literal_and_port
    assert_equal "http://[::1]:8080/%E4%B8%AD", URI.iri_to_uri("http://[::1]:8080/中")
    assert_equal "http://example.com:8080/", URI.iri_to_uri("http://example.com:8080/")
  end

  def test_iri_to_uri_rejects_invalid_input
    assert_raise(URI::InvalidURIError) { URI.iri_to_uri("not an iri") }
    assert_raise(URI::InvalidURIError) { URI.iri_to_uri("/relative/path") }
    assert_raise(URI::InvalidURIError) { URI.iri_to_uri("http://exa mple.com/") }
    assert_raise(URI::InvalidURIError) { URI.iri_to_uri("http://example.com:port/") }
    assert_raise(URI::InvalidURIError) { URI.iri_to_uri("http://[::1/") }
    assert_raise(URI::InvalidURIError) { URI.iri_to_uri(nil) }
  end

  def test_iri_to_uri_result_is_parseable_ascii
    uri = URI.iri_to_uri("https://用户@bücher.de:443/中文 路径?q=é#€", idna_encoder: IDNA)
    assert uri.ascii_only?
    parsed = URI.parse(uri)
    assert_equal "https", parsed.scheme
    assert_equal "xn--bcher-kva.de", parsed.host
    assert_equal 443, parsed.port
    assert_equal "%E7%94%A8%E6%88%B7", parsed.userinfo
    assert_equal "/%E4%B8%AD%E6%96%87%20%E8%B7%AF%E5%BE%84", parsed.path
    assert_equal "q=%C3%A9", parsed.query
    assert_equal "%E2%82%AC", parsed.fragment
  end

  def test_uri_parse_stays_strict
    assert_raise(URI::InvalidURIError) { URI.parse("https://bücher.de/") }
    assert_raise(URI::InvalidURIError) { URI.parse("http://example.com/中文") }
  end

  def test_uri_to_display_decodes_displayable
    assert_equal "https://example.com/搜索?q=中#€",
                 URI.uri_to_display("https://example.com/%E6%90%9C%E7%B4%A2?q=%E4%B8%AD#%E2%82%AC")
  end

  def test_uri_to_display_keeps_reserved_encoded
    assert_equal "http://example.com/a%2Fb", URI.uri_to_display("http://example.com/a%2Fb")
    assert_equal "http://example.com/?q=%3F%23%25%2F",
                 URI.uri_to_display("http://example.com/?q=%3F%23%25%2F")
    assert_equal "http://example.com/%3A%40%5B%5D",
                 URI.uri_to_display("http://example.com/%3A%40%5B%5D")
  end

  def test_uri_to_display_decodes_unreserved_ascii
    assert_equal "http://example.com/Az09-._~",
                 URI.uri_to_display("http://example.com/%41%7A%30%39%2D%2E%5F%7E")
  end

  def test_uri_to_display_keeps_invalid_utf8_encoded
    assert_equal "http://example.com/%FF%FE", URI.uri_to_display("http://example.com/%FF%FE")
    assert_equal "http://example.com/%E4%B8", URI.uri_to_display("http://example.com/%E4%B8")
  end

  def test_uri_to_display_keeps_controls_and_format_chars_encoded
    assert_equal "http://example.com/%00%7F", URI.uri_to_display("http://example.com/%00%7F")
    # U+202E RIGHT-TO-LEFT OVERRIDE must never be revealed
    assert_equal "http://example.com/%E2%80%AE", URI.uri_to_display("http://example.com/%E2%80%AE")
  end

  def test_uri_to_display_round_trip
    iri = "https://用户@bücher.de/中文 路径?q=é#€"
    uri = URI.iri_to_uri(iri, idna_encoder: IDNA)
    assert_equal "https://用户@xn--bcher-kva.de/中文%20路径?q=é#€",
                 URI.uri_to_display(uri)
  end

  def test_uri_to_display_decodes_displayable_parts_of_mixed_runs
    assert_equal "http://example.com/中%20文",
                 URI.uri_to_display("http://example.com/%E4%B8%AD%20%E6%96%87")
  end

  def test_uri_to_display_accepts_uri_objects
    uri = URI.parse("http://example.com/%E4%B8%AD")
    assert_equal "http://example.com/中", URI.uri_to_display(uri)
  end

  def test_uri_to_display_rejects_invalid_input
    assert_raise(URI::InvalidURIError) { URI.uri_to_display("http://exa mple.com/") }
    assert_raise(URI::InvalidURIError) { URI.uri_to_display("http://example.com/中") }
    assert_raise(URI::InvalidURIError) { URI.uri_to_display("http://example.com/%zz") }
  end

  def test_uri_to_display_does_not_change_component_boundaries
    display = URI.uri_to_display("http://example.com/a%3Fb%23c%2Fd?q=%26%3D")
    reparsed = URI.parse(display)
    assert_equal "/a%3Fb%23c%2Fd", reparsed.path
    assert_equal "q=%26%3D", reparsed.query
  end
end
