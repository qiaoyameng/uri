# frozen_string_literal: false
require 'test/unit'
require 'uri'

class URI::TestIRI < Test::Unit::TestCase
  IDNA = {
    "例子.测试" => "xn--fsqu00a.xn--0zwm56d",
    "例え.jp"   => "xn--r8jz45g.jp",
    "bücher.de" => "xn--bcher-kva.de",
    "ex.com"    => "ex.com",
  }
  IDNA_ENCODER = ->(domain) do
    raise "unexpected host: #{domain.inspect}" unless IDNA.key?(domain)
    IDNA.fetch(domain)
  end

  def enc(iri, encoder = IDNA_ENCODER)
    URI::IRI.encode(iri, idna: encoder)
  end

  def test_encode_basic
    encoded = enc("https://例子.测试/路/径?key=值#片")
    assert_equal(
      "https://xn--fsqu00a.xn--0zwm56d/%E8%B7%AF/%E5%BE%84?key=%E5%80%BC#%E7%89%87",
      encoded)
    assert_predicate(encoded, :ascii_only?)
    assert_nothing_raised { URI.parse(encoded) }
  end

  def test_encode_userinfo
    assert_equal(
      "http://%E7%94%A8%E6%88%B7:pw@ex.com/",
      enc("http://用户:pw@ex.com/"))
  end

  def test_encoder_receives_only_host
    seen = nil
    encoder = ->(host) { seen = host; "ex.com" }
    URI::IRI.encode("http://例子.测试:9000/a?b#c", idna: encoder)
    assert_equal("例子.测试", seen)
  end

  def test_encoder_block_form
    encoded = URI::IRI.encode("http://例子.测试/") { |host| IDNA.fetch(host) }
    assert_equal("http://xn--fsqu00a.xn--0zwm56d/", encoded)
  end

  def test_ascii_host_skips_encoder
    called = false
    encoder = ->(host) { called = true; "ex.com" }
    URI::IRI.encode("http://ex.com/a", idna: encoder)
    assert_not_predicate(called, :itself)
  end

  def test_ip_literal_host_is_not_idna_encoded
    assert_equal("http://[2001:db8::1]/a", enc("http://[2001:db8::1]/a"))
    assert_equal("http://[::1]:8080/%E8%B7%AF", enc("http://[::1]:8080/路"))
  end

  def test_existing_percent_triplets_preserved
    encoded = enc("http://ex.com/%c3%a9/%2f?x=%2F%2f#%41")
    assert_equal("http://ex.com/%c3%a9/%2f?x=%2F%2f#%41", encoded)
  end

  def test_existing_triplets_not_double_encoded
    encoded = enc("http://ex.com/%E8%B7%AF")
    assert_equal("http://ex.com/%E8%B7%AF", encoded)
    assert_not_include(encoded, "%25")
  end

  def test_path_is_not_unicode_normalized
    nfc = enc("http://ex.com/\u00e9")
    nfd = enc("http://ex.com/e\u0301")
    assert_equal("http://ex.com/%C3%A9", nfc)
    assert_equal("http://ex.com/e%CC%81", nfd)
    assert_not_equal(nfc, nfd)
  end

  def test_stray_percent_rejected
    assert_raise(URI::InvalidURIError) do
      enc("http://ex.com/100%")
    end
    assert_raise(URI::InvalidURIError) do
      enc("http://ex.com/a%zz")
    end
    assert_raise(URI::InvalidURIError) do
      enc("http://ex.com/a%2")
    end
  end

  def test_bad_utf8_rejected
    assert_raise(URI::InvalidURIError) do
      URI::IRI.encode("http://ex.com/a".b + "\xff".b)
    end
  end

  def test_non_ascii_host_without_encoder_rejected
    assert_raise(URI::InvalidURIError) do
      URI::IRI.encode("http://例子.测试/")
    end
  end

  def test_encoder_returning_slash_rejected
    assert_raise(URI::InvalidURIError) do
      URI::IRI.encode("http://例子.测试/", idna: ->(_h) { "ex.com/" })
    end
  end

  def test_encoder_returning_port_rejected
    assert_raise(URI::InvalidURIError) do
      URI::IRI.encode("http://例子.测试/", idna: ->(_h) { "ex.com:80" })
    end
  end

  def test_encoder_returning_non_ascii_rejected
    assert_raise(URI::InvalidURIError) do
      URI::IRI.encode("http://例子.测试/", idna: ->(_h) { "ex\u00e9.com" })
    end
  end

  def test_encoder_returning_non_string_rejected
    assert_raise(URI::InvalidURIError) do
      URI::IRI.encode("http://例子.测试/", idna: ->(_h) { 123 })
    end
  end

  def test_encoder_raising_is_wrapped
    assert_raise(URI::InvalidURIError) do
      URI::IRI.encode("http://例子.测试/", idna: ->(_h) { raise "boom" })
    end
  end

  def test_non_callable_encoder_rejected
    assert_raise(URI::InvalidURIError) do
      URI::IRI.encode("http://例子.测试/", idna: 12)
    end
  end

  def test_non_ascii_scheme_rejected
    assert_raise(URI::InvalidURIError) { URI::IRI.encode("合://x/") }
  end

  def test_relative_and_fragment_only
    assert_equal("a/b/%E8%B7%AF", URI::IRI.encode("a/b/路"))
    assert_equal("#%E7%89%87", URI::IRI.encode("#片"))
  end

  def test_opaque
    assert_equal("urn:%C3%A9?x#f", URI::IRI.encode("urn:\u00e9?x#f"))
  end

  def test_query_reserved_delimiters_kept
    assert_equal(
      "http://ex.com/a?b=c/d&e=f",
      URI::IRI.encode("http://ex.com/a?b=c/d&e=f"))
  end

  def test_space_encoded_in_path_and_query
    assert_equal(
      "http://ex.com/a%20b?c=d%20e",
      URI::IRI.encode("http://ex.com/a b?c=d e"))
  end

  def test_parse_entry
    uri = URI::IRI.parse("https://例子.测试/路", idna: IDNA_ENCODER)
    assert_instance_of(URI::HTTPS, uri)
    assert_equal("xn--fsqu00a.xn--0zwm56d", uri.host)
    assert_equal("/%E8%B7%AF", uri.path)
  end

  def test_strict_parse_still_rejects_non_ascii
    assert_raise(URI::InvalidURIError) { URI.parse("http://例子.测试/") }
  end

  def test_decode_unreserved_and_unicode
    assert_equal("http://ex.com/a/A", URI::IRI.decode("http://ex.com/a/%41"))
    assert_equal(
      "http://ex.com/路",
      URI::IRI.decode("http://ex.com/%E8%B7%AF"))
  end

  def test_decode_keeps_encoded_slash_boundary
    assert_equal("http://ex.com/a%2Fb/路",
                 URI::IRI.decode("http://ex.com/a%2Fb/%E8%B7%AF"))
  end

  def test_decode_keeps_all_reserved
    # Reserved characters stay encoded; only unreserved characters decode.
    assert_equal("%2F%2f%3F%23A", URI::IRI.decode("%2F%2f%3F%23%41"))
    assert_equal("%26%3D%3A%40", URI::IRI.decode("%26%3D%3A%40"))
  end

  def test_decode_adjacent_reserved_runs
    assert_equal("x=%2F%2F", URI::IRI.decode("x=%2F%2F"))
    assert_equal("%2F%2fA", URI::IRI.decode("%2F%2f%41"))
    assert_equal("路%2F", URI::IRI.decode("%E8%B7%AF%2F"))
  end

  def test_decode_invalid_utf8_kept_percent_encoded
    assert_equal("%FF%FE/路", URI::IRI.decode("%FF%FE/%E8%B7%AF"))
  end

  def test_decode_control_and_space_kept_encoded
    assert_equal("%00%09/路", URI::IRI.decode("%00%09/%E8%B7%AF"))
    assert_equal("%20%7FA", URI::IRI.decode("%20%7F%41"))
  end

  def test_decode_accepts_uri_object
    uri = URI.parse("http://ex.com/%E8%B7%AF")
    assert_equal("http://ex.com/路", URI::IRI.decode(uri))
  end

  def test_roundtrip_display
    iri = "https://例子.测试/路?a=值#片"
    ascii_uri = enc(iri)
    decoded = URI::IRI.decode(ascii_uri)
    assert_include(decoded, "/路")
    assert_include(decoded, "a=值")
    assert_include(decoded, "#片")
    # host stays punycode on the safe display path
    assert_include(decoded, "xn--fsqu00a.xn--0zwm56d")
  end

  def test_decode_does_not_change_component_boundaries
    decoded = URI::IRI.decode("http://ex.com/a%3Fb%23c%2Fd?x=%26%3D#f%2F")
    assert_equal("http://ex.com/a%3Fb%23c%2Fd?x=%26%3D#f%2F", decoded)
  end
end
