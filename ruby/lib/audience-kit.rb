# frozen_string_literal: true

require "faraday"

require_relative "audience-kit/version"

module Audience
  # Ruby client for the AudienceKit API.
  #
  #   Audience::Kit.configure { |c| c.token = "..." }
  #   Audience::Kit::Venue.find(1).data
  module Kit
    class Error < StandardError; end

    DEFAULT_BASE_URL = "https://api.audiencekit.io"

    class << self
      attr_writer :base_url, :token, :connection

      def base_url
        @base_url || ENV.fetch("AUDIENCE_KIT_BASE_URL", DEFAULT_BASE_URL)
      end

      def token
        @token || ENV.fetch("AUDIENCE_KIT_TOKEN", nil)
      end

      def configure
        yield self
        @connection = nil
        self
      end

      def connection
        @connection ||= Faraday.new(url: base_url) do |f|
          f.headers["Authorization"] = "Bearer #{token}" if token
          f.request :json
          f.response :json
          f.response :raise_error
        end
      end

      def get(path)
        connection.get(path).body
      rescue Faraday::Error => e
        raise Error, e.message
      end
    end
  end
end

require_relative "audience-kit/event"
require_relative "audience-kit/venue"
