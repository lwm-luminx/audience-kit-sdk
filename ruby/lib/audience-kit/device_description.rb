# frozen_string_literal: true

module Audience
  module Kit
    # The device a session is created on. The API records it alongside the session.
    #
    # @!attribute [r] identifier
    #   @return [String] a stable identifier for this install, browser or server
    # @!attribute [r] type
    #   @return [String] +web+ for a server or browser client
    # @!attribute [r] model
    #   @return [String, nil] the hardware model, when there is one
    # @!attribute [r] version
    #   @return [String, nil] the app's marketing version
    # @!attribute [r] build
    #   @return [String, nil] the app's build number
    DeviceDescription = Data.define(:identifier, :type, :model, :version, :build) do
      def initialize(identifier:, type: "web", model: nil, version: nil, build: nil)
        super
      end

      # The device as the API's +device+ object.
      # @return [Hash{String => String}]
      def to_body
        { "identifier" => identifier, "type" => type, "model" => model, "version" => version, "build" => build }.compact
      end
    end
  end
end
