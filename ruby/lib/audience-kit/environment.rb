# frozen_string_literal: true

module Audience
  module Kit
    # Which build of the app is calling. Staging builds talk to the production API but sign people in with the
    # audience's staging Facebook app; the client says so with the +X-AudienceKit-Environment: staging+ header.
    # Production builds leave the header out. A value the SDK doesn't know is sent as is.
    module Environment
      # A store build: sends no header.
      PRODUCTION = "production"
      # A staging build, which signs people in with the audience's staging Facebook app.
      STAGING = "staging"
      # The header that carries the environment.
      HEADER = "X-AudienceKit-Environment"
      # The environments this SDK knows.
      KNOWN = [PRODUCTION, STAGING].freeze
    end

    # Which of an audience's GraphQL endpoints a request goes to: its path segment under +/v1/audience/<id>/+. This
    # SDK speaks to the consumer view, which grants a signed-in member their own records and nothing more.
    module GraphQLEndpoint
      # +/v1/audience/<id>/graphql+, for the apps people use.
      CONSUMER = "graphql"

      # The endpoint's path for an audience.
      # @param audience_id [String]
      # @param endpoint [String]
      # @return [String]
      def self.path(audience_id, endpoint = CONSUMER)
        "/v1/audience/#{URI.encode_uri_component(audience_id)}/#{endpoint}"
      end
    end
  end
end
