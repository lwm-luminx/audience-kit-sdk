# frozen_string_literal: true

RSpec.describe Audience::Kit do
  it "has versions and a client header" do
    expect(described_class::VERSION).to match(/\A\d+\.\d+\.\d+\z/)
    expect(described_class.client_header).to eq("AudienceKit-Ruby/#{described_class::VERSION}")
    expect(described_class.older?("99.0", "0.3.0")).to be(true)
    expect(described_class.older?("0.3", "0.3.0")).to be(false)
    expect(described_class.older?("0.2.9")).to be(false)
  end

  describe "the module-level session" do
    around do |example|
      saved = ENV.to_h.slice("AUDIENCEKIT_TOKEN", "AUDIENCE_KIT_TOKEN", "AUDIENCEKIT_HOST")
      %w[AUDIENCEKIT_TOKEN AUDIENCE_KIT_TOKEN AUDIENCEKIT_HOST].each { |name| ENV.delete(name) }
      example.run
    ensure
      ENV.update(saved)
    end

    it "is configured in a block" do
      described_class.configure do |c|
        c.token = "key"
        c.base_url = "https://api.test"
        c.audience_id = "aud-1"
        c.host = "h"
      end
      expect(described_class.session.session_token).to eq("key")
      expect(described_class.session.configuration).to have_attributes(base_url: "https://api.test", audience_id: "aud-1", host: "h")
    end

    it "reads the environment, including the 0.2 names" do
      ENV["AUDIENCE_KIT_TOKEN"] = "old"
      expect(described_class.token).to eq("old")
      expect(described_class.base_url).to eq("https://api.audiencekit.com")
      expect(described_class.host).to be_nil
      ENV["AUDIENCEKIT_TOKEN"] = "akst_new"
      expect(described_class.session).not_to be_signed_in
    end

    it "runs documents" do
      described_class.session = signed_in_session
      answer("locales" => [])
      expect(described_class.query("query { locales { id } }", { "a" => 1 })).to eq("locales" => [])
    end
  end

  describe Audience::Kit::Credential do
    let(:json) { credential_json(expiresAt: "2026-11-26T20:00:00.000Z", scopes: ["public:read", 1], audience: "Hot Mess", role: "service") }

    it "round-trips the API's JSON" do
      credential = described_class.from_h(json)
      expect(credential).to have_attributes(service?: true, expires_at: Time.utc(2026, 11, 26, 20), scopes: ["public:read"])
      expect(credential).to be_scope("public:read")
      expect(described_class.from_h(credential.to_h)).to eq(credential)
      expect(credential.to_h).to include("expiresAt" => "2026-11-26T20:00:00.000Z", "audience" => "Hot Mess")
      expect(described_class.from_h("token" => "t", "endpoint" => "e").to_h).not_to have_key("scopes")
      expect(credential.to_s).to include("token=[REDACTED]")
    end

    it "knows when it expires" do
      credential = described_class.from_h(json)
      expect(credential.expired?(Time.utc(2026, 11, 26, 21))).to be(true)
      expect(credential.expires_within?(60, Time.utc(2026, 11, 26, 19, 59, 30))).to be(true)
      expect(credential.expires_within?(60, Time.utc(2026, 11, 26, 19))).to be(false)
      forever = described_class.new(token: "t", endpoint: "e")
      expect([forever.expired?, forever.expires_within?(60)]).to eq([false, false])
    end

    it "refuses malformed credentials" do
      expect { described_class.from_h("token" => "t") }.to raise_error(ArgumentError, /no endpoint/)
      expect { described_class.from_h(credential_json(expiresAt: 5)) }.to raise_error(ArgumentError, /ISO 8601/)
      expect { described_class.from_h(credential_json(expiresAt: "soon")) }.to raise_error(ArgumentError, /ISO 8601/)
    end

    it "names the instance that issued it" do
      expect(described_class.new(token: "t", endpoint: "https://api.test/v1/graphql").origin).to eq("https://api.test")
      expect(described_class.new(token: "t", endpoint: "http://localhost:3000/x").origin).to eq("http://localhost:3000")
      expect(described_class.new(token: "t", endpoint: "/relative").origin).to be_nil
      expect(described_class.new(token: "t", endpoint: "http://[bad").origin).to be_nil
    end
  end

  describe Audience::Kit::Configuration do
    it "sends a credential to the instance that issued it, unless trusted" do
      other = credential(endpoint: "https://other.test/v1/audience/a/graphql")
      expect(configuration.api_base(nil)).to eq("https://api.test")
      expect(configuration.api_base(other)).to eq("https://other.test")
      trusting = configuration(trusted_credential_origins: ["HTTPS://OTHER.TEST:443"])
      expect(trusting.api_base(other)).to eq("https://api.test")
      expect(described_class.same_origin?("http://[bad", "https://x")).to be(false)
    end
  end

  describe Audience::Kit::SessionCredentialStore do
    it "keeps the credential in a session hash" do
      session = {}
      store = described_class.new(session)
      store.save(credential)
      expect(session["audiencekit.credential"]).to include("token" => "jwt")
      expect(store.load).to eq(credential)
      session["audiencekit.credential"] = { token: "t", endpoint: "e" }
      expect(store.load.token).to eq("t")
      session["audiencekit.credential"] = { "token" => "t" }
      expect(store.load).to be_nil
      store.delete
      expect(store.load).to be_nil
    end

    it "is the interface stores follow" do
      store = Object.new.extend(Audience::Kit::CredentialStore)
      expect { store.load }.to raise_error(NotImplementedError)
      expect { store.save(nil) }.to raise_error(NotImplementedError)
      expect { store.delete }.to raise_error(NotImplementedError)
    end
  end

  describe Audience::Kit::Coordinate do
    it "parses and writes WKT" do
      expect(described_class.from_wkt("POINT(-112.07 33.45)").latitude).to eq(33.45)
      expect(described_class.from_wkt("POINT (33.45 -112.07)")).to be_nil
      expect(described_class.from_wkt("LINESTRING (1 2, 3 4)")).to be_nil
      expect(described_class.from_wkt("POINT (1.2.3 4)")).to be_nil
      expect(described_class.new(latitude: -0.0, longitude: 1).to_wkt).to eq("POINT (1 0)")
    end

    it "measures distance and leaves out an empty beacon" do
      phoenix = described_class.new(latitude: 33.4484, longitude: -112.074)
      tucson = described_class.new(latitude: 32.2226, longitude: -110.9747, beacon_major: 0, beacon_minor: 3)
      expect(phoenix.distance_to(tucson)).to be_within(1000).of(170_000)
      expect(tucson.to_input).to eq("latitude" => 32.2226, "longitude" => -110.9747, "beaconMinor" => 3)
    end
  end

  describe Audience::Kit::Color do
    it "parses hex and themes" do
      expect(described_class.from_hex("#abc").to_hex).to eq("#aabbcc")
      expect(described_class.from_hex("11223380").to_css).to eq("rgba(17, 34, 51, 0.502)")
      expect(described_class.from_hex("11223380").to_hex).to eq("#11223380")
      expect(described_class.from_hex("#12")).to be_nil
      theme = { "light" => { "accent" => "#000000" }, "dark" => [{ "name" => "accent", "value" => "#ffffff" }] }
      expect(described_class.from_theme(theme, "accent").to_hex).to eq("#000000")
      expect(described_class.from_theme(theme, "accent", dark: true).to_hex).to eq("#ffffff")
      expect(described_class.from_theme(theme, "other", dark: true)).to be_nil
      expect(described_class.from_theme({ "light" => "x" }, "accent")).to be_nil
      expect(described_class.from_theme(nil, "accent")).to be_nil
      expect(described_class.new(red: 2, green: -1, blue: 0.5).to_css).to eq("rgba(255, 0, 128, 1)")
    end
  end

  describe Audience::Kit::CoverPass do
    it "makes door codes that change every 30 seconds" do
      code = described_class.code("a1", "c2VjcmV0", 59)
      expect(code).to match(/\AHMC1\.a1\.1\.[\w-]{16}\z/)
      expect(code).to eq(described_class.code("a1", "c2VjcmV0", 31))
      expect(code).not_to eq(described_class.code("a1", "c2VjcmV0", 60))
      expect(described_class.code("a1", "c2VjcmV0")).to start_with("HMC1.a1.#{Time.now.to_i / 30}")
      expect(described_class.seconds_until_next_window(59)).to eq(1)
      expect(described_class.code?(code)).to be(true)
      expect(described_class.code?("HMC1..1.x")).to be(false)
    end

    it "matches the other SDKs' signature" do
      # HMAC-SHA256("a1.1", "secret"), URL-safe Base64, first 16 characters.
      expected = [OpenSSL::HMAC.digest("SHA256", "secret", "a1.1")].pack("m0").tr("+/", "-_")[0, 16]
      expect(described_class.signature("a1", "c2VjcmV0", 1)).to eq(expected)
    end
  end

  describe Audience::Kit::Error do
    it "classifies GraphQL errors" do
      error = described_class.graphql([Audience::Kit::GraphQLError.from_h("message" => "x", "extensions" => { "code" => "undefinedField" })])
      expect(error).to be_undefined_field
      expect(error).not_to be_unauthenticated
      expect(described_class.graphql([]).message).to eq("The request failed.")
      expect(Audience::Kit::GraphQLError.from_h(nil).code).to be_nil
    end
  end

  describe Audience::Kit::Queries do
    it "builds documents for what an audience has" do
      none = Audience::Kit::SchemaShape.new({})
      expect(described_class.articles(none)).to eq("query Articles { id }\n")
      %i[articles_page national_articles article publications publication my_op_eds].each do |name|
        expect(described_class.public_send(name, none)).to match(/\Aquery \w+ \{ id \}\n\z/)
      end
      expect(described_class.venue_offers(none)).not_to include("$night")
      expect(described_class.venue_detail(none)).not_to include("$recentMessages")
      expect(described_class.people(none)).not_to include("venues {")
      expect(described_class.event_fields(none)).not_to include("rsvp")
      expect(described_class.articles_about("venue").last.call(none)).to eq("query ArticlesAbout { id }\n")
      expect { described_class.articles_about("photo") }.to raise_error(ArgumentError)
      expect(described_class.article_fields(Audience::Kit::SchemaShape.everything)).to include("adFreeOffered", "viewerAdFree")
    end

    it "builds documents for an audience with some modules" do
      shape = Audience::Kit::SchemaShape.new(
        "Venue" => %w[tickets profile chat events], "Event" => %w[venue rsvp people tickets], "Person" => %w[venues events],
        "Locale" => %w[profile], "Audience" => %w[soapbox], "EventSeries" => %w[venue]
      )
      documents = %i[venues people locales venue_cover venue_offers events event_series venue_detail articles
                     publications].map { |name| described_class.public_send(name, shape) }.join
      expect(documents).not_to include("jockeys", "places", "friends", "VenueTickets", "viewerAdFree", "facebook", "coatCheck")
      expect(documents).to include("people { hosts", "tickets { offers(night: $night)")
      bare = Audience::Kit::SchemaShape.new("Person" => %w[events])
      expect(described_class.people(bare) + described_class.event_series(bare)).not_to include("venue {")
    end

    it "names every document after its operation" do
      described_class.all.each do |name, document|
        expect(document).to match(/\A(query|mutation|subscription) #{name}\b/)
      end
      expect(described_class.chat_room(:locale, watch: true)).to include("room: localeChat(localeId: $id, watch: true)")
    end
  end
end
