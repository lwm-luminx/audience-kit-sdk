# frozen_string_literal: true

require "faraday"
require "json"
require "openssl"
require "time"
require "uri"

require_relative "audience-kit/version"

# The namespace of the audience-kit gem.
module Audience
  # The AudienceKit SDK for Ruby: a client for an audience's consumer GraphQL API and the REST calls around it
  # (sign-in, branding, public listings), returning typed models.
  #
  # Make a {Session} for an audience, give it a credential (a person's sign-in, an application API key or a service
  # token), then read and act on the audience:
  #
  #   session = Audience::Kit::Session.from_env   # AUDIENCEKIT_TOKEN, AUDIENCEKIT_HOST, ...
  #   session.events.each { |event| puts "#{event.start_at}: #{event.name}" }
  #
  # Scripts that talk to one audience can use the module-level session instead, set up with {configure}.
  module Kit
    # The hosted AudienceKit API.
    PRODUCTION_BASE_URL = "https://api.audiencekit.com"
    # @deprecated Use {PRODUCTION_BASE_URL}. Kept for code written against 0.2.
    DEFAULT_BASE_URL = PRODUCTION_BASE_URL
    # The request header that carries {API_VERSION}.
    API_VERSION_HEADER = "X-AudienceKit-API-Version"
    # The request header that says which SDK is calling.
    CLIENT_HEADER = "X-AudienceKit-Client"

    class << self
      # @return [String, nil] the API's base URL for {session}; +AUDIENCEKIT_BASE_URL+ or {PRODUCTION_BASE_URL} when
      #   unset.
      attr_writer :base_url
      # @return [String, nil] the token {session} uses: an application API key, a session JWT or a service token
      #   (+akst_...+). +AUDIENCEKIT_TOKEN+ when unset.
      attr_writer :token
      # @return [String, nil] the audience {session} reads; +AUDIENCEKIT_AUDIENCE_ID+ when unset.
      attr_writer :audience_id
      # @return [String, nil] a host that names the audience (e.g. +hotmess.social+); +AUDIENCEKIT_HOST+ when unset.
      attr_writer :host

      # What {CLIENT_HEADER} carries: the SDK's name and version.
      # @return [String]
      def client_header
        "AudienceKit-Ruby/#{VERSION}"
      end

      # Whether +version+ (this SDK's by default) is older than +minimum+, a dotted version like "0.4.0".
      # @param minimum [String]
      # @param version [String]
      # @return [Boolean]
      def older?(minimum, version = VERSION)
        mine = version.split(".").map(&:to_i)
        theirs = minimum.split(".").map(&:to_i)
        length = [mine.length, theirs.length].max
        (mine + ([0] * (length - mine.length)) <=> theirs + ([0] * (length - theirs.length))).negative?
      end

      # @return [String]
      def base_url
        @base_url || env("BASE_URL") || PRODUCTION_BASE_URL
      end

      # @return [String, nil]
      def token
        @token || env("TOKEN")
      end

      # @return [String, nil]
      def audience_id
        @audience_id || env("AUDIENCE_ID")
      end

      # @return [String, nil]
      def host
        @host || env("HOST")
      end

      # Sets up the module-level {session}.
      #
      # @example
      #   Audience::Kit.configure do |c|
      #     c.token = ENV.fetch("AUDIENCEKIT_TOKEN")
      #     c.host = "hotmess.social"
      #   end
      # @yieldparam config [Module] this module, with its writers
      # @return [Module]
      def configure
        yield self
        @session = nil
        self
      end

      # A {Session} built from {configure}'s settings (or the environment), made on first use.
      # @return [Session]
      def session
        @session ||= Session.build(
          configuration: Configuration.new(base_url: base_url, host: host, audience_id: audience_id,
                                           environment: env("ENVIRONMENT") || Environment::PRODUCTION),
          token: token
        )
      end

      # Replaces the module-level session, e.g. with one a test built against a stub API.
      attr_writer :session

      # Runs a GraphQL document with the module-level {session} and returns its +data+.
      # @param document [String]
      # @param variables [Hash, nil]
      # @return [Hash]
      def query(document, variables = nil)
        session.graphql(document, variables)
      end

      # Forgets {configure}'s settings and the module-level session.
      # @return [void]
      def reset!
        @base_url = @token = @audience_id = @host = @session = nil
      end

      private

      # +AUDIENCEKIT_<name>+, or the 0.2 releases' +AUDIENCE_KIT_<name>+.
      def env(name)
        [ENV.fetch("AUDIENCEKIT_#{name}", nil), ENV.fetch("AUDIENCE_KIT_#{name}", nil)].find { |v| v && !v.empty? }
      end
    end
  end
end

require_relative "audience-kit/error"
require_relative "audience-kit/environment"
require_relative "audience-kit/configuration"
require_relative "audience-kit/credential"
require_relative "audience-kit/credential_store"
require_relative "audience-kit/device_description"
require_relative "audience-kit/schema_shape"
require_relative "audience-kit/coordinate"
require_relative "audience-kit/color"
require_relative "audience-kit/cover_pass"
require_relative "audience-kit/report_target"
require_relative "audience-kit/model"
require_relative "audience-kit/models"
require_relative "audience-kit/queries"
require_relative "audience-kit/operations"
require_relative "audience-kit/session"
