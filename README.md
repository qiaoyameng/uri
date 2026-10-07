# URI

[![CI](https://github.com/ruby/uri/actions/workflows/test.yml/badge.svg)](https://github.com/ruby/uri/actions/workflows/test.yml)
[![Yard Docs](https://img.shields.io/badge/docs-exist-blue.svg)](https://ruby.github.io/uri/)

URI is a module providing classes to handle Uniform Resource Identifiers [RFC3986](http://tools.ietf.org/html/rfc3986).

## Features

* Uniform way of handling URIs.
* Flexibility to introduce custom URI schemes.
* Flexibility to have an alternate URI::Parser (or just different patterns and regexp's).

## Installation

Add this line to your application's Gemfile:

```ruby
gem 'uri'
```

And then execute:

    $ bundle

Or install it yourself as:

    $ gem install uri

## Usage

```ruby
require 'uri'

uri = URI("http://foo.com/posts?id=30&limit=5#time=1305298413")
#=> #<URI::HTTP http://foo.com/posts?id=30&limit=5#time=1305298413>

uri.scheme    #=> "http"
uri.host      #=> "foo.com"
uri.path      #=> "/posts"
uri.query     #=> "id=30&limit=5"
uri.fragment  #=> "time=1305298413"

uri.to_s      #=> "http://foo.com/posts?id=30&limit=5#time=1305298413"
```

### IPv6 zone identifiers (RFC 6874)

URIs like `http://[fe80::1%25eth0]/` carry an RFC 6874 zone identifier.
This representation is explicitly supported through an optional
compatibility mode; by default such URIs are strictly rejected.

```ruby
parser = URI::RFC3986_Parser.new(rfc6874: true)
uri = parser.parse("http://[fe80::1%25eth0]/")

uri.host        #=> "[fe80::1%25eth0]" (serialized form, for URIs)
uri.hostname    #=> "fe80::1"          (bare IPv6 address)
uri.zone_id     #=> "eth0"             (decoded zone identifier)
uri.scoped_host #=> "fe80::1%eth0"     (scoped form, for socket calls)
```

A URI can also be built from a separate address and zone identifier;
the zone is percent-encoded so it cannot break out of the host
component:

```ruby
URI::HTTP.build(scheme: 'http', host: 'fe80::1', zone_id: 'eth0')
#=> #<URI::HTTP http://[fe80::1%25eth0]>
```

Parsing and serialization are pure string operations: no network
interfaces are queried and no DNS requests are made.

## Development

After checking out the repo, run `bin/setup` to install dependencies. Then, run `rake test` to run the tests. You can also run `bin/console` for an interactive prompt that will allow you to experiment.

To install this gem onto your local machine, run `bundle exec rake install`. To release a new version, update the version number in `version.rb`, and then run `bundle exec rake release`, which will create a git tag for the version, push git commits and tags, and push the `.gem` file to [rubygems.org](https://rubygems.org).

## Contributing

Bug reports and pull requests are welcome on GitHub at https://github.com/ruby/uri.
