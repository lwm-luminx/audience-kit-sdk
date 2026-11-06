# Audience::Kit

Ruby bindings for the AudienceKit API. Requires Ruby 3.2 or newer.

## Installation

Add this line to your application's Gemfile:

```ruby
gem 'audience-kit'
```

And then execute:

    $ bundle install

Or install it yourself as:

    $ gem install audience-kit

## Usage

```ruby
require "audience-kit"

Audience::Kit.configure do |c|
  c.token = ENV["AUDIENCE_KIT_TOKEN"]       # optional bearer token
  c.base_url = "https://api.audiencekit.io" # the default
end

Audience::Kit::Venue.find(1).data # => { "id" => 1, ... }
Audience::Kit::Event.find(42).data
```

HTTP failures raise `Audience::Kit::Error`.

## Development

After checking out the repo, `cd ruby` and run `bin/setup` to install dependencies. Then, run `bundle exec rake` to run the specs and RuboCop. You can also run `bin/console` for an interactive prompt that will allow you to experiment.

To install this gem onto your local machine, run `bundle exec rake install`. The gem keeps its own version in `lib/audience-kit/version.rb`, separate from the Swift and Kotlin SDKs' `VERSION`. To publish it, run `gem build audience-kit.gemspec` and `gem push` the `.gem` to [rubygems.org](https://rubygems.org); don't use `bundle exec rake release`, which would push a bare version tag that the Swift package's release tags share.

## Contributing

Bug reports and pull requests are welcome on GitHub at https://github.com/lwm-luminx/audience-kit-sdk (the gem lives in `ruby/`). This project is intended to be a safe, welcoming space for collaboration, and contributors are expected to adhere to the [code of conduct](https://github.com/lwm-luminx/audience-kit-sdk/blob/main/ruby/CODE_OF_CONDUCT.md).

## License

The gem is available under the [AudienceKit SDK License](LICENSE): use it freely, with the AudienceKit service Love Wins Media operates only.

## Code of Conduct

Everyone interacting in the Audience::Kit project's codebases, issue trackers, chat rooms and mailing lists is expected to follow the [code of conduct](https://github.com/lwm-luminx/audience-kit-sdk/blob/main/ruby/CODE_OF_CONDUCT.md).
