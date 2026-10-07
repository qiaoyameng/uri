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
  end

  def test_compose_fields
    uri = URI.parse(
      'mailto:' \
      '%22Doe%2C%20Jane%22%20%3Cjane%2Bwork@example.com%3E,jim%2Blist@example.com' \
      '?to=John%20%22Big%22%20%3Cjohn%2Bops@example.com%3E' \
      '&To=ken%2Bteam@example.com' \
      '&SuBjEcT=Project%20A%2BB' \
      '&subject=Project%20B' \
      '&cc=docs%2Bnotes@example.com' \
      '&body=line1%0D%0Aline2%3A%20subject%3A%20ignored'
    )

    fields = uri.compose_fields(allowed_headers: ['Subject', 'cc'],
                                duplicate_headers: :first)

    assert_equal([
      '"Doe, Jane" <jane+work@example.com>',
      'jim+list@example.com',
      'John "Big" <john+ops@example.com>',
      'ken+team@example.com'
    ], fields[:to])
    assert_equal([
      ['SuBjEcT', 'Project A+B'],
      ['cc', 'docs+notes@example.com']
    ], fields[:headers])
    assert_equal("line1\r\nline2: subject: ignored", fields[:body])
    assert_equal(
      'mailto:%22Doe%2C%20Jane%22%20%3Cjane%2Bwork@example.com%3E,jim%2Blist@example.com' \
      '?to=John%20%22Big%22%20%3Cjohn%2Bops@example.com%3E' \
      '&To=ken%2Bteam@example.com' \
      '&SuBjEcT=Project%20A%2BB' \
      '&subject=Project%20B' \
      '&cc=docs%2Bnotes@example.com' \
      '&body=line1%0D%0Aline2%3A%20subject%3A%20ignored',
      uri.to_s
    )
  end

  def test_compose_fields_only_accepts_allowed_headers
    uri = URI.parse('mailto:jane@example.com?subject=hello&bcc=secret@example.com')

    assert_raise(URI::InvalidComponentError) do
      uri.compose_fields
    end
    assert_raise(URI::InvalidComponentError) do
      uri.compose_fields(allowed_headers: ['subject'])
    end

    subject_uri = URI.parse('mailto:jane@example.com?subject=hello')
    assert_equal([['subject', 'hello']],
                 subject_uri.compose_fields(allowed_headers: ['SUBJECT'])[:headers])
    assert_equal([['subject', 'hello']],
                 subject_uri.compose_fields(['subject'])[:headers])
    assert_equal([['subject', 'hello']],
                 subject_uri.compose_fields(:subject)[:headers])
  end

  def test_compose_fields_duplicate_headers
    uri = URI.parse('mailto:jane@example.com?subject=first&SuBjEcT=second')

    assert_raise(URI::InvalidComponentError) do
      uri.compose_fields(allowed_headers: ['subject'])
    end
    assert_equal([['subject', 'first']],
                 uri.compose_fields(allowed_headers: ['subject'],
                                    duplicate_headers: :first)[:headers])
    assert_equal([['subject', 'second']],
                 uri.compose_fields(allowed_headers: ['subject'],
                                    duplicate_headers: :last)[:headers])
    assert_equal([['subject', 'first'], ['subject', 'second']],
                 uri.compose_fields(allowed_headers: ['subject'],
                                    duplicate_headers: :all)[:headers])
    assert_equal([['subject', ['first', 'second']]],
                 uri.compose_fields(allowed_headers: ['subject'],
                                    duplicate_headers: :array)[:headers])
    fields = uri.compose_fields(allowed_headers: ['subject']) do |_name, values|
      values.join(' / ')
    end
    assert_equal([['subject', 'first / second']], fields[:headers])
  end

  def test_compose_fields_rejects_header_injection
    invalid_uris = [
      'mailto:jane@example.com?subject=a%0d%0abcc%3Asecret',
      'mailto:jane@example.com?subject=a%0abcc%3Asecret',
      'mailto:jane@example.com?to=a%0d%0abcc%3Asecret',
      'mailto:jane@example.com?subject%0d=ignored',
      'mailto:jane@example.com?subject%3A=ignored',
      'mailto:jane@example.com?to=%2540example.com'
    ]

    invalid_uris.each do |source|
      assert_raise(URI::InvalidComponentError, source) do
        URI.parse(source).compose_fields(allowed_headers: ['subject'])
      end
    end

    uri = URI.parse('mailto:jane@example.com?subject=%250d%250a')
    assert_equal([['subject', '%0d%0a']],
                 uri.compose_fields(allowed_headers: ['subject'])[:headers])

    uri = URI.parse('mailto:jane@example.com?subject%0d=ignored')
    field_name_test_uri = Class.new(URI::MailTo) do
      private
      define_method(:permitted_header_names) do |_headers|
        ["subject\r"]
      end
    end.allocate
    field_name_test_uri.instance_variable_set(:@to, uri.to)
    field_name_test_uri.instance_variable_set(:@headers, uri.headers)
    assert_raise(URI::InvalidComponentError) do
      field_name_test_uri.compose_fields(allowed_headers: ['subject'])
    end
  end

  def test_compose_fields_does_not_promote_body_headers
    uri = URI.parse(
      'mailto:jane@example.com?body=hello%0D%0ASubject%3A%20fake%0D%0ABcc%3A%20secret')

    fields = uri.compose_fields(allowed_headers: ['subject'])

    assert_equal([], fields[:headers])
    assert_equal("hello\r\nSubject: fake\r\nBcc: secret", fields[:body])
  end

  def test_compose_fields_returns_independent_values
    uri = URI.parse('mailto:jane%2Bwork@example.com?subject=a%2Bb&body=hello')
    fields = uri.compose_fields(allowed_headers: ['subject'])

    fields[:to] << 'changed@example.com'
    fields[:headers][0][1] << ' changed'
    fields[:body] << ' changed'

    assert_equal('jane+work@example.com', uri.compose_fields(allowed_headers: ['subject'])[:to].first)
    assert_equal('a%2Bb', uri.headers.assoc('subject').last)
    assert_equal('mailto:jane%2Bwork@example.com?subject=a%2Bb&body=hello',
                 uri.to_s)
  end

  def test_select
    u = URI.parse('mailto:joe@example.com?cc=bob@example.com&body=hello')
    assert_equal(uri_to_ary(u), u.select(*u.component))
    assert_raise(ArgumentError) do
      u.select(:scheme, :host, :not_exist, :port)
    end
  end
end
