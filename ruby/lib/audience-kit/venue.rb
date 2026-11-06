# frozen_string_literal: true

module Audience
  module Kit
    # A venue fetched from the AudienceKit API; +data+ is the raw JSON hash.
    class Venue
      attr_reader :data

      def self.find(id)
        new Kit.get("/v1/venues/#{id}")["venue"]
      end

      def initialize(data)
        @data = data
      end
    end
  end
end
