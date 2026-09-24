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

After checking out the repo, run `bin/setup` to install dependencies. Then, run `bundle exec rake` to run the specs and RuboCop. You can also run `bin/console` for an interactive prompt that will allow you to experiment.

To install this gem onto your local machine, run `bundle exec rake install`. To release a new version, update the version number in `version.rb`, and then run `bundle exec rake release`, which will create a git tag for the version, push git commits and the created tag, and push the `.gem` file to [rubygems.org](https://rubygems.org).

## Contributing

Bug reports and pull requests are welcome on GitHub at https://github.com/audience-kit/audience-kit-sdk-ruby. This project is intended to be a safe, welcoming space for collaboration, and contributors are expected to adhere to the [code of conduct](https://github.com/audience-kit/audience-kit-sdk-ruby/blob/main/CODE_OF_CONDUCT.md).

## License

The gem is available as open source under the terms of the [MIT License](https://opensource.org/licenses/MIT).

## Code of Conduct

Everyone interacting in the Audience::Kit project's codebases, issue trackers, chat rooms and mailing lists is expected to follow the [code of conduct](https://github.com/audience-kit/audience-kit-sdk-ruby/blob/main/CODE_OF_CONDUCT.md).
