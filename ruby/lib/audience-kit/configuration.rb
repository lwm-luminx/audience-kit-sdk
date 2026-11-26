# frozen_string_literal: true

module Audience
  module Kit
    # Where a {Session} talks to and which audience it speaks for.
    #
    # @!attribute [r] base_url
    #   @return [String] the API's base URL, e.g. +https://api.audiencekit.com+ or +http://localhost:3000+
    # @!attribute [r] host
    #   @return [String, nil] a host that names the audience, e.g. +hotmess.social+. Sent with sign-in so the session
    #     is bound to the audience, and used to look up branding (and the audience ID when none is set).
    # @!attribute [r] audience_id
    #   @return [String, nil] the audience's ID (a UUID). When nil the session works it out from the stored
    #     credential, or from branding for {#host}.
    # @!attribute [r] facebook_app_id
    #   @return [String, nil] the Facebook app the site signs people in with
    # @!attribute [r] environment
    #   @return [String] {Environment::PRODUCTION} or {Environment::STAGING}
    # @!attribute [r] trusted_credential_origins
    #   @return [Array<String>] other API instances whose sign-ins {#base_url} also takes: a credential one of them
    #     issued is sent to {#base_url} rather than its own instance
    Configuration = Data.define(:base_url, :host, :audience_id, :facebook_app_id, :environment,
                                :trusted_credential_origins) do
      def initialize(base_url: PRODUCTION_BASE_URL, host: nil, audience_id: nil, facebook_app_id: nil,
                     environment: Environment::PRODUCTION, trusted_credential_origins: [])
        super
      end

      # The API instance to send +credential+ to: the one that issued it (its endpoint's origin), unless {#base_url}
      # takes that instance's sign-ins ({#trusted_credential_origins}); {#base_url} with no credential.
      # @param credential [Credential, nil]
      # @return [String]
      def api_base(credential)
        origin = credential&.origin
        return base_url if origin.nil?
        return base_url if trusted_credential_origins.any? { |trusted| Configuration.same_origin?(trusted, origin) }

        origin
      end

      # Whether two URLs name the same scheme, host and port.
      # @return [Boolean]
      def self.same_origin?(lhs, rhs)
        a = URI.parse(lhs)
        b = URI.parse(rhs)
        [a.scheme, a.host, a.port].map { |part| part.to_s.downcase } == [b.scheme, b.host, b.port].map do |part|
          part.to_s.downcase
        end
      rescue URI::InvalidURIError
        false
      end
    end
  end
end
