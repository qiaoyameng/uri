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

### Scoped IPv6 addresses (RFC 6874)

URIs of scoped (link-local) IPv6 addresses carry a zone identifier such
as an interface name, represented as `http://[fe80::1%25eth0]/` per
[RFC 6874](https://www.rfc-editor.org/rfc/rfc6874).  This representation
is not part of strict RFC 3986, so it is supported through an opt-in
parser:

```ruby
uri = URI.parse("http://[fe80::1%25eth0]/", parser: URI::RFC6874_PARSER)
uri.host             #=> "[fe80::1%25eth0]" # host used for URI serialization
uri.hostname         #=> "fe80::1"         # bracket-less IPv6 address
uri.zone             #=> "eth0"            # decoded zone identifier
uri.scoped_hostname  #=> "fe80::1%eth0"    # form suitable for socket calls
```

The address and zone can also be supplied separately to a constructor:

```ruby
URI::HTTP.build(host: "[fe80::1]", zone: "eth0").to_s
#=> "http://[fe80::1%25eth0]"
```

Parsing never queries network interfaces or performs DNS resolution, and
the default parser keeps rejecting this form unless RFC 6874 support is
enabled.

## Development

After checking out the repo, run `bin/setup` to install dependencies. Then, run `rake test` to run the tests. You can also run `bin/console` for an interactive prompt that will allow you to experiment.

To install this gem onto your local machine, run `bundle exec rake install`. To release a new version, update the version number in `version.rb`, and then run `bundle exec rake release`, which will create a git tag for the version, push git commits and tags, and push the `.gem` file to [rubygems.org](https://rubygems.org).

## Contributing

Bug reports and pull requests are welcome on GitHub at https://github.com/ruby/uri.
