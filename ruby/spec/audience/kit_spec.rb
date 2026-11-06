# frozen_string_literal: true

RSpec.describe Audience::Kit do
  let(:stubs) { Faraday::Adapter::Test::Stubs.new }

  before { stub_api(stubs) }

  it "has a version number" do
    expect(Audience::Kit::VERSION).not_to be_nil
  end

  it "defaults to the production API" do
    described_class.connection = nil
    expect(described_class.connection.url_prefix.to_s).to eq("https://api.audiencekit.io/")
  end

  it "sends the configured token as a bearer header" do
    described_class.configure { |c| c.token = "secret" }
    expect(described_class.connection.headers["Authorization"]).to eq("Bearer secret")
  end

  describe Audience::Kit::Event do
    it "finds an event by id" do
      stubs.get("/v1/events/42") { [200, { "Content-Type" => "application/json" }, '{"event":{"id":42}}'] }
      expect(described_class.find(42).data).to eq("id" => 42)
    end
  end

  describe Audience::Kit::Venue do
    it "finds a venue by id" do
      stubs.get("/v1/venues/7") { [200, { "Content-Type" => "application/json" }, '{"venue":{"id":7}}'] }
      expect(described_class.find(7).data).to eq("id" => 7)
    end

    it "wraps HTTP failures in Audience::Kit::Error" do
      stubs.get("/v1/venues/0") { [404, {}, ""] }
      expect { described_class.find(0) }.to raise_error(Audience::Kit::Error)
    end
  end
end

RSpec.describe Audience::Kit, ".configure" do
  around do |example|
    saved = ENV.to_h.slice("AUDIENCE_KIT_BASE_URL", "AUDIENCE_KIT_TOKEN")
    example.run
  ensure
    %w[AUDIENCE_KIT_BASE_URL AUDIENCE_KIT_TOKEN].each { |key| ENV.delete(key) }
    ENV.update(saved)
  end

  it "reads the base URL and token from the environment", :aggregate_failures do
    ENV["AUDIENCE_KIT_BASE_URL"] = "https://api.next.audiencekit.io"
    ENV["AUDIENCE_KIT_TOKEN"] = "from-env"

    expect(described_class.connection.url_prefix.to_s).to eq("https://api.next.audiencekit.io/")
    expect(described_class.connection.headers["Authorization"]).to eq("Bearer from-env")
  end

  it "prefers what was configured over the environment", :aggregate_failures do
    ENV["AUDIENCE_KIT_TOKEN"] = "from-env"
    described_class.configure { |c| c.base_url = "https://example.test" }.configure { |c| c.token = "configured" }

    expect(described_class.connection.url_prefix.to_s).to eq("https://example.test/")
    expect(described_class.connection.headers["Authorization"]).to eq("Bearer configured")
  end

  it "sends no Authorization header without a token" do
    ENV.delete("AUDIENCE_KIT_TOKEN")

    expect(described_class.connection.headers).not_to have_key("Authorization")
  end

  it "builds a new connection when reconfigured", :aggregate_failures do
    described_class.configure { |c| c.token = "first" }
    first = described_class.connection
    described_class.configure { |c| c.token = "second" }

    expect(described_class.connection).not_to be(first)
    expect(described_class.connection.headers["Authorization"]).to eq("Bearer second")
  end

  it "returns itself from configure, for chaining" do
    expect(described_class.configure { |c| c.token = "x" }).to be(described_class)
  end
end

RSpec.describe Audience::Kit, ".get" do
  let(:stubs) { Faraday::Adapter::Test::Stubs.new }

  before { stub_api(stubs) }

  it "parses the JSON body" do
    stubs.get("/v1/events/1") do
      [200, { "Content-Type" => "application/json" }, '{"event":{"id":1,"name":"Bingo","tags":["drag"]}}']
    end

    expect(Audience::Kit::Event.find(1).data).to eq("id" => 1, "name" => "Bingo", "tags" => ["drag"])
  end

  it "leaves data nil when the response has no record" do
    stubs.get("/v1/venues/3") { [200, { "Content-Type" => "application/json" }, "{}"] }

    expect(Audience::Kit::Venue.find(3).data).to be_nil
  end

  it "wraps server errors, keeping Faraday's message" do
    stubs.get("/v1/events/5") { [500, {}, "boom"] }

    expect { Audience::Kit::Event.find(5) }.to raise_error(Audience::Kit::Error, /500/)
  end

  it "wraps unauthorized responses" do
    stubs.get("/v1/venues/9") { [401, {}, ""] }

    expect { Audience::Kit::Venue.find(9) }.to raise_error(Audience::Kit::Error)
  end

  it "wraps network failures" do
    stubs.get("/v1/venues/1") { raise Faraday::ConnectionFailed, "connection refused" }

    expect { Audience::Kit::Venue.find(1) }.to raise_error(Audience::Kit::Error, "connection refused")
  end

  it "asks for the record by its id" do
    stubs.get("/v1/venues/abc-123") { [200, { "Content-Type" => "application/json" }, '{"venue":{"id":"abc-123"}}'] }

    Audience::Kit::Venue.find("abc-123")

    expect { stubs.verify_stubbed_calls }.not_to raise_error
  end
end
