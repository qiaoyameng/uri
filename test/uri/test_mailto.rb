# frozen_string_literal: false
require 'test/unit'
require 'uri/mailto'

class URI::TestMailTo < Test::Unit::TestCase
  def setup
    @u = URI::MailTo
  end

  def teardown
  end

  def uri_to_ary(uri)
    uri.class.component.collect {|c| uri.send(c)}
  end

  def test_build
    ok = []
    bad = []

    # RFC2368, 6. Examples
    # mailto:chris@example.com
    ok << ["mailto:chris@example.com"]
    ok[-1] << ["chris@example.com", nil]
    ok[-1] << {:to => "chris@example.com"}

    ok << ["mailto:foo+@example.com,bar@example.com"]
    ok[-1] << [["foo+@example.com", "bar@example.com"], nil]
    ok[-1] << {:to => "foo+@example.com,bar@example.com"}

    # mailto:infobot@example.com?subject=current-issue
    ok << ["mailto:infobot@example.com?subject=current-issue"]
    ok[-1] << ["infobot@example.com", ["subject=current-issue"]]
    ok[-1] << {:to => "infobot@example.com",
      :headers => ["subject=current-issue"]}

    # mailto:infobot@example.com?body=send%20current-issue
    ok << ["mailto:infobot@example.com?body=send%20current-issue"]
    ok[-1] << ["infobot@example.com", ["body=send%20current-issue"]]
    ok[-1] << {:to => "infobot@example.com",
      :headers => ["body=send%20current-issue"]}

    # mailto:infobot@example.com?body=send%20current-issue%0D%0Asend%20index
    ok << ["mailto:infobot@example.com?body=send%20current-issue%0D%0Asend%20index"]
    ok[-1] << ["infobot@example.com",
      ["body=send%20current-issue%0D%0Asend%20index"]]
    ok[-1] << {:to => "infobot@example.com",
      :headers => ["body=send%20current-issue%0D%0Asend%20index"]}

    # mailto:foobar@example.com?In-Reply-To=%3c3469A91.D10AF4C@example.com
    ok << ["mailto:foobar@example.com?In-Reply-To=%3c3469A91.D10AF4C@example.com"]
    ok[-1] << ["foobar@example.com",
      ["In-Reply-To=%3c3469A91.D10AF4C@example.com"]]
    ok[-1] << {:to => "foobar@example.com",
      :headers => ["In-Reply-To=%3c3469A91.D10AF4C@example.com"]}

    # mailto:majordomo@example.com?body=subscribe%20bamboo-l
    ok << ["mailto:majordomo@example.com?body=subscribe%20bamboo-l"]
    ok[-1] << ["majordomo@example.com", ["body=subscribe%20bamboo-l"]]
    ok[-1] << {:to => "majordomo@example.com",
      :headers => ["body=subscribe%20bamboo-l"]}

    # mailto:joe@example.com?cc=bob@example.com&body=hello
    ok << ["mailto:joe@example.com?cc=bob@example.com&body=hello"]
    ok[-1] << ["joe@example.com", ["cc=bob@example.com", "body=hello"]]
    ok[-1] << {:to => "joe@example.com",
      :headers => ["cc=bob@example.com", "body=hello"]}

    # mailto:?to=joe@example.com&cc=bob@example.com&body=hello
    ok << ["mailto:?to=joe@example.com&cc=bob@example.com&body=hello"]
    ok[-1] << [nil,
      ["to=joe@example.com", "cc=bob@example.com", "body=hello"]]
    ok[-1] << {:headers => ["to=joe@example.com",
	"cc=bob@example.com", "body=hello"]}

    # mailto:gorby%25kremvax@example.com
    ok << ["mailto:gorby%25kremvax@example.com"]
    ok[-1] << ["gorby%25kremvax@example.com", nil]
    ok[-1] << {:to => "gorby%25kremvax@example.com"}

    # mailto:unlikely%3Faddress@example.com?blat=foop
    ok << ["mailto:unlikely%3Faddress@example.com?blat=foop"]
    ok[-1] << ["unlikely%3Faddress@example.com", ["blat=foop"]]
    ok[-1] << {:to => "unlikely%3Faddress@example.com",
      :headers => ["blat=foop"]}

    # mailto:john@example.com?Subject=Ruby&Cc=jack@example.com
    ok << ["mailto:john@example.com?Subject=Ruby&Cc=jack@example.com"]
    ok[-1] << ['john@example.com', [['Subject', 'Ruby'], ['Cc', 'jack@example.com']]]
    ok[-1] << {:to=>"john@example.com", :headers=>[["Subject", "Ruby"], ["Cc", "jack@example.com"]]}

    # mailto:listman@example.com?subject=subscribe
    ok << ["mailto:listman@example.com?subject=subscribe"]
    ok[-1] << {:to => 'listman@example.com', :headers => [['subject', 'subscribe']]}
    ok[-1] << {:to => 'listman@example.com', :headers => [['subject', 'subscribe']]}

    # mailto:listman@example.com?subject=subscribe
    ok << ["mailto:listman@example.com?subject=subscribe"]
    ok[-1] << {:to => 'listman@example.com', :headers => { 'subject' => 'subscribe' }}
    ok[-1] << {:to => 'listman@example.com', :headers => 'subject=subscribe' }

    ok_all = ok.flatten.join("\0")

    # mailto:joe@example.com?cc=bob@example.com?body=hello   ; WRONG!
    bad << ["joe@example.com", ["cc=bob@example.com?body=hello"]]

    # mailto:javascript:alert()
    bad << ["javascript:alert()", []]

    # mailto:/example.com/    ; WRONG, not a mail address
    bad << ["/example.com/", []]

    # '=' which is in hname or hvalue is wrong.
    bad << ["foo@example.jp?subject=1+1=2", []]

    ok.each do |x|
      assert_equal(x[0], URI.parse(x[0]).to_s)
      assert_equal(x[0], @u.build(x[1]).to_s)
      assert_equal(x[0], @u.build(x[2]).to_s)
    end

    bad.each do |x|
      assert_raise(URI::InvalidURIError) {
        URI.parse(x)
      }
      assert_raise(URI::InvalidComponentError) {
	@u.build(x)
      }
    end

    assert_equal(ok_all, ok.flatten.join("\0"))
  end

  def test_initializer
    assert_raise(URI::InvalidComponentError) do
      URI::MailTo.new('mailto', 'sdmitry:bla', 'localhost', '2000', nil,
                      'joe@example.com', nil, nil, 'subject=Ruby')
    end
  end

  def test_check_to
    u = URI::MailTo.build(['joe@example.com', 'subject=Ruby'])

    # Valid emails
    u.to = 'a@valid.com'
    assert_equal(u.to, 'a@valid.com')

    # Intentionally allowed violations of RFC 5322
    u.to = 'a..a@valid.com'
    assert_equal(u.to, 'a..a@valid.com')

    u.to = 'hello.@valid.com'
    assert_equal(u.to, 'hello.@valid.com')

    u.to = '.hello@valid.com'
    assert_equal(u.to, '.hello@valid.com')

    # Invalid emails
    assert_raise(URI::InvalidComponentError) do
      u.to = '#1@mail.com'
    end

    assert_raise(URI::InvalidComponentError) do
      u.to = '@invalid.email'
    end

    # Invalid host emails
    assert_raise(URI::InvalidComponentError) do
      u.to = 'a@.invalid.email'
    end

    assert_raise(URI::InvalidComponentError) do
      u.to = 'a@invalid.email.'
    end

    assert_raise(URI::InvalidComponentError) do
      u.to = 'a@invalid..email'
    end

    assert_raise(URI::InvalidComponentError) do
      u.to = 'a@-invalid.email'
    end

    assert_raise(URI::InvalidComponentError) do
      u.to = 'a@invalid-.email'
    end

    assert_raise(URI::InvalidComponentError) do
      u.to = 'a@invalid.-email'
    end

    assert_raise(URI::InvalidComponentError) do
      u.to = 'a@invalid.email-'
    end

    u.to = 'a@'+'invalid'.ljust(63, 'd')+'.email'
    assert_raise(URI::InvalidComponentError) do
      u.to = 'a@'+'invalid'.ljust(64, 'd')+'.email'
    end

    u.to = 'a@invalid.'+'email'.rjust(63, 'e')
    assert_raise(URI::InvalidComponentError) do
      u.to = 'a@invalid.'+'email'.rjust(64, 'e')
    end
  end

  def test_email_regexp
    re = URI::MailTo::EMAIL_REGEXP

    repeat = 10
    longlabel = '.' + 'invalid'.ljust(63, 'd')
    endlabel = ''
    seq = (1..3).map {|i| 10**i}
    rehearsal = 10
    pre = ->(n) {'a@invalid' + longlabel*(n) + endlabel}
    assert_linear_performance(seq, rehearsal: rehearsal, pre: pre) do |to|
      repeat.times {re =~ to or flunk}
    end
    endlabel = '.' + 'email'.rjust(64, 'd')
    assert_linear_performance(seq, rehearsal: rehearsal, pre: pre) do |to|
      repeat.times {re =~ to and flunk}
    end
  end

  def test_to_s
    u = URI::MailTo.build([nil, 'subject=Ruby'])

    u.send(:set_to, nil)
    assert_equal('mailto:?subject=Ruby', u.to_s)

    u.fragment = 'test'
    assert_equal('mailto:?subject=Ruby#test', u.to_s)
  end

  def test_to_mailtext
    results = []
    results << ["To: ruby-list@ruby-lang.org\nSubject: subscribe\n\n\n"]
    results[-1] << { to: 'ruby-list@ruby-lang.org', headers: { 'subject' => 'subscribe' } }

    results << ["To: ruby-list@ruby-lang.org\n\nBody\n"]
    results[-1] << { to: 'ruby-list@ruby-lang.org', headers: { 'body' => 'Body' } }

    results << ["To: ruby-list@ruby-lang.org, cc@ruby-lang.org\n\n\n"]
    results[-1] << { to: 'ruby-list@ruby-lang.org', headers: { 'to' => 'cc@ruby-lang.org' } }

    results.each do |expected, params|
      u = URI::MailTo.build(params)
      assert_equal(expected, u.to_mailtext)
    end

    u = URI.parse('mailto:ruby-list@ruby-lang.org?Subject=subscribe&cc=myaddr')
    assert_equal "To: ruby-list@ruby-lang.org\nSubject: subscribe\nCc: myaddr\n\n\n",
      u.to_mailtext

    u = URI.parse('mailto:user+label@example.com?subject=hello+world')
    assert_equal "To: user+label@example.com\nSubject: hello+world\n\n\n",
      u.to_mailtext
  end

  def test_compose_fields
    uri = URI.parse(
      "mailto:user+label@example.com,second@example.com" \
      "?to=third+label@example.com,fourth@example.com" \
      "&Subject=Re%3A%20hello+world" \
      "&body=line%20one%0D%0AIn-Reply-To%3A%20not-a-header"
    )

    fields = uri.compose_fields(["Subject"])

    assert_equal(
      [
        "user+label@example.com",
        "second@example.com",
        "third+label@example.com",
        "fourth@example.com",
      ],
      fields[:to]
    )
    assert_equal({"Subject" => "Re: hello+world"}, fields[:headers])
    assert_equal("line one\r\nIn-Reply-To: not-a-header", fields[:body])
    assert_empty(fields[:headers].keys - ["Subject"])
  end

  def test_compose_fields_headers_are_case_insensitive
    uri = URI.parse("mailto:user@example.com?Subject=first&sUbJeCt=second")

    fields = uri.compose_fields(["Subject"], duplicate_headers: :first)
    assert_equal({"Subject" => "first"}, fields[:headers])

    fields = uri.compose_fields(["Subject"], duplicate_headers: :last)
    assert_equal({"Subject" => "second"}, fields[:headers])

    fields = uri.compose_fields(["Subject"], duplicate_headers: :join)
    assert_equal({"Subject" => "first, second"}, fields[:headers])
  end

  def test_compose_fields_duplicate_header_policy
    uri = URI.parse("mailto:user@example.com?X-Test=one&x-test=two")

    assert_raise(URI::InvalidComponentError) do
      uri.compose_fields(["X-Test"])
    end

    fields = uri.compose_fields(["X-Test"]) do |name, values|
      assert_equal("x-test", name)
      values.join(";")
    end
    assert_equal({"X-Test" => "one;two"}, fields[:headers])
  end

  def test_compose_fields_rejects_unallowed_headers_by_default
    uri = URI.parse("mailto:user@example.com?subject=hello&cc=other@example.com")

    error = assert_raise(URI::InvalidComponentError) do
      uri.compose_fields
    end
    assert_match(/subject/, error.message)

    assert_raise(URI::InvalidComponentError) do
      uri.compose_fields(["subject"])
    end
  end

  def test_compose_fields_rejects_encoded_colon_in_header_name
    uri = URI.parse("mailto:user@example.com?sub%3Aject=value")

    assert_raise(URI::InvalidComponentError) do
      uri.compose_fields(["subject"])
    end

    uri = URI.parse("mailto:user@example.com?body%3A=not-the-body")
    assert_raise(URI::InvalidComponentError) do
      uri.compose_fields
    end
  end

  def test_compose_fields_rejects_decoded_line_breaks_outside_body
    uri = URI.parse("mailto:user@example.com?subject=hello%0D%0AEvil:%20value")

    assert_raise(URI::InvalidComponentError) do
      uri.compose_fields(["subject"])
    end

    uri = URI.parse("mailto:user@example.com?sub%0D%0Aject=value")
    assert_raise(URI::InvalidComponentError) do
      uri.compose_fields(["subject"])
    end

    uri = URI.parse("mailto:user%0D%0A@example.com")
    assert_raise(URI::InvalidComponentError) do
      uri.compose_fields
    end
  end

  def test_compose_fields_does_not_decode_twice
    uri = URI.parse(
      "mailto:user@example.com" \
      "?body=safe%250d%250aIn-Reply-To%253A%2520not-a-header"
    )

    fields = uri.compose_fields

    assert_equal("safe%0d%0aIn-Reply-To%3A%20not-a-header", fields[:body])
    assert_empty(fields[:headers])

    uri = URI.parse("mailto:user@example.com?subject=safe%250d%250a")
    fields = uri.compose_fields(["Subject"])
    assert_equal({"Subject" => "safe%0d%0a"}, fields[:headers])
  end

  def test_compose_fields_ignores_empty_to_fields
    uri = URI.parse("mailto:?to=&to=user@example.com")
    fields = uri.compose_fields
    assert_equal(["user@example.com"], fields[:to])
  end

  def test_compose_fields_rejects_unknown_duplicate_policy
    uri = URI.parse("mailto:user@example.com?subject=one&subject=two")

    assert_raise(ArgumentError) do
      uri.compose_fields(["subject"], duplicate_headers: :unknown)
    end
  end

  def test_compose_fields_duplicate_body_policy
    uri = URI.parse("mailto:user@example.com?body=one&body=two&body=three")

    assert_raise(URI::InvalidComponentError) do
      uri.compose_fields
    end
    assert_equal(
      "three",
      uri.compose_fields(nil, duplicate_headers: :last)[:body]
    )
    assert_equal(
      "one;two;three",
      uri.compose_fields do |_name, values|
        values.join(";")
      end[:body]
    )
  end

  def test_compose_fields_result_does_not_alias_uri
    source = "mailto:user+label@example.com?Subject=hello+world"
    uri = URI.parse(source)
    fields = uri.compose_fields(["Subject"])

    fields[:to].first << " changed"
    fields[:to] << "changed@example.com"
    fields[:headers]["Subject"] << " changed"
    fields[:body] = "changed"

    assert_equal(source, uri.to_s)
    assert_equal(
      ["user+label@example.com"],
      uri.compose_fields(["Subject"])[:to]
    )
    assert_equal([["Subject", "hello+world"]], uri.headers)
  end

  def test_select
    u = URI.parse('mailto:joe@example.com?cc=bob@example.com&body=hello')
    assert_equal(uri_to_ary(u), u.select(*u.component))
    assert_raise(ArgumentError) do
      u.select(:scheme, :host, :not_exist, :port)
    end
  end
end
