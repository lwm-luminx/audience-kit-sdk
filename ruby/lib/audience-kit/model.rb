# frozen_string_literal: true

module Audience
  module Kit
    # A result from the API: typed readers for what apps read most, over the API's JSON exactly as it came back.
    #
    # Every model is also readable as the Hash it was made from (+venue["locale"]["name"]+), with the keys the schema
    # names (camelCase), so fields the model has no reader for are still there. {#to_h} returns that Hash and
    # {#to_json} writes it back out. Models are read-only.
    class Model
      # @return [Hash{String => Object}] the API's JSON for this object, as it came back
      attr_reader :raw
      # @deprecated The 0.2 name for {#raw}.
      alias data raw

      class << self
        # The model for +data+, or nil when it isn't an object (the field was null, or its module isn't installed).
        # @param data [Object]
        # @return [Model, nil]
        def from(data)
          data.is_a?(Hash) ? new(data) : nil
        end

        # The models for a JSON list, skipping nulls: a connection's +nodes+ or a plain list.
        # @param data [Object]
        # @return [Array<Model>]
        def list(data)
          data = data["nodes"] if data.is_a?(Hash) && data.key?("nodes")
          return [] unless data.is_a?(Array)

          data.grep(Hash).map { |item| new(item) }
        end

        # @return [Array<Symbol>] the readers {.attribute} declared, in order
        def attributes
          @attributes ||= []
        end

        private

        # Declares a reader for a field of the JSON. +type+ is +:string+, +:integer+, +:boolean+, +:time+,
        # +:strings+, +:hashes+, +:hash+, a model class's name (a String, so models can refer to each other) or a
        # one-element Array of one, for a list. +path+ is where the field is (+"startAt"+ by default for
        # +:start_at+), +default+ what to read when it is missing.
        def attribute(name, type = :string, path: nil, default: nil)
          keys = Array(path || name.to_s.gsub(/_([a-z])/) { Regexp.last_match(1).upcase })
          attributes << name
          define_method(name) do
            @values.fetch(name) do
              @values[name] = Model.cast(dig(*keys), type, default)
            end
          end
        end
      end

      # @param raw [Hash] the API's JSON for this object, decoded with string keys
      def initialize(raw)
        @raw = raw.freeze
        @values = {}
      end

      # A field of the JSON, by the schema's name.
      # @param key [String, Symbol]
      # @return [Object, nil]
      def [](key)
        raw[key.to_s]
      end

      # The JSON at a path of keys, or nil where any of it is missing.
      # @return [Object, nil]
      def dig(*keys)
        raw.dig(*keys.map(&:to_s))
      rescue TypeError
        nil
      end

      # @return [Hash{String => Object}]
      def to_h = raw

      # @return [String]
      def to_json(*) = raw.to_json(*)

      # @return [Boolean]
      def ==(other)
        other.instance_of?(self.class) && other.raw == raw
      end
      alias eql? ==

      # @return [Integer]
      def hash = [self.class, raw].hash

      # @return [String]
      def inspect
        shown = self.class.attributes.first(4).map { |name| "#{name}=#{public_send(name).inspect}" }
        "#<#{self.class.name} #{shown.join(" ")}>"
      end

      # @!visibility private
      def self.cast(value, type, default)
        result = case type
                 when :string then value.is_a?(String) || value.is_a?(Numeric) ? value.to_s : nil
                 when :integer then integer(value)
                 when :boolean then value if [true, false].include?(value)
                 when :time then time(value)
                 when :strings then value.is_a?(Array) ? value.grep(String) : []
                 when :hashes then hashes(value)
                 when :hash then value.is_a?(Hash) ? value : nil
                 when Array then Kit.const_get(type.first).list(value)
                 else Kit.const_get(type).from(value)
                 end
        result.nil? ? default : result
      end

      # @!visibility private
      def self.integer(value)
        case value
        when Integer then value
        when Float, /\A-?\d+(\.\d+)?\z/ then value.to_i
        end
      end

      # @!visibility private
      def self.time(value)
        value.is_a?(String) && !value.empty? ? Time.iso8601(value) : nil
      rescue ArgumentError
        nil
      end

      # @!visibility private
      def self.hashes(value)
        value = value["nodes"] if value.is_a?(Hash)
        value.is_a?(Array) ? value.grep(Hash) : []
      end
    end
  end
end
