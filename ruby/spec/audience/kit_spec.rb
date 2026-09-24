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
