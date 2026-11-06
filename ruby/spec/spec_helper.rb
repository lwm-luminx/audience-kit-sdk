# frozen_string_literal: true

# Coverage starts before the gem loads, or its files count as never run. Every line and branch is covered; CI (which
# sets CI) fails when that drops, while running one spec file locally doesn't.
require "simplecov"
SimpleCov.start do
  enable_coverage :branch
  add_filter "/spec/"
  minimum_coverage line: 100, branch: 100 if ENV["CI"]
end

require "audience-kit"

module ApiHelpers
  def stub_api(stubs)
    Audience::Kit.connection = Faraday.new(url: Audience::Kit.base_url) do |f|
      f.response :json
      f.response :raise_error
      f.adapter :test, stubs
    end
  end
end

RSpec.configure do |config|
  config.include ApiHelpers

  # Enable flags like --only-failures and --next-failure
  config.example_status_persistence_file_path = ".rspec_status"

  # Disable RSpec exposing methods globally on `Module` and `main`
  config.disable_monkey_patching!

  config.expect_with :rspec do |c|
    c.syntax = :expect
  end

  config.after do
    Audience::Kit.base_url = nil
    Audience::Kit.token = nil
    Audience::Kit.connection = nil
  end
end
