# frozen_string_literal: true

module Audience
  module Kit
    # A latitude and longitude, with an optional iBeacon's major and minor values.
    #
    # @!attribute [r] latitude
    #   @return [Float] degrees north, -90 to 90
    # @!attribute [r] longitude
    #   @return [Float] degrees east, -180 to 180
    # @!attribute [r] beacon_major
    #   @return [Integer, nil] an iBeacon's major value, which names a locale; nil or 0 for none
    # @!attribute [r] beacon_minor
    #   @return [Integer, nil] an iBeacon's minor value; nil or 0 for none
    Coordinate = Data.define(:latitude, :longitude, :beacon_major, :beacon_minor) do
      def initialize(latitude:, longitude:, beacon_major: nil, beacon_minor: nil)
        super(latitude: Float(latitude), longitude: Float(longitude), beacon_major: beacon_major,
              beacon_minor: beacon_minor)
      end

      # Parses a WKT point, +POINT (<longitude> <latitude>)+, optionally with an SRID prefix
      # (+SRID=4326;POINT (...)+). Nil when it isn't a point, or isn't a place on Earth (often the two numbers
      # swapped).
      # @param wkt [String]
      # @return [Coordinate, nil]
      def self.from_wkt(wkt)
        match = /POINT\s*\(\s*(-?[\d.]+(?:e-?\d+)?)\s+(-?[\d.]+(?:e-?\d+)?)/i.match(wkt.to_s)
        return nil unless match

        longitude = Float(match[1])
        latitude = Float(match[2])
        return nil unless latitude.between?(-90, 90) && longitude.between?(-180, 180)

        new(latitude: latitude, longitude: longitude)
      rescue ArgumentError
        nil
      end

      # The value to pass as a +CoordinatesInput+ variable. Zero beacon values mean no beacon.
      # @return [Hash{String => Numeric}]
      def to_input
        input = { "latitude" => latitude, "longitude" => longitude }
        input["beaconMajor"] = beacon_major unless beacon_major.to_i.zero?
        input["beaconMinor"] = beacon_minor unless beacon_minor.to_i.zero?
        input
      end

      # The point as WKT, +POINT (<longitude> <latitude>)+.
      # @return [String]
      def to_wkt
        "POINT (#{number(longitude)} #{number(latitude)})"
      end

      # The great-circle distance to +other+, in meters.
      # @param other [Coordinate]
      # @return [Float]
      def distance_to(other)
        lat1 = radians(latitude)
        lat2 = radians(other.latitude)
        d_lat = lat2 - lat1
        d_lon = radians(other.longitude - longitude)
        a = (Math.sin(d_lat / 2)**2) + (Math.cos(lat1) * Math.cos(lat2) * (Math.sin(d_lon / 2)**2))
        2 * 6_371_000.0 * Math.asin([1.0, Math.sqrt(a)].min)
      end

      private

      def radians(degrees) = degrees * Math::PI / 180

      def number(value)
        text = format("%.7f", value).sub(/0+\z/, "").sub(/\.\z/, "")
        text == "-0" ? "0" : text
      end
    end
  end
end
