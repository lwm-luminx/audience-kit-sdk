# frozen_string_literal: true

module Audience
  module Kit
    # A event fetched from the AudienceKit API; +data+ is the raw JSON hash.
    class Event
      attr_reader :data

      def self.find(id)
        new Kit.get("/v1/events/#{id}")["event"]
      end

      def initialize(data)
        @data = data
      end
    end
  end
end
