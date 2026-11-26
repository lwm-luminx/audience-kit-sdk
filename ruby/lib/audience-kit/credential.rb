# frozen_string_literal: true

module Audience
  module Kit
    # A session the API issued, as +POST /v1/token+ (every variant) returns it:
    #
    #   { "token": "...", "userId": "...", "audienceId": "...", "role": "member",
    #     "endpoint": "https://api.audiencekit.com/v1/audience/<id>/graphql", "expiresAt": "2026-11-26T19:00:00Z" }
    #
    # The credential says everything the client needs about the session, so nothing decodes the JWT. Treat the token
    # like a password: keep it in a {CredentialStore} backed by something private, and never log it ({#inspect}
    # leaves it out).
    class Credential
      # @return [String] the session JWT, sent as +Authorization: Bearer <token>+
      attr_reader :token
      # @return [String, nil] the signed-in user's ID; nil for a service token's session or an API key
      attr_reader :user_id
      # @return [String, nil] the audience the session is bound to; nil for a platform-console session
      attr_reader :audience_id
      # @return [String] +member+, +admin+, +venue_device+, +service+ or +bearer+ (an API key sent as is)
      attr_reader :role
      # @return [String] the GraphQL endpoint the token was issued for, as a full URL
      attr_reader :endpoint
      # @return [String, nil] the venue device this session runs on, for venue-device sessions
      attr_reader :venue_device_id
      # @return [Time, nil] when the session expires; nil when it only ends by signing out
      attr_reader :expires_at
      # @return [String] the API version the credential was issued under
      attr_reader :api_version
      # @return [Array<String>] a service token's scopes, e.g. +public:read+
      attr_reader :scopes
      # @return [String, nil] a service token's audience name
      attr_reader :audience

      def initialize(token:, endpoint:, user_id: nil, audience_id: nil, role: "member", venue_device_id: nil,
                     expires_at: nil, api_version: API_VERSION, scopes: [], audience: nil)
        @token = token
        @endpoint = endpoint
        @user_id = user_id
        @audience_id = audience_id
        @role = role
        @venue_device_id = venue_device_id
        @expires_at = expires_at
        @api_version = api_version
        @scopes = scopes
        @audience = audience
      end

      # A credential from the API's JSON (decoded to a Hash with string keys).
      # @param data [Hash]
      # @return [Credential]
      # @raise [ArgumentError] when +token+ or +endpoint+ is missing, or +expiresAt+ isn't an ISO 8601 time
      def self.from_h(data)
        %w[token endpoint].each do |key|
          raise ArgumentError, "The credential has no #{key}." unless data[key].is_a?(String)
        end
        new(token: data["token"], endpoint: data["endpoint"], user_id: string(data["userId"]),
            audience_id: string(data["audienceId"]), role: string(data["role"]) || "member",
            venue_device_id: string(data["venueDeviceId"]), expires_at: time(data["expiresAt"]),
            api_version: string(data["apiVersion"]) || API_VERSION,
            scopes: data["scopes"].is_a?(Array) ? data["scopes"].grep(String) : [],
            audience: string(data["audience"]))
      end

      # The credential as the API's JSON shape, for storing (e.g. in a Rails session).
      # @return [Hash{String => Object}]
      def to_h
        {
          "token" => token, "userId" => user_id, "audienceId" => audience_id, "role" => role, "endpoint" => endpoint,
          "venueDeviceId" => venue_device_id, "expiresAt" => expires_at&.utc&.iso8601(3), "apiVersion" => api_version
        }.merge({ "scopes" => scopes, "audience" => audience }.reject { |_, v| v.nil? || v == [] })
      end

      # Whether the session has expired at +at+ (now by default). Sessions with no expiry never do.
      # @param at [Time]
      # @return [Boolean]
      def expired?(at = Time.now)
        !expires_at.nil? && expires_at <= at
      end

      # Whether the session expires within +seconds+ of +at+ (now by default).
      # @param seconds [Numeric]
      # @param at [Time]
      # @return [Boolean]
      def expires_within?(seconds, at = Time.now)
        !expires_at.nil? && expires_at <= at + seconds
      end

      # Whether this is a service token's session (no person behind it).
      # @return [Boolean]
      def service?
        role == "service"
      end

      # Whether a service token's session may do what +scope+ covers, e.g. +public:read+.
      # @param scope [String]
      # @return [Boolean]
      def scope?(scope)
        scopes.include?(scope)
      end

      # The API instance the endpoint is on: its scheme, host and port, and nothing else.
      # @return [String, nil]
      def origin
        uri = URI.parse(endpoint)
        return nil if uri.scheme.nil? || uri.host.nil?

        default = uri.port == uri.default_port
        "#{uri.scheme}://#{uri.host}#{":#{uri.port}" unless default}"
      rescue URI::InvalidURIError
        nil
      end

      # @return [Boolean]
      def ==(other)
        other.is_a?(Credential) && other.to_h == to_h
      end

      # Keeps the token out of logs and consoles.
      # @return [String]
      def inspect
        "#<#{self.class.name} role=#{role} user_id=#{user_id.inspect} audience_id=#{audience_id.inspect} " \
          "expires_at=#{expires_at&.iso8601.inspect} token=[REDACTED]>"
      end
      alias to_s inspect

      def self.string(value) = value.is_a?(String) ? value : nil

      def self.time(value)
        return nil if value.nil?
        raise ArgumentError, "expiresAt is not a string." unless value.is_a?(String)

        Time.iso8601(value)
      rescue ArgumentError
        raise ArgumentError, "#{value} isn't an ISO 8601 time."
      end
      private_class_method :string, :time
    end
  end
end
