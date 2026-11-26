# frozen_string_literal: true

RSpec.describe Audience::Kit::Session do
  let(:session) { described_class.new(configuration: configuration(host: "hotmess.social", facebook_app_id: "fb1"), http: http) }

  describe "signing in" do
    it "trades a Facebook token with the host, app and device" do
      http.on(:post, "/v1/token", 200, credential_json)
      result = session.sign_in_with_facebook_token("fb-token", device: device)
      expect(result.token).to eq("jwt2")
      expect(session).to be_signed_in
      expect(http.sent.last.json).to eq("facebook_token" => "fb-token", "host" => "hotmess.social",
                                        "facebook_app_id" => "fb1",
                                        "device" => { "identifier" => "server-1", "type" => "web" })
      expect(http.sent.last.headers).not_to have_key("Authorization")
      expect(http.sent.last.headers).to include("X-AudienceKit-API-Version" => Audience::Kit::API_VERSION,
                                                "X-AudienceKit-Client" => "AudienceKit-Ruby/#{Audience::Kit::VERSION}")
    end

    it "trades a Facebook code, with another app when given" do
      http.on(:post, "/v1/token", 200, credential_json)
      session.sign_in_with_facebook_code("c", redirect_uri: "https://x/cb", device: device, facebook_app_id: "fb2")
      expect(http.sent.last.json).to include("code" => "c", "redirect_uri" => "https://x/cb", "facebook_app_id" => "fb2")
    end

    it "trades Google, Apple and review-code logins" do
      3.times { |i| http.on(:post, %r{/v1/token/(google|apple|review)}, 200, credential_json(token: "t#{i}")) }
      session.sign_in_with_google("id", device: device, name: "Pat")
      session.sign_in_with_apple("idt", device: device, nonce: "n", first_name: "Pat")
      session.sign_in_with_review_code(" 1234 ", device: device)
      expect(http.sent.map(&:path)).to eq(%w[/v1/token/google /v1/token/apple /v1/token/review])
      expect(http.sent[0].json).to include("id_token" => "id", "name" => "Pat", "host" => "hotmess.social")
      expect(http.sent[1].json).to include("identity_token" => "idt", "nonce" => "n", "first_name" => "Pat")
      expect(http.sent[1].json).not_to have_key("last_name")
      expect(http.sent[2].json).to include("code" => "1234")
      expect(session.session_token).to eq("t2")
      expect(described_class.new(http: http).session_token).to be_nil
    end

    it "connects Google and Facebook to the signed-in account with its token" do
      session.adopt(credential)
      http.on(:post, "/v1/token/google", 200, credential_json).on(:post, "/v1/token", 200, credential_json)
      session.connect_google("id", device: device)
      session.connect_facebook("code", redirect_uri: "https://x/cb", device: device)
      expect(http.sent.map { |r| r.headers["Authorization"] }).to eq(["Bearer jwt", "Bearer jwt2"])
      expect(http.sent.map { |r| r.json["connect"] }).to eq([true, true])
    end

    it "needs a session to connect a provider" do
      expect { session.connect_google("id", device: device) }
        .to raise_error(Audience::Kit::Error) { |e| expect(e.code).to eq("NOT_SIGNED_IN") }
    end

    it "reports a refused login" do
      http.on(:post, "/v1/token", 401, {})
      expect { session.sign_in_with_facebook_token("bad", device: device) }
        .to raise_error(Audience::Kit::Error) { |e| expect(e.code).to eq("SIGN_IN_REJECTED") }
    end

    it "reports a failed login with the API's message" do
      http.on(:post, "/v1/token", 400, { "fault" => { "message" => "Email taken" } })
      expect { session.sign_in_with_facebook_token("x", device: device) }
        .to raise_error(Audience::Kit::Error) { |e| expect([e.code, e.message]).to eq(["SIGN_IN_FAILED", "Email taken"]) }
    end

    it "reports an API version the API no longer serves" do
      http.on(:post, "/v1/token", 400, { "error" => "unsupported_api_version", "supported" => ["2027-01-01"] })
      expect { session.sign_in_with_facebook_token("x", device: device) }.to raise_error(Audience::Kit::Error) do |e|
        expect(e.code).to eq("UNSUPPORTED_API_VERSION")
        expect(e.message).to end_with("(API versions served: 2027-01-01.)")
      end
    end

    it "reports other failures and undecodable credentials" do
      http.on(:post, "/v1/token", 500, "oops").on(:post, "/v1/token", 200, { "token" => "t" })
          .on(:post, "/v1/token", 200, "[]")
      expect { session.sign_in_with_facebook_token("x", device: device) }
        .to raise_error(Audience::Kit::Error) { |e| expect([e.code, e.status]).to eq(["INTERNAL", 500]) }
      expect { session.sign_in_with_facebook_token("x", device: device) }
        .to raise_error(Audience::Kit::Error) { |e| expect(e.code).to eq("DECODING") }
      expect { session.sign_in_with_facebook_token("x", device: device) }
        .to raise_error(Audience::Kit::Error, /not a JSON object/)
    end

    it "reports a store that can't save" do
      store = Audience::Kit::MemoryCredentialStore.new
      def store.save(_) = raise(IOError, "disk full")
      session = described_class.new(configuration: configuration, store: store, http: http)
      http.on(:post, "/v1/token", 200, credential_json)
      expect { session.sign_in_with_facebook_token("x", device: device) }
        .to raise_error(Audience::Kit::Error) { |e| expect([e.code, e.message]).to eq(["STORAGE", "The session couldn't be saved. disk full"]) }
    end

    it "treats an unreadable store as signed out" do
      store = Audience::Kit::MemoryCredentialStore.new
      def store.load = raise(IOError)
      expect(described_class.new(configuration: configuration, store: store, http: http)).not_to be_signed_in
    end
  end

  describe "tokens" do
    it "sends an API key as is" do
      session.use_bearer_token("key")
      answer("id" => "aud-1", "name" => "Hot Mess")
      expect(session.audience.name).to eq("Hot Mess")
      expect(session.credential.role).to eq("bearer")
      expect(http.sent.last.url).to eq("https://api.test/v1/audience/aud-1/graphql")
      expect(http.sent.last.headers["Authorization"]).to eq("Bearer key")
    end

    it "trades a service token, renews it before it expires and retries once when refused" do
      soon = (Time.now + 30).utc.iso8601
      later = (Time.now + 3600).utc.iso8601
      http.on(:post, "/v1/token/service", 200, credential_json(token: "s1", role: "service", userId: nil, expiresAt: soon))
          .on(:post, "/v1/token/service", 200, credential_json(token: "s2", role: "service", userId: nil, expiresAt: later))
          .on(:get, "/v1/public/listings", 401, {})
          .on(:post, "/v1/token/service", 200, credential_json(token: "s3", role: "service", userId: nil, expiresAt: later))
          .on(:get, "/v1/public/listings", 200, { "listings" => [] })
      expect(session.use_service_token("akst_a_b").token).to eq("s1")
      expect(http.sent.first.json).to eq("service_token" => "akst_a_b")
      session.public_listings_page
      expect(http.sent.select { |r| r.path == "/v1/public/listings" }.map { |r| r.headers["Authorization"] })
        .to eq(["Bearer s2", "Bearer s3"])
    end

    it "forgets a revoked service token" do
      http.on(:post, "/v1/token/service", 403, {})
      expect { session.use_service_token("akst_x") }
        .to raise_error(Audience::Kit::Error) { |e| expect([e.code, e.status]).to eq(["UNAUTHENTICATED", 403]) }
      expect { session.request("/v1/public/listings") }.to raise_error(Audience::Kit::Error, /not signed in/)
    end

    it "reports a service token exchange that failed" do
      http.on(:post, "/v1/token/service", 503, {})
      expect { session.use_service_token("akst_x") }.to raise_error(Audience::Kit::Error) { |e| expect(e.status).to eq(503) }
    end

    it "follows a service session to the instance that issued it" do
      http.on(:post, "/v1/token/service", 200,
              credential_json(role: "service", endpoint: "https://other.test:8443/v1/audience/aud-1/graphql"))
          .on(:get, "/v1/public/listings", 200, { "listings" => [] })
      session.use_service_token("akst_x")
      session.public_listings_page
      expect(http.sent.last.url).to start_with("https://other.test:8443/v1/public/listings")
    end
  end

  describe ".from_env and .build" do
    it "reads a service token and the configuration" do
      env = { "AUDIENCEKIT_TOKEN" => "akst_1", "AUDIENCEKIT_BASE_URL" => SessionHelpers::BASE, "AUDIENCEKIT_HOST" => "h",
              "AUDIENCEKIT_AUDIENCE_ID" => "", "AUDIENCEKIT_ENVIRONMENT" => "staging" }
      session = described_class.from_env(env, http: http)
      expect(session.configuration).to have_attributes(base_url: SessionHelpers::BASE, host: "h", audience_id: nil, environment: "staging")
      expect(session).not_to be_signed_in
      http.on(:post, "/v1/token/service", 200, credential_json(role: "service")).on(:get, "/v1/public/listings", 200, {})
      session.public_listings_page
      expect(http.sent.first.headers["X-AudienceKit-Environment"]).to eq("staging")
    end

    it "uses any other token as a bearer token, and defaults to production" do
      session = described_class.from_env({ "AUDIENCEKIT_TOKEN" => "key" })
      expect(session.session_token).to eq("key")
      expect(session.configuration.base_url).to eq("https://api.audiencekit.com")
      expect(described_class.from_env({})).not_to be_signed_in
    end
  end

  describe "#sign_out" do
    it "forgets the credential and revokes the token" do
      session.adopt(credential)
      http.on(:delete, "/v1/token", 204, "")
      session.sign_out
      expect(session).not_to be_signed_in
      expect(http.sent.last.headers["Authorization"]).to eq("Bearer jwt")
    end

    it "accepts a session that was already gone, and does nothing when signed out" do
      session.adopt(credential)
      http.on(:delete, "/v1/token", 401, {})
      session.sign_out
      session.sign_out
      expect(http.sent.size).to eq(1)
    end

    it "reports a revocation that failed, after forgetting the credential" do
      session.adopt(credential)
      http.on(:delete, "/v1/token", 500, {})
      expect { session.sign_out }.to raise_error(Audience::Kit::Error)
      expect(session).not_to be_signed_in
    end

    it "forgets even when the store can't delete" do
      store = Audience::Kit::MemoryCredentialStore.new(credential)
      def store.delete = raise(IOError)
      session = described_class.new(configuration: configuration, store: store, http: http)
      http.on(:delete, "/v1/token", 200, {})
      expect { session.sign_out }.not_to raise_error
    end
  end

  describe "account" do
    before { session.adopt(credential) }

    it "refreshes, switches audience and deletes the account" do
      http.on(:post, "/v1/token/refresh", 200, credential_json(token: "r"))
          .on(:post, "/v1/admin/choices", 200, credential_json(token: "s", audienceId: "aud-2"))
      expect(session.refresh_session.token).to eq("r")
      expect(session.switch_audience("aud-2").audience_id).to eq("aud-2")
      expect(http.sent.last.json).to eq("audience_id" => "aud-2")
      answer("deleteAccount" => { "deleted" => false })
      expect(session.delete_account).to be(false)
      expect(session).to be_signed_in
      answer("deleteAccount" => { "deleted" => true })
      expect(session.delete_account).to be(true)
      expect(session).not_to be_signed_in
    end

    it "ends a session rejected elsewhere once" do
      expect(session.session_rejected("other")).to be(false)
      expect(session.session_rejected(nil)).to be(false)
      expect(session.session_rejected("jwt")).to be(true)
      expect(session.session_rejected("jwt")).to be(false)
    end

    it "forgets a person's session the API refused" do
      answer { [401, {}] }
      expect { session.me }.to raise_error(Audience::Kit::Error, &:unauthenticated?)
      expect(session).not_to be_signed_in
    end
  end

  describe "the audience" do
    let(:session) { described_class.new(configuration: Audience::Kit::Configuration.new(base_url: SessionHelpers::BASE, host: "hotmess.social"), http: http) }

    it "reads branding and works out the audience ID from it once" do
      http.on(:get, "/v1/branding", 200, { "audience" => { "id" => "aud-9" } })
      expect(session.audience_id).to eq("aud-9")
      expect(session.audience_id).to eq("aud-9")
      expect(http.sent.size).to eq(1)
      expect(http.sent.first.query).to eq("host" => "hotmess.social")
      http.on(:get, "/v1/branding", 200, {})
      session.branding(host: "x", app: "com.app")
      expect(http.sent.last.query).to eq("host" => "x", "app" => "com.app")
    end

    it "needs an audience ID or a host" do
      session = described_class.new(configuration: Audience::Kit::Configuration.new, http: http)
      expect { session.audience_id }.to raise_error(Audience::Kit::Error) { |e| expect(e.code).to eq("MISSING_CONFIGURATION") }
      expect { session.branding }.to raise_error(Audience::Kit::Error, /needs a host/)
    end

    it "reports branding without an audience" do
      http.on(:get, "/v1/branding", 200, { "audience" => {} })
      expect { session.audience_id }.to raise_error(Audience::Kit::Error, /no audience id/)
    end
  end

  describe "#graphql" do
    before { session.adopt(credential) }

    it "sends the document, variables and operation headers" do
      answer("ok" => true)
      expect(session.graphql("mutation Go($a: Int) { ok }", { "a" => 1 })).to eq("ok" => true)
      expect(http.sent.last.json).to eq("query" => "mutation Go($a: Int) { ok }", "variables" => { "a" => 1 })
      expect(http.sent.last.headers).to include("X-APOLLO-OPERATION-TYPE" => "mutation", "X-APOLLO-OPERATION-NAME" => "Go",
                                                "Content-Type" => "application/json")
    end

    it "raises the first error, with INVALID fields" do
      answer { [200, { "errors" => [{ "message" => "Bad", "path" => ["x"], "extensions" => { "code" => "INVALID", "fields" => { "name" => ["is blank"], "age" => "too low" } } }], "data" => nil }] }
      expect { session.graphql("{ x }") }.to raise_error(Audience::Kit::Error) do |e|
        expect([e.code, e.message, e.fields]).to eq(["INVALID", "Bad", { "name" => ["is blank"], "age" => ["too low"] }])
        expect(e.errors.first.path).to eq(["x"])
      end
    end

    it "raises GRAPHQL for an error without a code, and DECODING without data" do
      answer { [200, { "errors" => ["odd"] }] }
      answer { [200, { "data" => "no" }] }
      expect { session.graphql("{ x }") }.to raise_error(Audience::Kit::Error) { |e| expect([e.code, e.message]).to eq(["GRAPHQL", "The request failed."]) }
      expect { session.graphql("{ x }") }.to raise_error(Audience::Kit::Error) { |e| expect(e.code).to eq("DECODING") }
    end

    it "reports a response that isn't JSON" do
      answer { [200, "<html>"] }
      expect { session.graphql("{ x }") }.to raise_error(Audience::Kit::Error) { |e| expect(e.code).to eq("DECODING") }
    end
  end

  describe "#shaped_graphql" do
    before { session.adopt(credential) }

    it "asks again with the audience's fields when one is undefined, then remembers them" do
      answer { undefined_field }
      answer("t0" => { "fields" => [{ "name" => "a" }, "junk"] }, "t1" => nil)
      answer("ok" => 1)
      answer("ok" => 2)
      build = ->(shape) { shape.has?("A", "b") ? "{ a b }" : "{ a }" }
      expect(session.shaped_graphql(%w[B A], nil, "Op", &build)).to eq("ok" => 1)
      expect(session.shaped_graphql(%w[A B], nil, "Op", &build)).to eq("ok" => 2)
      expect(http.graphql_bodies.map { |b| b["query"] }).to eq(["{ a b }", http.graphql_bodies[1]["query"], "{ a }", "{ a }"])
      expect(http.graphql_bodies[1]["query"]).to include('t0: __type(name: "A")', 't1: __type(name: "B")')
      expect(session.schema_fields(%w[A B])).to eq("A" => ["a"])
    end

    it "passes on other errors" do
      answer { [200, { "errors" => [{ "message" => "no", "extensions" => { "code" => "FORBIDDEN" } }] }] }
      expect { session.shaped_graphql(["A"], nil, "Op") { "{ a }" } }.to raise_error(Audience::Kit::Error) { |e| expect(e.code).to eq("FORBIDDEN") }
    end

    it "has no cached fields without an audience" do
      session = described_class.new(configuration: Audience::Kit::Configuration.new, http: http)
      expect(session.cached_schema_fields(["A"])).to be_nil
    end
  end

  describe "#request" do
    before { session.adopt(credential) }

    {
      403 => %w[FORBIDDEN Nope], 404 => %w[NOT_FOUND Nope], 409 => %w[CONFLICT Nope], 422 => %w[INVALID Nope],
      429 => %w[RATE_LIMITED Nope], 418 => %w[HTTP Nope], 400 => %w[INVALID Nope]
    }.each do |status, (code, message)|
      it "maps HTTP #{status} to #{code}" do
        http.on(:get, "/v1/x", status, { "message" => "Nope" })
        expect { session.request("/v1/x") }.to raise_error(Audience::Kit::Error) { |e| expect([e.code, e.message, e.status]).to eq([code, message, status]) }
      end
    end

    it "passes the API's own code through and fills in messages" do
      http.on(:get, "/v1/x", 400, { "error" => "too_soon" }).on(:get, "/v1/x", 502, "bad gateway")
          .on(:get, "/v1/x", 426, { "minimum_sdk_version" => "0.4.0" }).on(:get, "/v1/x", 400, { "error" => "unsupported_api_version", "message" => "Old" })
          .on(:get, "/v1/x", 403, { "message" => 5 }).on(:get, "/v1/x", 404, "[1]")
      expect { session.request("/v1/x") }.to raise_error(Audience::Kit::Error) { |e| expect(e.code).to eq("TOO_SOON") }
      expect { session.request("/v1/x") }.to raise_error(Audience::Kit::Error) { |e| expect([e.code, e.message]).to eq(["INTERNAL", "The server responded with status 502."]) }
      expect { session.request("/v1/x") }.to raise_error(Audience::Kit::Error) { |e| expect([e.code, e.minimum_sdk_version]).to eq(["UPDATE_REQUIRED", "0.4.0"]) }
      expect { session.request("/v1/x") }.to raise_error(Audience::Kit::Error) { |e| expect([e.code, e.message]).to eq(%w[UNSUPPORTED_API_VERSION Old]) }
      expect { session.request("/v1/x") }.to raise_error(Audience::Kit::Error, "You don't have access to this.")
      expect { session.request("/v1/x") }.to raise_error(Audience::Kit::Error, "That isn't available.")
    end

    it "reports a 401 on an unauthenticated request without ending the session" do
      http.on(:get, "/v1/x", 401, {})
      expect { session.request("/v1/x", authenticated: false) }.to raise_error(Audience::Kit::Error, &:unauthenticated?)
      expect(session).to be_signed_in
    end

    it "wraps network failures" do
      faraday = Faraday.new { |f| f.adapter(:test, Faraday::Adapter::Test::Stubs.new { |s| s.get("/v1/x") { raise Faraday::ConnectionFailed, "offline" } }) }
      session = described_class.new(configuration: configuration, http: faraday)
      expect { session.request("/v1/x", authenticated: false) }.to raise_error(Audience::Kit::Error) { |e| expect([e.code, e.message]).to eq(%w[NETWORK offline]) }
    end

    it "makes its own Faraday connection by default" do
      expect(described_class.new.instance_variable_get(:@http)).to be_a(Faraday::Connection)
    end
  end

  it "resolves URLs the API sent" do
    expect(session.url(nil)).to be_nil
    expect(session.url("")).to be_nil
    expect(session.url("https://cdn.test/a.png")).to eq("https://cdn.test/a.png")
    expect(session.url("/v1/photos/1")).to eq("https://api.test/v1/photos/1")
  end

  it "describes operations for the monitoring headers" do
    expect(described_class.describe("query Venues { x }", nil)).to eq(%w[query Venues])
    expect(described_class.describe("subscription { x }", "Mine")).to eq(%w[subscription Mine])
    expect(described_class.describe("{ x }", nil)).to eq(["query", nil])
  end

  it "keeps the token out of inspect" do
    session.adopt(credential)
    expect(session.inspect).to eq("#<Audience::Kit::Session base_url=https://api.test signed_in=true>")
    expect(session.credential.inspect).not_to include("jwt")
  end
end
