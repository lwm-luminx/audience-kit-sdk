# frozen_string_literal: true

module Audience
  module Kit
    # Which fields an audience's schema has, as far as the SDK's documents need to know. The API leaves a module's
    # fields out of an audience that hasn't installed it (Facebook Pages, Google Places, RSVP, Ticketing, Friends...),
    # and asking for one fails the whole operation with +undefinedField+; the SDK builds its documents from this.
    class SchemaShape
      # @return [Hash{String => Array<String>}, nil] every type's fields, by type; nil assumes every field is there
      attr_reader :fields

      def initialize(fields = nil)
        @fields = fields
      end

      # Assumes every field is there: the first try of each operation, so an audience with every module needs one
      # call.
      # @return [SchemaShape]
      def self.everything
        new(nil)
      end

      # @param type [String]
      # @param field [String]
      # @return [Boolean]
      def has?(type, field)
        fields.nil? || fields.fetch(type, []).include?(field)
      end
    end
  end
end
