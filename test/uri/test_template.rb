# frozen_string_literal: true
require 'test/unit'
require 'uri'

class URI::TestTemplate < Test::Unit::TestCase
  # Variables used by the RFC 6570 section 3.2 examples.
  VARS = {
    "count"     => %w[one two three],
    "dom"       => %w[example com],
    "dub"       => "me/too",
    "hello"     => "Hello World!",
    "half"      => "50%",
    "var"       => "value",
    "who"       => "fred",
    "base"      => "http://example.com/home/",
    "path"      => "/foo/bar",
    "list"      => %w[red green blue],
    "chars"     => %w[ä ö] + ["中"],
    "keys"      => {"semi" => ";", "dot" => ".", "comma" => ","},
    "v"         => "6",
    "x"         => "1024",
    "y"         => "768",
    "empty"     => "",
    "empty_keys"=> [],
    "empty_map" => {},
    "Oof!"      => [],
  }.freeze

  def check(table)
    table.each do |template, expected|
      assert_equal(expected,
                   URI::Template.new(template).expand(VARS),
                   template.inspect)
    end
  end

  # RFC 6570 section 3.2.2
  def test_simple_expansion
    check(
      "{var}"       => "value",
      "{hello}"     => "Hello%20World%21",
      "{half}"      => "50%25",
      "O{empty}X"   => "OX",
      "O{undef}X"   => "OX",
      "{x,y}"       => "1024,768",
      "{x,hello,y}" => "1024,Hello%20World%21,768",
      "?{x,empty}"  => "?1024,",
      "?{x,undef}"  => "?1024",
      "?{undef,y}"  => "?768",
      "{list}"      => "red,green,blue",
      "{list*}"     => "red,green,blue",
      "{keys}"      => "semi,%3B,dot,.,comma,%2C",
      "{keys*}"     => "semi=%3B,dot=.,comma=%2C",
      "{count}"     => "one,two,three",
      "{count*}"    => "one,two,three",
      "{dom}"       => "example,com",
      "{dom*}"      => "example,com",
      "X{empty}X"   => "XX",
    )
  end

  # RFC 6570 section 3.2.3
  def test_reserved_expansion
    check(
      "{+var}"      => "value",
      "{+hello}"    => "Hello%20World!",
      "{+half}"     => "50%25",
      "O{+empty}X"  => "OX",
      "O{+undef}X"  => "OX",
      "{+path}/here"=> "/foo/bar/here",
      "here?ref={+path}" => "here?ref=/foo/bar",
      "up{+path}{var}/here" => "up/foo/barvalue/here",
      "{+x,hello,y}" => "1024,Hello%20World!,768",
      "{+path,x}/here" => "/foo/bar,1024/here",
      "{+path:6}/here" => "/foo/b/here",
      "{+list}"     => "red,green,blue",
      "{+list*}"    => "red,green,blue",
      "{+keys}"     => "semi,;,dot,.,comma,,",
      "{+keys*}"    => "semi=;,dot=.,comma=,",
      "{+chars}"    => "%C3%A4,%C3%B6,%E4%B8%AD",
      "{+chars*}"   => "%C3%A4,%C3%B6,%E4%B8%AD",
      "{+count}"    => "one,two,three",
      "{+count*}"   => "one,two,three",
      "{+dub}"      => "me/too",
      "{+Oof%21}"   => "",
    )
  end

  # RFC 6570 section 3.2.4
  def test_fragment_expansion
    check(
      "{#var}"      => "#value",
      "{#hello}"    => "#Hello%20World!",
      "{#half}"     => "#50%25",
      "foo{#empty}" => "foo#",
      "foo{#undef}" => "foo",
      "{#x,hello,y}" => "#1024,Hello%20World!,768",
      "{#path,x}/here" => "#/foo/bar,1024/here",
      "{#path:6}/here" => "#/foo/b/here",
      "{#list}"     => "#red,green,blue",
      "{#list*}"    => "#red,green,blue",
      "{#keys}"     => "#semi,;,dot,.,comma,,",
      "{#keys*}"    => "#semi=;,dot=.,comma=,",
      "{#count}"    => "#one,two,three",
      "{#count*}"   => "#one,two,three",
      "{#chars}"    => "#%C3%A4,%C3%B6,%E4%B8%AD",
      "{#chars*}"   => "#%C3%A4,%C3%B6,%E4%B8%AD",
      "{#Oof%21}"   => "",
    )
  end

  # RFC 6570 section 3.2.5
  def test_label_expansion_with_dot_prefix
    check(
      "{.who}"        => ".fred",
      "{.who,who}"    => ".fred.fred",
      "{.half,who}"   => ".50%25.fred",
      "www{.dom*}"    => "www.example.com",
      "X{.empty}"     => "X.",
      "X{.undef}"     => "X",
      "{.list}"       => ".red,green,blue",
      "{.list*}"      => ".red.green.blue",
      "{.keys}"       => ".semi,%3B,dot,.,comma,%2C",
      "{.keys*}"      => ".semi=%3B.dot=..comma=%2C",
      "{.empty_keys}" => "",
      "{.empty_keys*}"=> "",
      "{.count}"      => ".one,two,three",
      "{.count*}"     => ".one.two.three",
      "{.var:3}"      => ".val",
    )
  end

  # RFC 6570 section 3.2.6
  def test_path_segment_expansion
    check(
      "{/who}"        => "/fred",
      "{/who,who}"    => "/fred/fred",
      "{/half,who}"   => "/50%25/fred",
      "{/who,dub}"    => "/fred/me%2Ftoo",
      "{/var}"        => "/value",
      "{/var,empty}"  => "/value/",
      "{/var,undef}"  => "/value",
      "{/empty,undef}/here" => "//here",
      "{/list}"       => "/red,green,blue",
      "{/list*}"      => "/red/green/blue",
      "{/list*,path:4}" => "/red/green/blue/%2Ffoo",
      "{/keys}"       => "/semi,%3B,dot,.,comma,%2C",
      "{/keys*}"      => "/semi=%3B/dot=./comma=%2C",
      "{/count}"      => "/one,two,three",
      "{/count*}"     => "/one/two/three",
      "{/chars}"      => "/%C3%A4,%C3%B6,%E4%B8%AD",
      "{/chars*}"     => "/%C3%A4/%C3%B6/%E4%B8%AD",
      "{/empty_keys}" => "",
      "{/who:2}"      => "/fr",
    )
  end

  # RFC 6570 section 3.2.7
  def test_path_style_parameter_expansion
    check(
      "{;who}"        => ";who=fred",
      "{;half}"       => ";half=50%25",
      "{;empty}"      => ";empty",
      "{;v,empty,who}"=> ";v=6;empty;who=fred",
      "{;v,bar,who}"  => ";v=6;who=fred",
      "{;list}"       => ";list=red,green,blue",
      "{;list*}"      => ";list=red;list=green;list=blue",
      "{;keys}"       => ";keys=semi,%3B,dot,.,comma,%2C",
      "{;keys*}"      => ";semi=%3B;dot=.;comma=%2C",
      "{;count}"      => ";count=one,two,three",
      "{;count*}"     => ";count=one;count=two;count=three",
      "{;empty_keys}" => "",
      "{;x,y}"        => ";x=1024;y=768",
      "{;x,empty}"    => ";x=1024;empty",
      "{;x,undef}"    => ";x=1024",
      "{;undef,y}"    => ";y=768",
      "{;who:10}"     => ";who=fred",
      "{;hello:5}"    => ";hello=Hello",
    )
  end

  # RFC 6570 section 3.2.8
  def test_form_style_query_expansion
    check(
      "{?who}"        => "?who=fred",
      "{?half}"       => "?half=50%25",
      "{?x,y}"        => "?x=1024&y=768",
      "{?x,hello,y}"  => "?x=1024&hello=Hello%20World%21&y=768",
      "{?x,empty}"    => "?x=1024&empty=",
      "{?x,undef}"    => "?x=1024",
      "{?undef,y}"    => "?y=768",
      "{?list}"       => "?list=red,green,blue",
      "{?list*}"      => "?list=red&list=green&list=blue",
      "{?keys}"       => "?keys=semi,%3B,dot,.,comma,%2C",
      "{?keys*}"      => "?semi=%3B&dot=.&comma=%2C",
      "{?count}"      => "?count=one,two,three",
      "{?count*}"     => "?count=one&count=two&count=three",
      "{?empty}"      => "?empty=",
      "{?empty_keys}" => "",
      "{?chars*}"     => "?chars=%C3%A4&chars=%C3%B6&chars=%E4%B8%AD",
      "{?var:3}"      => "?var=val",
    )
  end

  # RFC 6570 section 3.2.9
  def test_form_style_query_continuation
    check(
      "{&who}"        => "&who=fred",
      "{&half}"       => "&half=50%25",
      "?fixed=yes{&x}"=> "?fixed=yes&x=1024",
      "{&x,y,empty}"  => "&x=1024&y=768&empty=",
      "{&x,y,undef}"  => "&x=1024&y=768",
      "{&list}"       => "&list=red,green,blue",
      "{&list*}"      => "&list=red&list=green&list=blue",
      "{&keys}"       => "&keys=semi,%3B,dot,.,comma,%2C",
      "{&keys*}"      => "&semi=%3B&dot=.&comma=%2C",
      "{&count}"      => "&count=one,two,three",
      "{&count*}"     => "&count=one&count=two&count=three",
      "{&empty}"      => "&empty=",
      "{&empty_keys}" => "",
    )
  end

  # RFC 6570 section 3.2.4 (prefix truncation examples)
  def test_prefix_length
    check(
      "{var}"       => "value",
      "{var:1}"     => "v",
      "{var:3}"     => "val",
      "{var:5}"     => "value",
      "{var:7}"     => "value",
      "{var:10}"    => "value",
      "{var:30}"    => "value",
      "{var:1000}"  => "value",
      "{path:1}"    => "%2F",
      "{+path:1}"   => "/",
      "{path:3}"    => "%2Ffo",
      "{+path:3}"   => "/fo",
      "{path:6}"    => "%2Ffoo%2Fb",
      "{path:10}"   => "%2Ffoo%2Fbar",
      "{+path:10}"  => "/foo/bar",
      "{hello}"     => "Hello%20World%21",
      "{hello:3}"   => "Hel",
      "{+hello:3}"  => "Hel",
      "{#hello:3}"  => "#Hel",
      "{/hello:3}"  => "/Hel",
      "{;hello:3}"  => ";hello=Hel",
      "{?hello:3}"  => "?hello=Hel",
      "{&hello:3}"  => "&hello=Hel",
      "{.hello:3}"  => ".Hel",
      "{half:1}"    => "5",
      "{+half:2}"   => "50",
    )
  end

  def test_prefix_length_counts_unicode_characters
    vars = {"smile" => "\u{1F600}ab", "word" => "\u{540d}\u{5b57}\u{4e16}\u{754c}"}
    template = URI::Template.new("{smile:2}")
    assert_equal("%F0%9F%98%80a", template.expand(vars))
    assert_equal("?smile=%F0%9F%98%80a",
                 URI::Template.new("{?smile:2}").expand(vars))
    assert_equal("%E5%90%8D%E5%AD%97",
                 URI::Template.new("{word:2}").expand(vars))
    assert_equal("/%E5%90%8D/%E5%AD%97",
                 URI::Template.new("{/word*}").expand(
                   "word" => ["\u{540d}", "\u{5b57}"]))
  end

  def test_comma_slash_and_multibyte_keys_and_values
    vars = {
      "comma" => "a,b",
      "slash" => "c/d",
      "both"  => "/a,b/c",
      "map"   => {"a,b" => "1,2", "c/d" => "/x/y", "\u{540d}" => "\u{5b57}"},
      "list"  => ["a,b", "c/d", "\u{540d}"],
    }
    check_sets = {
      "{comma}"       => "a%2Cb",
      "{slash}"       => "c%2Fd",
      "{both}"        => "%2Fa%2Cb%2Fc",
      "{+comma}"      => "a,b",
      "{+slash}"      => "c/d",
      "{+both}"       => "/a,b/c",
      "{#both}"       => "#/a,b/c",
      "{?comma,slash}"=> "?comma=a%2Cb&slash=c%2Fd",
      "{&comma}"      => "&comma=a%2Cb",
      "{;slash}"      => ";slash=c%2Fd",
      "{/both}"       => "/%2Fa%2Cb%2Fc",
      "{.both}"       => ".%2Fa%2Cb%2Fc",
      "{map}"         => "a%2Cb,1%2C2,c%2Fd,%2Fx%2Fy,%E5%90%8D,%E5%AD%97",
      "{+map}"        => "a%2Cb,1,2,c%2Fd,/x/y,%E5%90%8D,%E5%AD%97",
      "{#map*}"       => "#a%2Cb=1,2,c%2Fd=/x/y,%E5%90%8D=%E5%AD%97",
      "{?map*}"       => "?a%2Cb=1%2C2&c%2Fd=%2Fx%2Fy&%E5%90%8D=%E5%AD%97",
      "{/map*}"       => "/a%2Cb=1%2C2/c%2Fd=%2Fx%2Fy/%E5%90%8D=%E5%AD%97",
      "{list}"        => "a%2Cb,c%2Fd,%E5%90%8D",
      "{+list*}"      => "a,b,c/d,%E5%90%8D",
      "{?list*}"      => "?list=a%2Cb&list=c%2Fd&list=%E5%90%8D",
      "{/list*}"      => "/a%2Cb/c%2Fd/%E5%90%8D",
      "{.list*}"      => ".a%2Cb.c%2Fd.%E5%90%8D",
      "{#list*}"      => "#a,b,c/d,%E5%90%8D",
    }
    check_sets.each do |t, expected|
      assert_equal(expected, URI::Template.new(t).expand(vars), t)
    end
  end

  def test_associative_array_keeps_caller_iteration_order
    map = {"b" => "2", "a" => "1", "C" => "3"}
    assert_equal("b,2,a,1,C,3",
                 URI::Template.new("{m}").expand("m" => map))
    assert_equal("b=2,a=1,C=3",
                 URI::Template.new("{+m*}").expand("m" => map))
    assert_equal("?b=2&a=1&C=3",
                 URI::Template.new("{?m*}").expand("m" => map))

    rehashed = map.to_a.reverse.to_h
    assert_equal("C,3,a,1,b,2",
                 URI::Template.new("{m}").expand("m" => rehashed))
  end

  def test_missing_empty_and_empty_collection_by_operator
    list_empty = {"l" => [], "m" => {}}
    ["", "+", "#", ".", "/", ";", "?", "&"].each do |op|
      ["l", "m"].each do |name|
        assert_equal("",
                     URI::Template.new("{#{op}#{name}}").expand(list_empty))
        assert_equal("",
                     URI::Template.new("{#{op}#{name}*}").expand(list_empty))
      end
    end
  end

  def test_empty_items_inside_composites
    vars = {"l" => ["", ""], "m" => {"a" => ""}}
    assert_equal(",", URI::Template.new("{l}").expand(vars))
    assert_equal(",", URI::Template.new("{+l*}").expand(vars))
    assert_equal("#,", URI::Template.new("{#l*}").expand(vars))
    assert_equal("//", URI::Template.new("{/l*}").expand(vars))
    assert_equal("..", URI::Template.new("{.l*}").expand(vars))
    assert_equal(";l=;l=", URI::Template.new("{;l*}").expand(vars))
    assert_equal("?l=&l=", URI::Template.new("{?l*}").expand(vars))
    assert_equal("&l=&l=", URI::Template.new("{&l*}").expand(vars))
    assert_equal("a,", URI::Template.new("{m}").expand(vars))
    assert_equal("a=", URI::Template.new("{+m*}").expand(vars))
    assert_equal("?a=", URI::Template.new("{?m*}").expand(vars))
    assert_equal(";a=", URI::Template.new("{;m*}").expand(vars))
    assert_equal("/a=", URI::Template.new("{/m*}").expand(vars))
  end

  def test_variables_are_not_re_expanded
    vars = {"who" => "{who}", "a" => "{b}", "b" => "deep"}
    assert_equal("%7Bwho%7D", URI::Template.new("{who}").expand(vars))
    assert_equal("%7Bwho%7D", URI::Template.new("{+who}").expand(vars))
    assert_equal("?a=%7Bb%7D", URI::Template.new("{?a}").expand(vars))
  end

  def test_expanded_result_is_parseable
    expanded = URI::Template.new(
      "https://example.com/{who}{?q,lang,list}").expand(
        "who"  => "a/b c",
        "q"    => "r&d",
        "lang" => "\u{65e5}",
        "list" => %w[x y])
    uri = URI.parse(expanded)
    assert_equal("https", uri.scheme)
    assert_equal("/a%2Fb%20c", uri.path)
    pairs = URI.decode_www_form(uri.query)
    assert_equal(["q", "r&d"], pairs.assoc("q"))
    assert_equal(["lang", "\u{65e5}"], pairs.assoc("lang"))
    assert_equal([["list", "x,y"]],
                 pairs.select { |key,| key == "list" })
  end

  def test_invalid_syntax_raised_at_construction
    invalid = {
      "{var:unknown}"  => [4, 6],
      "{who"           => [0, 4],
      "{var:2"         => [0, 6],
      "}"              => [0, 1],
      "{>var}"         => [1, 2],
      "dud {e"         => nil,
      "{var:2*}"       => nil,
      "{var*:2}"       => nil,
      "{var::2}"       => nil,
      "{var:02}"       => nil,
      "{var:0}"        => nil,
      "{var:99999}"    => nil,
      "{var:10000}"    => nil,
      "{var:}"         => nil,
      "{var"           => nil,
      "{}"             => nil,
      "{+}"            => nil,
      "{#}"            => nil,
      "{var,}"         => nil,
      "{,var}"         => nil,
      "{var..x}"       => nil,
      "{va r}"         => nil,
      "{va-r}"         => nil,
      "{va%2r}"        => nil,
      "{va%2}"         => nil,
      "{var=%20}"      => nil,
      "{var=}"         => nil,
      "{var?}"         => nil,
      "hello{world"    => nil,
      "a%ZZ"           => nil,
      "a%"             => nil,
      "a|b"            => nil,
      "a b"            => nil,
      "a\"b"           => nil,
      "{Oof!}"         => nil,
      "{#*}"           => nil,
      "{var/name}"     => nil,
    }
    invalid.each do |pattern, range|
      error = assert_raise(URI::Template::InvalidTemplate, pattern.inspect) do
        URI::Template.new(pattern)
      end
      assert_kind_of(Array, error.range, pattern.inspect)
      assert_equal(range, error.range, pattern.inspect) if range
    end
  end

  def test_valid_literals
    [
      "http://example.com:8080/p;x?q=1&y=2#f",
      "a[b]#c",
      "$10(now)!*+,:;=@&",
      "a'b",
      "\u{540d}\u{5b57}/\u{1F600}",
      "100%20ok",
      "*",
    ].each do |literal|
      t = URI::Template.new(literal)
      assert_equal(literal, t.expand({}), literal.inspect)
    end
  end

  def test_expand_with_hash_and_keywords
    t = URI::Template.new("{a}{b}")
    assert_equal("XY", t.expand({"a" => "X"}, b: "Y"))
    assert_equal("ZW", t.expand({"a" => "X"}, a: "Z", b: "W"))
    assert_equal("1", t.expand(a: 1, b: nil))
  end

  def test_symbol_key_lookup
    t = URI::Template.new("{/who}")
    assert_equal("/fred", t.expand(who: "fred"))
  end

  def test_pattern_and_reuse
    t = URI::Template.new("x{who}y")
    assert_equal("xfredy", t.expand(who: "fred"))
    assert_equal("xbary", t.expand(who: "bar"))
    assert_equal("x{who}y", t.to_str)
    assert_equal("x{who}y", t.to_s)
    assert_equal("x{who}y", "#{t.pattern}")
    assert_match(/x\{who\}y/, t.inspect)
    assert_predicate(t.pattern, :frozen?)
  end

  def test_multiple_expressions
    t = URI::Template.new(
      "{scheme}://{host}{/path*}{?params*}")
    assert_equal("https://example.com/a/b?params=x&params=y",
                 t.expand(
                   "scheme" => "https",
                   "host"   => "example.com",
                   "path"   => %w[a b],
                   "params" => %w[x y]))
  end

  def test_integer_and_boolean_scalars
    t = URI::Template.new("{?n,b}")
    assert_equal("?n=42&b=true", t.expand(n: 42, b: true))
  end

  def test_non_hash_variables_raise
    assert_raise(TypeError) { URI::Template.new("{x}").expand(42) }
  end

  def test_nil_variables
    t = URI::Template.new("O{x}X")
    assert_equal("OX", t.expand(nil))
  end

  def test_nested_composites_raise
    t = URI::Template.new("{l}")
    assert_raise(ArgumentError) { t.expand("l" => [["nested"]]) }
    t2 = URI::Template.new("{m*}")
    assert_raise(ArgumentError) { t2.expand("m" => {"k" => {"x" => 1}}) }
  end

  def test_to_uri
    t = URI::Template.new("https://example.com/{who}")
    uri = t.to_uri(who: "fred")
    assert_instance_of(URI::HTTPS, uri)
    assert_equal("/fred", uri.path)
  end

  def test_nil_elements_inside_composites
    vars = {"l" => ["a", nil, "b"], "m" => {"k" => nil}}
    assert_equal("a,,b", URI::Template.new("{l}").expand(vars))
    assert_equal("/a//b", URI::Template.new("{/l*}").expand(vars))
    assert_equal("?l=a&l=&l=b", URI::Template.new("{?l*}").expand(vars))
    assert_equal("k,", URI::Template.new("{m}").expand(vars))
    assert_equal("k=", URI::Template.new("{+m*}").expand(vars))
    assert_equal("?k=", URI::Template.new("{?m*}").expand(vars))
  end

  def test_multibyte_percent_encoded_varname
    vars = {"\u{540d}" => "x"}
    assert_equal("x", URI::Template.new("{%E5%90%8D}").expand(vars))
    assert_equal("?%E5%90%8D=x",
                 URI::Template.new("{?%E5%90%8D}").expand(vars))
  end

  def test_prefix_on_composite_is_ignored_per_grammar
    t = URI::Template.new("{list:2}")
    assert_equal("red,green,blue", t.expand("list" => %w[red green blue]))
  end

  def test_pct_encoded_values_preserved_only_with_reserved_operator
    vars = {"u" => "http://x.com/100%20ok?q=%C3%A4"}
    assert_equal("http://x.com/100%20ok?q=%C3%A4",
                 URI::Template.new("{+u}").expand(vars))
    assert_equal("#http://x.com/100%20ok?q=%C3%A4",
                 URI::Template.new("{#u}").expand(vars))
    assert_equal("http%3A%2F%2Fx.com%2F100%2520ok%3Fq%3D%25C3%25A4",
                 URI::Template.new("{u}").expand(vars))
  end

  def test_symbol_values_and_keys_are_stringified
    t = URI::Template.new("{m*}")
    assert_equal("a=1", t.expand("m" => {a: 1}))
  end

  def test_to_hash_duck_typed_variables
    vars = Object.new
    def vars.to_hash
      {"a" => "b"}
    end
    assert_equal("b", URI::Template.new("{a}").expand(vars))
  end

  def test_range_is_half_open_and_on_the_template
    begin
      URI::Template.new("abc{!}")
      flunk
    rescue URI::Template::InvalidTemplate => error
      assert_equal([4, 5], error.range)
      assert_equal("!", "abc{!}"[error.range[0]...error.range[1]])
    end
  end

  def test_utf16_values_are_converted_to_utf8
    value = "\u{4e16}".encode(Encoding::UTF_16LE)
    result = URI::Template.new("{x}").expand("x" => value)
    assert_equal("%E4%B8%96", result)
    assert_predicate(result, :ascii_only?)
  end

  def test_ractor_shareable
    t = Ractor.make_shareable(URI::Template.new("http://x/{a}{?b}"))
    r = Ractor.new(t) do |template|
      template.expand("a" => "y", "b" => "z")
    end
    assert_equal("http://x/y?b=z", r.take)
  end if defined?(Ractor)

  def test_expansion_has_no_side_effects
    t = URI::Template.new("{?a,b}")
    assert_equal("?a=1", t.expand("a" => "1"))
    assert_equal("?b=2", t.expand("b" => "2"))
    assert_equal("?a=1&b=2", t.expand("a" => "1", "b" => "2"))
    assert_equal("x{?a,b}y", "x#{t}y")
  end
end
