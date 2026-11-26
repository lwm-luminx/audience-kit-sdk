# frozen_string_literal: true

# Coverage starts before the gem loads, or its files count as never run. CI (which sets CI) fails when it drops
# below the floor; running one spec file locally doesn't.
require "simplecov"
SimpleCov.start do
  enable_coverage :branch
  add_filter "/spec/"
  add_filter "/examples/"
  minimum_coverage line: 100, branch: 100 if ENV["CI"]
end

require "audience-kit"

# A stand-in for the Faraday connection a Session sends through: answers each request from the routes the spec
# gives, in order, and records what was sent.
class FakeHTTP
  Response = Struct.new(:status, :body) do
    def success? = status.between?(200, 299)
  end
  Sent = Struct.new(:verb, :url, :body, :headers) do
    def json = body && JSON.parse(body)
    def path = URI.parse(url).path
    def query = URI.decode_www_form(URI.parse(url).query.to_s).to_h
  end

  attr_reader :sent

  def initialize
    @routes = []
    @sent = []
  end

  # Answers the next request for +method+ and a path matching +path+ with +status+ and +body+ (a Hash or Array is
  # sent as JSON; a block gets the request and returns [status, body]).
  def on(method, path, status = 200, body = {}, &block)
    @routes << [method, path, block || ->(_) { [status, body] }]
    self
  end

  def run_request(method, url, body, headers)
    request = Sent.new(method, url, body, headers)
    @sent << request
    index = @routes.index { |m, path, _| m == method && path === URI.parse(url).path } # rubocop:disable Style/CaseEquality
    raise "No route for #{method.upcase} #{url}" if index.nil?

    status, payload = @routes.delete_at(index).last.call(request)
    Response.new(status, payload.is_a?(String) ? payload : JSON.generate(payload))
  end

  def graphql_bodies = sent.select { |r| r.path.end_with?("/graphql") }.map(&:json)
end

module SessionHelpers
  AUDIENCE_ID = "aud-1"
  BASE = "https://api.test"

  def http
    @http ||= FakeHTTP.new
  end

  def configuration(**)
    Audience::Kit::Configuration.new(base_url: BASE, audience_id: AUDIENCE_ID, **)
  end

  def credential(**)
    Audience::Kit::Credential.new(token: "jwt", endpoint: "#{BASE}/v1/audience/#{AUDIENCE_ID}/graphql",
                                  user_id: "u1", audience_id: AUDIENCE_ID, **)
  end

  def device = Audience::Kit::DeviceDescription.new(identifier: "server-1")

  def signed_in_session(**)
    session = Audience::Kit::Session.new(configuration: configuration(**), http: http)
    session.adopt(credential)
    session
  end

  # Answers the next GraphQL request with +data+.
  def answer(data = {}, &block)
    http.on(:post, %r{/graphql\z}, &block || ->(_) { [200, { "data" => data }] })
  end

  def undefined_field
    [200, { "errors" => [{ "message" => "Field 'x' doesn't exist", "extensions" => { "code" => "undefinedField" } }] }]
  end

  def credential_json(**fields)
    { "token" => "jwt2", "userId" => "u1", "audienceId" => AUDIENCE_ID, "role" => "member",
      "endpoint" => "#{BASE}/v1/audience/#{AUDIENCE_ID}/graphql" }.merge(fields.transform_keys(&:to_s))
  end
end

RSpec.configure do |config|
  config.include SessionHelpers
  config.example_status_persistence_file_path = ".rspec_status"
  config.disable_monkey_patching!
  config.expect_with(:rspec) { |c| c.syntax = :expect }
  config.after { Audience::Kit.reset! }
end
