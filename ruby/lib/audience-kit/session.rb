# frozen_string_literal: true

module Audience
  module Kit
    # Talks to the AudienceKit API on behalf of one audience and, once signed in, one person.
    #
    # Sign in with a Facebook, Google or Apple token the page obtained, use an application API key or a service
    # token, or {#adopt} a credential minted elsewhere. After that, every call carries the token as
    # +Authorization: Bearer <token>+ and the API contract version as +X-AudienceKit-API-Version+. When the API
    # rejects a person's session, the call raises {Error} with {Error::UNAUTHENTICATED} and the credential is
    # forgotten.
    #
    # The calls every app makes ({#venues}, {#events}, {#rsvp_event}...) are in {Operations}; run your own documents
    # with {#graphql}.
    #
    # @example A script with an application API key
    #   session = Audience::Kit::Session.new(
    #     configuration: Audience::Kit::Configuration.new(host: "hotmess.social")
    #   )
    #   session.use_bearer_token(ENV.fetch("AUDIENCEKIT_TOKEN"))
    #   session.venues.each { |venue| puts venue.name }
    class Session
      include Operations

      # How long before a service token's session expires the SDK trades the token again, in seconds.
      SERVICE_RENEW_BEFORE = 60

      # @return [Configuration]
      attr_reader :configuration

      # @param configuration [Configuration] where the API is and which audience to speak for
      # @param store [#load, #save, #delete] where the credential is kept ({MemoryCredentialStore} by default;
      #   {SessionCredentialStore} for a website)
      # @param http [Faraday::Connection, nil] the connection requests go through; pass one to set timeouts, a proxy,
      #   instrumentation or a test adapter
      def initialize(configuration: Configuration.new, store: MemoryCredentialStore.new, http: nil)
        @configuration = configuration
        @store = store
        @http = http || Faraday.new { |f| f.options.timeout = 30 }
        @resolved_audience_id = nil
        @schema_fields = {}
        @service_token = nil
      end

      # A session configured from the environment, for servers and scripts: +AUDIENCEKIT_TOKEN+ (a service token,
      # +akst_...+, or another bearer value such as an application API key) and, when set, +AUDIENCEKIT_BASE_URL+,
      # +AUDIENCEKIT_AUDIENCE_ID+, +AUDIENCEKIT_HOST+ and +AUDIENCEKIT_ENVIRONMENT+.
      # @param env [Hash{String => String}] where to read them from
      # @param http [Faraday::Connection, nil]
      # @return [Session]
      def self.from_env(env = ENV, http: nil)
        read = ->(name) { env.fetch("AUDIENCEKIT_#{name}", nil).then { |value| value.to_s.empty? ? nil : value } }
        build(
          configuration: Configuration.new(base_url: read["BASE_URL"] || PRODUCTION_BASE_URL, host: read["HOST"],
                                           audience_id: read["AUDIENCE_ID"],
                                           environment: read["ENVIRONMENT"] || Environment::PRODUCTION),
          token: read["TOKEN"], http: http
        )
      end

      # A session that uses +token+: a service token (+akst_...+), traded when first needed, or anything else, sent
      # as is.
      # @return [Session]
      def self.build(configuration:, token: nil, http: nil)
        session = new(configuration: configuration, http: http)
        if token&.start_with?("akst_")
          session.instance_variable_set(:@service_token, token)
        elsif token
          session.use_bearer_token(token)
        end
        session
      end

      # @!group Session

      # Whether a credential is stored. The API may still reject it.
      # @return [Boolean]
      def signed_in?
        !load_credential.nil?
      end

      # The stored credential: who is signed in, to which audience, and the token. Never log the token.
      # @return [Credential, nil]
      def credential
        load_credential
      end

      # The stored session token, for the rare connection the SDK doesn't make itself (an Action Cable client).
      # @return [String, nil]
      def session_token
        load_credential&.token
      end

      # Exchanges a Facebook user access token for a session and stores it. Sends the configured host and Facebook
      # app ID, so the API checks the token against the right Facebook app and binds the session to the audience.
      # @param access_token [String]
      # @param device [DeviceDescription]
      # @return [Credential]
      # @raise [Error] {Error::SIGN_IN_REJECTED} when the API refuses the token
      def sign_in_with_facebook_token(access_token, device:)
        sign_in("/v1/token", facebook_body({ "facebook_token" => access_token }, device))
      end

      # Exchanges the code from Facebook's OAuth dialog for a session and stores it. The API trades the code with the
      # app secret, so +redirect_uri+ must be exactly the one the dialog was opened with.
      # @param code [String]
      # @param redirect_uri [String]
      # @param device [DeviceDescription]
      # @param facebook_app_id [String, nil] overrides the configured app
      # @return [Credential]
      def sign_in_with_facebook_code(code, redirect_uri:, device:, facebook_app_id: nil)
        fields = { "code" => code, "redirect_uri" => redirect_uri, "facebook_app_id" => facebook_app_id }.compact
        sign_in("/v1/token", facebook_body(fields, device))
      end

      # Exchanges a Google ID token (from Google Identity Services) for a session and stores it. Pass +access_token+
      # (an OAuth token for +https://www.googleapis.com/auth/user.emails.read+) and the API can also match an
      # existing account by the Google account's other verified emails.
      # @param id_token [String]
      # @param device [DeviceDescription]
      # @param name [String, nil]
      # @param access_token [String, nil]
      # @return [Credential]
      def sign_in_with_google(id_token, device:, name: nil, access_token: nil)
        sign_in("/v1/token/google", { "id_token" => id_token, "access_token" => access_token,
                                      "host" => configuration.host, "device" => device.to_body,
                                      "name" => name }.compact)
      end

      # Connects a Google account to the signed-in account, so Google signs in to it from then on, and stores the
      # session the API answers with. A refusal raises {Error::SIGN_IN_FAILED} and keeps the current session.
      # @return [Credential]
      def connect_google(id_token, device:)
        sign_in("/v1/token/google", { "id_token" => id_token, "host" => configuration.host,
                                      "device" => device.to_body, "connect" => true }.compact, authenticated: true)
      end

      # Exchanges a Sign in with Apple credential for a session and stores it (+POST /v1/token/apple+). On the web,
      # Sign in with Apple JS returns the identity token, an authorization code and the redirect URI it used; pass the
      # nonce you gave it. Apple gives the person's name only the first time; pass it then.
      # @return [Credential]
      def sign_in_with_apple(identity_token, device:, authorization_code: nil, redirect_uri: nil, nonce: nil,
                             first_name: nil, last_name: nil)
        sign_in("/v1/token/apple", {
          "identity_token" => identity_token, "authorization_code" => authorization_code,
          "redirect_uri" => redirect_uri, "nonce" => nonce, "first_name" => first_name, "last_name" => last_name,
          "host" => configuration.host, "device" => device.to_body
        }.compact)
      end

      # Signs in with an App Review code (+POST /v1/token/review+). It works only while the audience is in App
      # Review; a wrong or expired code raises {Error::SIGN_IN_REJECTED}.
      # @return [Credential]
      def sign_in_with_review_code(code, device:)
        sign_in("/v1/token/review", { "code" => code.strip, "host" => configuration.host,
                                      "device" => device.to_body }.compact)
      end

      # Connects Facebook to the signed-in account (one that signed in with Apple or Google), with the code from
      # Facebook's OAuth dialog, and stores the new session the API returns.
      # @return [Credential]
      def connect_facebook(code, redirect_uri:, device:)
        body = facebook_body({ "code" => code, "redirect_uri" => redirect_uri, "connect" => true }, device)
        sign_in("/v1/token", body, authenticated: true)
      end

      # Re-issues the session token at +POST /v1/token/refresh+ (the same session, signed with the API's current key)
      # and stores it.
      # @return [Credential]
      def refresh_session
        store(decode_credential(request("/v1/token/refresh", method: :post)))
      end

      # Uses an audience service token (+akst_<prefix>_<secret>+, minted by an admin in the audience's console): a
      # server or agent acting for the audience rather than a person. The SDK trades it at +POST /v1/token/service+
      # for an hour-long session now, trades it again a minute before that runs out, and once more when the API
      # refuses the session. A token with +public:read+ reads the public listings ({Operations#public_listings}).
      # @param service_token [String]
      # @return [Credential]
      # @raise [Error] {Error::UNAUTHENTICATED} when the token is invalid or revoked
      def use_service_token(service_token)
        @service_token = service_token
        trade_service_token
      end

      # Sends +token+ as is (an application's API key, or a session JWT on its own) as +Authorization: Bearer+, to
      # the configured base URL and audience.
      # @param token [String]
      # @return [Credential]
      def use_bearer_token(token)
        @service_token = nil
        store(Credential.new(token: token, audience_id: configuration.audience_id, role: "bearer",
                             endpoint: "#{configuration.base_url.chomp("/")}/v1/graphql"))
      end

      # Makes +credential+ the session: one minted outside the SDK (a venue device's) or one the app stored itself.
      # GraphQL goes to the API instance the credential's endpoint names, for its audience.
      # @param credential [Credential]
      # @return [Credential]
      def adopt(credential)
        store(credential)
      end

      # Moves the session to another audience (+POST /v1/admin/choices+) and returns its credential, stored and in
      # use. The API allows it for platform-console sessions; anyone else gets {Error::FORBIDDEN}.
      # @return [Credential]
      def switch_audience(audience_id)
        store(decode_credential(request("/v1/admin/choices", method: :post, body: { "audience_id" => audience_id })))
      end

      # Ends the session: forgets the credential, then revokes the token with +DELETE /v1/token+ so it stops working
      # everywhere. The credential is forgotten even when that call fails; a 401 or 404 (the session was already
      # gone) is not an error.
      # @return [void]
      def sign_out
        credential = load_credential
        @service_token = nil
        forget
        return if credential.nil?

        response = perform(:delete, "/v1/token", token: credential.token)
        return if response.success? || [401, 404].include?(response.status)

        raise error_for_status(response.status, response.body)
      end

      # Deletes the signed-in person's account for good (App Store guideline 5.1.1(v), Google Play's account
      # deletion rule). The API erases their data and signs them out everywhere, so the credential is forgotten too.
      # It can't be undone: ask first.
      # @return [Boolean] whether the account is gone; when it isn't, the person stays signed in
      def delete_account
        data = graphql(Queries::DELETE_ACCOUNT, { "confirm" => true }, operation_name: "DeleteAccount")
        return false unless data.dig("deleteAccount", "deleted") == true

        forget
        true
      end

      # Ends the session because the API refused +token+ on a connection the SDK didn't make itself. Forgets the
      # credential once: when the store no longer holds +token+ it does nothing and returns false.
      # @return [Boolean]
      def session_rejected(token)
        stored = load_credential
        return false if token.nil? || stored.nil? || stored.token != token

        forget
        true
      end

      # @!endgroup

      # @!group The audience

      # The audience's public branding for the configured host (or +host+). No sign-in needed. Pass +app+ (a bundle
      # ID) to have it carry that app's release config too.
      # @return [Hash]
      def branding(host: configuration.host, app: nil)
        raise Error.missing_configuration("branding needs a host") if host.nil?

        query = { "host" => host }
        query["app"] = app unless app.to_s.empty?
        decode_object(request("/v1/branding", query: query, authenticated: false))
      end

      # The audience this session reads: the stored credential's audience, else the configured ID, else the audience
      # that owns the configured host (looked up once).
      # @return [String]
      # @raise [Error] {Error::MISSING_CONFIGURATION} with neither an audience ID nor a host
      def audience_id
        id = load_credential&.audience_id || configuration.audience_id || @resolved_audience_id
        return id if id
        raise Error.missing_configuration("set an audience_id or a host") if configuration.host.nil?

        id = branding.dig("audience", "id")
        raise Error.decoding("The branding had no audience id.") unless id.is_a?(String)

        @resolved_audience_id = id
      end

      # @!endgroup

      # @!group GraphQL

      # Runs a GraphQL operation against the audience's endpoint and returns its +data+.
      #
      # The request goes to the API instance the stored credential names (the configured base URL before sign-in).
      # Raises when the response carries errors, even alongside data.
      # @param document [String]
      # @param variables [Hash, nil]
      # @param operation_name [String, nil]
      # @param endpoint [String] {GraphQLEndpoint::CONSUMER}
      # @return [Hash] the response's +data+, with the schema's (camelCase) keys
      # @raise [Error] {Error.graphql} for GraphQL errors; see {Error} for the rest
      # @example
      #   data = session.graphql(<<~GRAPHQL, { "first" => 5 })
      #     query Soon($first: Int) { events { list(first: $first) { nodes { id name startAt } } } }
      #   GRAPHQL
      #   Audience::Kit::Event.list(data.dig("events", "list"))
      def graphql(document, variables = nil, operation_name: nil, endpoint: GraphQLEndpoint::CONSUMER)
        ensure_service_session
        credential = load_credential
        body = { "query" => document, "variables" => variables, "operationName" => operation_name }.compact
        type, name = Session.describe(document, operation_name)
        # Apollo's operation headers, which APM agents record with each request.
        headers = { "X-APOLLO-OPERATION-TYPE" => type, "X-APOLLO-OPERATION-NAME" => name }.compact
        path = GraphQLEndpoint.path(audience_id, endpoint)
        json = decode_object(request(path, method: :post, body: body, headers: headers,
                                           base_url: configuration.api_base(credential)))
        # Errors first: a refused mutation comes back as {"errors":[...],"data":{"field":null}}.
        if json["errors"].is_a?(Array) && !json["errors"].empty?
          raise Error.graphql(json["errors"].map { |error| GraphQLError.from_h(error) })
        end
        raise Error.decoding("The response had no data.") unless json["data"].is_a?(Hash)

        json["data"]
      end

      # Runs the operation the block builds, first for an audience with every module; when the API refuses a field
      # (+undefinedField+), asks the schema which fields +types+ have and runs it again with only those. The answer
      # is cached for the session, so later operations go straight to the right document.
      # @param types [Array<String>]
      # @param variables [Hash, nil]
      # @param operation_name [String]
      # @yieldparam shape [SchemaShape]
      # @yieldreturn [String] the document
      # @return [Hash]
      def shaped_graphql(types, variables, operation_name, &document)
        known = cached_schema_fields(types)
        return graphql(document.call(SchemaShape.new(known)), variables, operation_name: operation_name) if known

        begin
          graphql(document.call(SchemaShape.everything), variables, operation_name: operation_name)
        rescue Error => e
          raise unless e.undefined_field?

          graphql(document.call(SchemaShape.new(schema_fields(types))), variables, operation_name: operation_name)
        end
      end

      # The fields each of +types+ has in the audience's schema (introspection), by type name; a type the schema
      # doesn't have is left out. Cached for the session (until sign-in or sign-out).
      # @param types [Array<String>]
      # @return [Hash{String => Array<String>}]
      def schema_fields(types, endpoint: GraphQLEndpoint::CONSUMER)
        prefix = "#{audience_id}|#{endpoint}|"
        missing = types.uniq.reject { |type| @schema_fields.key?(prefix + type) }.sort
        unless missing.empty?
          selections = missing.each_with_index.map do |name, index|
            "t#{index}: __type(name: \"#{name}\") { fields(includeDeprecated: true) { name } }"
          end
          result = graphql("query SchemaFields { #{selections.join(" ")} }", operation_name: "SchemaFields",
                                                                             endpoint: endpoint)
          missing.each_with_index do |name, index|
            fields = result.dig("t#{index}", "fields")
            @schema_fields[prefix + name] = Array(fields).filter_map { |field| field["name"] if field.is_a?(Hash) }
          end
        end
        shape_from_cache(prefix, types)
      end

      # {#schema_fields}'s answer when the session already has it for every one of +types+, without asking the API;
      # nil otherwise.
      # @return [Hash{String => Array<String>}, nil]
      def cached_schema_fields(types, endpoint: GraphQLEndpoint::CONSUMER)
        prefix = "#{audience_id}|#{endpoint}|"
        types.all? { |type| @schema_fields.key?(prefix + type) } ? shape_from_cache(prefix, types) : nil
      rescue Error
        nil
      end

      # @!endgroup

      # @!group REST

      # Sends a request to one of the API's REST endpoints and returns the body of a successful response.
      # @param path [String] e.g. +/v1/branding+
      # @param method [Symbol] +:get+, +:post+, +:delete+...
      # @param query [Hash] query parameters
      # @param body [Object, nil] a JSON body
      # @param authenticated [Boolean] whether to send the session token; a 401 on an authenticated request ends a
      #   person's session
      # @param headers [Hash] headers beyond the ones every call carries
      # @param base_url [String, nil] another API instance than the configured one
      # @return [String]
      def request(path, method: :get, query: {}, body: nil, authenticated: true, headers: {}, base_url: nil)
        retried = false
        loop do
          token = nil
          base = base_url
          if authenticated
            ensure_service_session
            stored = load_credential or raise Error.not_signed_in
            token = stored.token
            # A REST call follows a service session to the instance that issued it, like GraphQL.
            base ||= configuration.api_base(stored) if stored.service?
          end
          response = perform(method, path, query: query, body: body, token: token, headers: headers, base_url: base)
          return response.body.to_s if response.success?

          if response.status == 401 && token
            if @service_token && !retried
              # The service session was refused (revoked, or signed with a retired key): trade the token again.
              retried = true
              trade_service_token
              next
            end
            session_rejected(token)
            raise Error.unauthorized
          end
          raise error_for_status(response.status, response.body)
        end
      end

      # Resolves a URL the API sent (absolute, or a path relative to the base URL).
      # @param string [String, nil]
      # @return [String, nil]
      def url(string)
        return nil if string.to_s.empty?
        return string if string.match?(%r{\A[a-z][a-z0-9+.-]*://}i)

        "#{configuration.base_url.chomp("/")}/#{string.delete_prefix("/")}"
      end

      # @!endgroup

      # An operation's type and name, from its document (or +operation_name+), for the monitoring headers.
      # @return [Array(String, String)]
      def self.describe(document, operation_name)
        match = /\A\s*(query|mutation|subscription)\b\s*([A-Za-z_]\w*)?/.match(document)
        return ["query", operation_name] unless match

        [match[1], operation_name || match[2]]
      end

      # @return [String]
      def inspect
        "#<#{self.class.name} base_url=#{configuration.base_url} signed_in=#{signed_in?}>"
      end

      private

      def ensure_service_session
        return if @service_token.nil?

        stored = load_credential
        trade_service_token if stored.nil? || stored.expires_within?(SERVICE_RENEW_BEFORE)
      end

      def trade_service_token
        response = perform(:post, "/v1/token/service", body: { "service_token" => @service_token })
        if [401, 403].include?(response.status)
          @service_token = nil
          raise Error.new("The service token was refused: it is invalid or was revoked.",
                          code: Error::UNAUTHENTICATED, status: response.status)
        end
        raise error_for_status(response.status, response.body) unless response.success?

        store(decode_credential(response.body))
      end

      def sign_in(path, body, authenticated: false)
        token = (load_credential&.token or raise Error.not_signed_in) if authenticated
        response = perform(:post, path, body: body, token: token)
        raise Error.sign_in_rejected if response.status == 401

        if response.status == 400
          fault = rest_error_body(response.body)
          unless fault["error"] == Error::UNSUPPORTED_API_VERSION_ERROR
            raise Error.sign_in_failed(fault["message"] || fault.dig("fault", "message"))
          end
        end
        raise error_for_status(response.status, response.body) unless response.success?

        store(decode_credential(response.body))
      end

      def facebook_body(fields, device)
        fields.merge("host" => configuration.host, "facebook_app_id" => configuration.facebook_app_id) { |_, a, _| a }
              .merge("device" => device.to_body).compact
      end

      def store(credential)
        begin
          @store.save(credential)
        rescue StandardError => e
          raise Error.storage(e.message)
        end
        @resolved_audience_id = nil
        @schema_fields = {}
        credential
      end

      def forget
        begin
          @store.delete
        rescue StandardError
          # The token is revoked (or the account is gone) either way.
        end
        @resolved_audience_id = nil
        @schema_fields = {}
      end

      def load_credential
        @store.load
      rescue StandardError
        nil
      end

      def shape_from_cache(prefix, types)
        types.to_h { |type| [type, @schema_fields.fetch(prefix + type, [])] }.reject { |_, fields| fields.empty? }
      end

      def perform(method, path, query: {}, body: nil, token: nil, headers: {}, base_url: nil)
        url = "#{(base_url || configuration.base_url).chomp("/")}/#{path.delete_prefix("/")}"
        url += "?#{URI.encode_www_form(query)}" unless query.empty?
        all = {
          "Accept" => "application/json", CLIENT_HEADER => Kit.client_header, API_VERSION_HEADER => API_VERSION
        }
        all[Environment::HEADER] = configuration.environment unless configuration.environment == Environment::PRODUCTION
        all["Authorization"] = "Bearer #{token}" if token
        all.merge!(headers)
        payload = nil
        unless body.nil?
          all["Content-Type"] = "application/json"
          payload = JSON.generate(body)
        end
        @http.run_request(method, url, payload, all)
      rescue Faraday::Error => e
        raise Error.network(e)
      end

      # The error for an unsuccessful REST status, reading the API's { "error": "<code>", "message": "..." } body.
      def error_for_status(status, data)
        body = rest_error_body(data)
        message = body["message"] || body.dig("fault", "message")
        message = nil unless message.is_a?(String)
        code = body["error"].is_a?(String) ? body["error"] : nil
        case status
        when 401 then Error.unauthorized
        when 403 then Error.forbidden(message)
        when 404 then Error.not_found(message)
        when 426 then Error.update_required(body["minimum_sdk_version"].to_s, message)
        else
          if status == 400 && code == Error::UNSUPPORTED_API_VERSION_ERROR
            text = message || "This version of the app is out of date. Update it to keep going."
            supported = body["supported"]
            text += " (API versions served: #{supported.join(", ")}.)" if supported.is_a?(Array) && !supported.empty?
            return Error.new(text, code: Error::UNSUPPORTED_API_VERSION, status: 400)
          end
          code = code&.upcase || { 400 => Error::INVALID, 409 => Error::CONFLICT, 422 => Error::INVALID,
                                   429 => Error::RATE_LIMITED }[status]
          code ||= Error::INTERNAL if status >= 500
          Error.http(status, code, message)
        end
      end

      def rest_error_body(data)
        decoded = JSON.parse(data.to_s)
        decoded.is_a?(Hash) ? decoded : {}
      rescue JSON::ParserError
        {}
      end

      def decode_object(data)
        decoded = JSON.parse(data.to_s)
        raise Error.decoding("The response was not a JSON object.") unless decoded.is_a?(Hash)

        decoded
      rescue JSON::ParserError => e
        raise Error.decoding(e.message)
      end

      def decode_credential(data)
        Credential.from_h(decode_object(data))
      rescue ArgumentError => e
        raise Error.decoding(e.message)
      end
    end
  end
end
