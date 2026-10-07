# frozen_string_literal: false
require 'test/unit'
require 'uri'

class URI::TestTemplate < Test::Unit::TestCase
  # The canonical variable set from RFC 6570 section 3.2, used by every
  # example in Appendix A.
  VARIABLES = {
    "count" => ["one", "two", "three"],
    "dom" => ["example", "com"],
    "dub" => "me/too",
    "hello" => "Hello World!",
    "half" => "50%",
    "var" => "value",
    "who" => "fred",
    "base" => "http://example.com/home/",
    "path" => "/foo/bar",
    "list" => ["red", "green", "blue"],
    "keys" => {"semi" => ";", "dot" => ".", "comma" => ","},
    "v" => "6",
    "x" => "1024",
    "y" => "768",
    "empty" => "",
    "empty_keys" => {},
    "empty_list" => [],
  }.freeze

  # Every template/expansion pair below is taken verbatim from the
  # Level 4 examples of RFC 6570 (sections 3.2.2 through 3.2.9).
  RFC_EXAMPLES = [
    ["{count}", "one,two,three"],
    ["{count*}", "one,two,three"],
    ["{/count}", "/one,two,three"],
    ["{/count*}", "/one/two/three"],
    ["{;count}", ";count=one,two,three"],
    ["{;count*}", ";count=one;count=two;count=three"],
    ["{?count}", "?count=one,two,three"],
    ["{?count*}", "?count=one&count=two&count=three"],
    ["{&count}", "&count=one,two,three"],
    ["{&count*}", "&count=one&count=two&count=three"],
    ["{dom}", "example,com"],
    ["{dom*}", "example,com"],
    ["{.dom}", ".example,com"],
    ["{.dom*}", ".example.com"],
    ["{dub}", "me%2Ftoo"],
    ["{+dub}", "me/too"],
    ["{#dub}", "#me/too"],
    ["{hello}", "Hello%20World%21"],
    ["{+hello}", "Hello%20World!"],
    ["{#hello}", "#Hello%20World!"],
    ["{half}", "50%25"],
    ["{+half}", "50%25"],
    ["{#half}", "#50%25"],
    ["{var}", "value"],
    ["{var:3}", "val"],
    ["{+path:6}", "/foo/b"],
    ["{/var*}", "/value"],
    ["{;hello}", ";hello=Hello%20World%21"],
    ["{who}", "fred"],
    ["{base}", "http%3A%2F%2Fexample.com%2Fhome%2F"],
    ["{+base}", "http://example.com/home/"],
    ["{#base}", "#http://example.com/home/"],
    ["{path}", "%2Ffoo%2Fbar"],
    ["{+path}", "/foo/bar"],
    ["{#path}", "#/foo/bar"],
    ["{list}", "red,green,blue"],
    ["{list*}", "red,green,blue"],
    ["{+list}", "red,green,blue"],
    ["{+list*}", "red,green,blue"],
    ["{#list}", "#red,green,blue"],
    ["{#list*}", "#red,green,blue"],
    ["{.list}", ".red,green,blue"],
    ["{.list*}", ".red.green.blue"],
    ["{/list}", "/red,green,blue"],
    ["{/list*}", "/red/green/blue"],
    ["{;list}", ";list=red,green,blue"],
    ["{;list*}", ";list=red;list=green;list=blue"],
    ["{?list}", "?list=red,green,blue"],
    ["{?list*}", "?list=red&list=green&list=blue"],
    ["{&list}", "&list=red,green,blue"],
    ["{&list*}", "&list=red&list=green&list=blue"],
    ["{keys}", "semi,%3B,dot,.,comma,%2C"],
    ["{keys*}", "semi=%3B,dot=.,comma=%2C"],
    ["{+keys}", "semi,%3B,dot,.,comma,%2C"],
    ["{+keys*}", "semi=;,dot=.,comma=,"],
    ["{#keys}", "#semi,%3B,dot,.,comma,%2C"],
    ["{#keys*}", "#semi=;,dot=.,comma=,"],
    ["{.keys}", ".semi,%3B,dot,.,comma,%2C"],
    ["{.keys*}", ".semi=%3B.dot=..comma=%2C"],
    ["{/keys}", "/semi,%3B,dot,.,comma,%2C"],
    ["{/keys*}", "/semi=%3B/dot=./comma=%2C"],
    ["{;keys}", ";keys=semi,%3B,dot,.,comma,%2C"],
    ["{;keys*}", ";semi=%3B;dot=.;comma=%2C"],
    ["{?keys}", "?keys=semi,%3B,dot,.,comma,%2C"],
    ["{?keys*}", "?semi=%3B&dot=.&comma=%2C"],
    ["{&keys}", "&keys=semi,%3B,dot,.,comma,%2C"],
    ["{&keys*}", "&semi=%3B&dot=.&comma=%2C"],
    ["{v:3}", "6"],
    ["{x:3}", "102"],
    ["{x:1024}", "1024"],
    ["{x:10}", "1024"],
    ["{x:1}", "1"],
    ["{?x:10}", "?x=1024"],
    ["{&x:10}", "&x=1024"],
    ["{?x:3,y:4}", "?x=102&y=768"],
    ["{#x,y}", "#1024,768"],
    ["{;x,y}", ";x=1024;y=768"],
    ["{/x,y}", "/1024/768"],
    ["{.x,y}", ".1024.768"],
    ["{empty}", ""],
    ["{+empty}", ""],
    ["{#empty}", "#"],
    ["{.empty}", "."],
    ["{/empty}", "/"],
    ["{;empty}", ";empty"],
    ["{?empty}", "?empty="],
    ["{&empty}", "&empty="],
    ["{empty_keys}", ""],
    ["{empty_keys*}", ""],
    ["{+empty_keys}", ""],
    ["{+empty_keys*}", ""],
    ["{#empty_keys}", ""],
    ["{#empty_keys*}", ""],
    ["{.empty_keys}", ""],
    ["{.empty_keys*}", ""],
    ["{/empty_keys}", ""],
    ["{/empty_keys*}", ""],
    ["{;empty_keys}", ""],
    ["{;empty_keys*}", ""],
    ["{?empty_keys}", ""],
    ["{?empty_keys*}", "?empty_keys="],
    ["{&empty_keys}", ""],
    ["{&empty_keys*}", "&empty_keys="],
    ["{empty_list}", ""],
    ["{empty_list*}", ""],
    ["{?empty_list*}", "?empty_list="],
    ["{&empty_list*}", "&empty_list="],
    ["{;empty_list*}", ""],
    ["{undef}", ""],
    ["{hello:2}", "He"],
    ["{half:2}", "50"],
    ["{path:6}", "%2Ffoo%2Fb"],
    ["{dub:3}", "me%2F"],
  ].freeze

  def test_rfc_6570_examples
    RFC_EXAMPLES.each do |template, expected|
      assert_equal(expected, URI::Template.new(template).expand(VARIABLES), template)
    end
  end

  def test_missing_variables
    t = URI::Template.new("http://example.com/{a}/{b}")
    assert_equal("http://example.com//", t.expand({}))
    assert_equal("http://example.com//", t.expand("a" => nil, "b" => nil))
    assert_equal("http://example.com/x/", t.expand("a" => "x"))
    assert_equal("http://example.com/x/y", t.expand("a" => "x", "b" => "y"))
  end

  def test_missing_skips_prefix
    assert_equal("", URI::Template.new("{/a}").expand({}))
    assert_equal("/x", URI::Template.new("{/a,b}").expand("b" => "x"))
    assert_equal("?b=x", URI::Template.new("{?a,b}").expand("b" => "x"))
    assert_equal("&b=x", URI::Template.new("{&a,b}").expand("b" => "x"))
    assert_equal(";b=x", URI::Template.new("{;a,b}").expand("b" => "x"))
    assert_equal("#x", URI::Template.new("{#a,b}").expand("b" => "x"))
    assert_equal(".x", URI::Template.new("{.a,b}").expand("b" => "x"))
    assert_equal("x", URI::Template.new("{+a,b}").expand("b" => "x"))
  end

  def test_empty_string_by_operator
    assert_equal("", URI::Template.new("{x}").expand("x" => ""))
    assert_equal("", URI::Template.new("{+x}").expand("x" => ""))
    assert_equal("#", URI::Template.new("{#x}").expand("x" => ""))
    assert_equal(".", URI::Template.new("{.x}").expand("x" => ""))
    assert_equal("/", URI::Template.new("{/x}").expand("x" => ""))
    assert_equal(";x", URI::Template.new("{;x}").expand("x" => ""))
    assert_equal("?x=", URI::Template.new("{?x}").expand("x" => ""))
    assert_equal("&x=", URI::Template.new("{&x}").expand("x" => ""))
    assert_equal("a;xb", URI::Template.new("a{;x}b").expand("x" => ""))
    assert_equal("a?x=b", URI::Template.new("a{?x}b").expand("x" => ""))
  end

  def test_empty_collections_by_operator
    operators = {"simple" => "", "reserved" => "+", "fragment" => "#",
                 "label" => ".", "path" => "/", "matrix" => ";"}
    operators.each do |_name, op|
      ["{#{op}l}", "{#{op}l*}", "{#{op}m}", "{#{op}m*}"].each do |t|
        assert_equal("", URI::Template.new(t).expand("l" => [], "m" => {}), t)
      end
    end
    # Form-style query: only the exploded empty composite emits name=
    assert_equal("?l=", URI::Template.new("{?l*}").expand("l" => []))
    assert_equal("&l=", URI::Template.new("{&l*}").expand("l" => []))
    assert_equal("?m=", URI::Template.new("{?m*}").expand("m" => {}))
    assert_equal("&m=", URI::Template.new("{&m*}").expand("m" => {}))
    assert_equal("", URI::Template.new("{?l}").expand("l" => []))
    assert_equal("", URI::Template.new("{?m}").expand("m" => {}))
    assert_equal("", URI::Template.new("{;l*}").expand("l" => []))
    # When another variable contributes, the exploded empty list still
    # emits its name, followed by the next pair
    assert_equal("?l=&y=1", URI::Template.new("{?l*,y}").expand("l" => [], "y" => "1"))
    assert_equal("?y=1", URI::Template.new("{?l,y}").expand("l" => [], "y" => "1"))
  end

  def test_commas_slashes_in_scalars
    assert_equal("a%2Cb", URI::Template.new("{x}").expand("x" => "a,b"))
    assert_equal("a,b", URI::Template.new("{+x}").expand("x" => "a,b"))
    assert_equal("a/b", URI::Template.new("{+x}").expand("x" => "a/b"))
    assert_equal("/a%2Fb", URI::Template.new("{/x}").expand("x" => "a/b"))
    assert_equal("#a/b,c", URI::Template.new("{#x}").expand("x" => "a/b,c"))
  end

  def test_commas_slashes_in_lists
    list = ["a,b", "c/d"]
    assert_equal("a%2Cb,c%2Fd", URI::Template.new("{l}").expand("l" => list))
    assert_equal("a,b,c/d", URI::Template.new("{+l*}").expand("l" => list))
    assert_equal("?l=a%2Cb&l=c%2Fd", URI::Template.new("{?l*}").expand("l" => list))
    assert_equal("/a%2Cb/c%2Fd", URI::Template.new("{/l*}").expand("l" => list))
    assert_equal(".a%2Cb.c%2Fd", URI::Template.new("{.l*}").expand("l" => list))
    assert_equal("a,b,c/d", URI::Template.new("{+x*}").expand("x" => list))
  end

  def test_commas_slashes_in_associative_arrays
    pairs = {"k1,k2" => "v1/v2", "a/b" => "c,d"}
    assert_equal("k1%2Ck2,v1%2Fv2,a%2Fb,c%2Cd",
                 URI::Template.new("{m}").expand("m" => pairs))
    assert_equal("?k1%2Ck2=v1%2Fv2&a%2Fb=c%2Cd",
                 URI::Template.new("{?m*}").expand("m" => pairs))
    assert_equal("#k1%2Ck2=v1/v2,a%2Fb=c,d",
                 URI::Template.new("{#m*}").expand("m" => pairs))
    assert_equal("/k1%2Ck2=v1%2Fv2/a%2Fb=c%2Cd",
                 URI::Template.new("{/m*}").expand("m" => pairs))
  end

  def test_multibyte_prefix_counts_characters
    word = "\u00e9\u00e8abc"
    assert_equal("%C3%A9%C3%A8", URI::Template.new("{w:2}").expand("w" => word))
    assert_equal("%C3%A9%C3%A8a", URI::Template.new("{w:3}").expand("w" => word))
    han = "\u4e2d\u6587"
    assert_equal("%E4%B8%AD", URI::Template.new("{h:1}").expand("h" => han))
    assert_equal("%E4%B8%AD%E6%96%87", URI::Template.new("{h:2}").expand("h" => han))
    emoji = "\u{1F600}x"
    assert_equal("%F0%9F%98%80", URI::Template.new("{e:1}").expand("e" => emoji))
  end

  def test_utf8_byte_encoding
    assert_equal("%E4%B8%AD%E6%96%87", URI::Template.new("{x}").expand("x" => "\u4e2d\u6587"))
    assert_equal("%C3%A9", URI::Template.new("{x}").expand("x" => "\u00e9"))
    # multibyte literal in the template is passed through untouched
    assert_equal("\u4e2d/x", URI::Template.new("\u4e2d/{x}").expand("x" => "x"))
  end

  def test_associative_array_keeps_iteration_order
    ordered = {"z" => "1", "a" => "2", "m" => "3"}
    assert_equal("z=1,a=2,m=3", URI::Template.new("{m*}").expand("m" => ordered))
    assert_equal("?z=1&a=2&m=3", URI::Template.new("{?m*}").expand("m" => ordered))
    non_exploded = ordered.map { |k, v| "#{k},#{v}" }.join(",")
    assert_equal(non_exploded, URI::Template.new("{m}").expand("m" => ordered))
  end

  def test_values_are_not_reexpanded
    assert_equal("%7Bx%7D", URI::Template.new("{v}").expand("v" => "{x}"))
    assert_equal("%7Bx%7D", URI::Template.new("{+v}").expand("v" => "{x}"))
    assert_equal("?v=%7Bx%7D", URI::Template.new("{?v}").expand("v" => "{x}"))
    assert_equal("a=%7B,b=1", URI::Template.new("{m*}").expand("m" => {"a" => "{", "b" => "1"}))
    assert_equal("a=%2C,b=%2F", URI::Template.new("{m*}").expand("m" => {"a" => ",", "b" => "/"}))
    assert_equal("?a=%7B&b=1", URI::Template.new("{?m*}").expand("m" => {"a" => "{", "b" => "1"}))
  end

  def test_reserved_chars_only_kept_by_reserved_operators
    value = "a/b:c?d=e&f#g"
    assert_equal("a%2Fb%3Ac%3Fd%3De%26f%23g",
                 URI::Template.new("{v}").expand("v" => value))
    assert_equal("a/b:c?d=e&f#g",
                 URI::Template.new("{+v}").expand("v" => value))
    assert_equal("#a/b:c?d=e&f#g",
                 URI::Template.new("{#v}").expand("v" => value))
    assert_equal("/a%2Fb%3Ac%3Fd%3De%26f%23g",
                 URI::Template.new("{/v}").expand("v" => value))
    assert_equal("?v=a%2Fb%3Ac%3Fd%3De%26f%23g",
                 URI::Template.new("{?v}").expand("v" => value))
    # percent itself is never reserved
    assert_equal("50%25", URI::Template.new("{+v}").expand("v" => "50%"))
  end

  def test_explode_and_prefix_combined
    assert_equal("a,b,c", URI::Template.new("{l*}").expand("l" => %w[a b c]))
    assert_raise(URI::InvalidTemplateError) { URI::Template.new("{v:1*}") }
    # Prefix modifier on a composite is syntactically valid but ignored
    assert_equal("a,b", URI::Template.new("{l:1}").expand("l" => %w[a b]))
    assert_equal("k,v", URI::Template.new("{m:1}").expand("m" => {"k" => "v"}))
  end

  def test_literal_characters
    assert_equal("a?b=c&d=e", URI::Template.new("a?b=c&d=e").expand({}))
    assert_equal("~user", URI::Template.new("~{x}").expand("x" => "user"))
    assert_raise(URI::InvalidTemplateError) { URI::Template.new("a b") }
    assert_raise(URI::InvalidTemplateError) { URI::Template.new("a|b") }
    assert_raise(URI::InvalidTemplateError) { URI::Template.new("a\"b") }
    # "[" is part of the RFC 6570 literal grammar
    assert_equal("a[b", URI::Template.new("a[b").expand({}))
    assert_equal("a%20b", URI::Template.new("{x}").expand("x" => "a b"))
  end

  def test_syntax_errors_reported_at_creation
    error = assert_raise(URI::InvalidTemplateError) { URI::Template.new("{var") }
    assert_equal(0, error.offset)
    assert_equal(1, error.length)
    assert_match(/unclosed expression/, error.message)

    error = assert_raise(URI::InvalidTemplateError) { URI::Template.new("abc}") }
    assert_equal(3, error.offset)

    error = assert_raise(URI::InvalidTemplateError) { URI::Template.new("xx{:3}") }
    assert_equal(3, error.offset)

    error = assert_raise(URI::InvalidTemplateError) { URI::Template.new("{var:99999}") }
    assert_equal(5, error.offset)
    assert_equal(5, error.length)

    assert_raise(URI::InvalidTemplateError) { URI::Template.new("{}") }
    assert_raise(URI::InvalidTemplateError) { URI::Template.new("{+}") }
    assert_raise(URI::InvalidTemplateError) { URI::Template.new("{var:0}") }
    assert_raise(URI::InvalidTemplateError) { URI::Template.new("{var:}") }
    assert_raise(URI::InvalidTemplateError) { URI::Template.new("{var**}") }
    assert_raise(URI::InvalidTemplateError) { URI::Template.new("{%2}") }
  end

  def test_error_subclass
    assert(URI::InvalidTemplateError < URI::Error)
  end

  def test_expand_accepts_keywords
    t = URI::Template.new("http://example.com/{who}{?q}")
    assert_equal("http://example.com/fred?q=hi", t.expand(who: "fred", q: "hi"))
  end

  def test_pattern_and_inspect
    t = URI::Template.new("http://example.com/{x}")
    assert_equal("http://example.com/{x}", t.pattern)
    assert_equal("http://example.com/{x}", t.to_s)
    assert_match(/URI::Template/, t.inspect)
    assert_equal(t, URI::Template.new("http://example.com/{x}"))
    assert_equal(t.hash, URI::Template.new("http://example.com/{x}").hash)
    assert(t.eql?(URI::Template.new("http://example.com/{x}")))
  end

  def test_invalid_value_types
    assert_raise(URI::InvalidTemplateError) do
      URI::Template.new("{x}").expand("x" => 5)
    end
    assert_raise(URI::InvalidTemplateError) do
      URI::Template.new("{x*}").expand("x" => [1])
    end
    assert_raise(URI::InvalidTemplateError) do
      URI::Template.new("{x*}").expand("x" => {"k" => 2})
    end
    assert_raise(TypeError) { URI::Template.new(42) }
  end

  def test_result_is_parseable
    expanded = URI::Template.new("http://example.com/search{?q,tags*}").expand(
      "q" => "hello world", "tags" => ["a b", "c/d"])
    uri = URI.parse(expanded)
    assert_equal("example.com", uri.host)
    assert_equal("/search", uri.path)
    assert_equal("q=hello%20world&tags=a%20b&tags=c%2Fd", uri.query)
  end

  def test_multiple_expressions_and_reuse
    t = URI::Template.new("http://example.com/{p}{?l*}{#m*}")
    out = t.expand("p" => "x", "l" => %w[a b], "m" => {"k" => "v"})
    assert_equal("http://example.com/x?l=a&l=b#k=v", out)
    assert_equal("http://example.com/y?l=c#d=e",
                 t.expand("p" => "y", "l" => %w[c], "m" => {"d" => "e"}))
  end

  def test_percent_encoded_varnames
    # Percent-encoded triplets are syntactic sugar only: the lookup
    # name is the verbatim "a%41b", matching the RFC which never
    # canonicalizes variable names.
    assert_equal("z", URI::Template.new("{a%41b}").expand("a%41b" => "z"))
    assert_equal("z", URI::Template.new("{a.b}").expand("a.b" => "z"))
    assert_raise(URI::InvalidTemplateError) { URI::Template.new("{a..b}") }
    assert_raise(URI::InvalidTemplateError) { URI::Template.new("{%zz}") }
  end

  def test_multibyte_literals
    assert_equal("\u4e2d/x", URI::Template.new("\u4e2d/{x}").expand("x" => "x"))
    assert_equal("\u{1F600}!x", URI::Template.new("\u{1F600}!{x}").expand("x" => "x"))
    assert_raise(URI::InvalidTemplateError) { URI::Template.new("a\tb") }
    assert_raise(URI::InvalidTemplateError) { URI::Template.new("\x7f") }
  end

  def test_non_utf8_values_transcoded
    value = "caf\u00e9".encode("ISO-8859-1")
    assert_equal("caf%C3%A9", URI::Template.new("{x}").expand("x" => value))
    assert_equal("caf%C3%A9", URI::Template.new("{+x}").expand("x" => value))
  end

  def test_prefix_larger_than_value
    assert_equal("abc", URI::Template.new("{x:10}").expand("x" => "abc"))
    assert_equal("abc", URI::Template.new("{x:9999}").expand("x" => "abc"))
    assert_equal("%C3%A9", URI::Template.new("{x:9999}").expand("x" => "\u00e9"))
    assert_equal("%C3%A9", URI::Template.new("{x:9999}").expand("x" => "\u00e9"))
  end

  def test_prefix_applied_before_encoding
    assert_equal("me%2F", URI::Template.new("{x:3}").expand("x" => "me/too"))
    assert_equal("Hello%20W", URI::Template.new("{x:7}").expand("x" => "Hello World!"))
  end
end
