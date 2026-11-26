# frozen_string_literal: true

module Audience
  module Kit
    # One entry of a GraphQL response's +errors+ array.
    class GraphQLError
      # @return [String]
      attr_reader :message
      # @return [Array<String, Integer>, nil] the response path of the field that failed, e.g. +["venues", 0]+
      attr_reader :path
      # @return [Hash, nil] extra detail: +code+ and, for INVALID, +fields+ mapping each field to its messages
      attr_reader :extensions

      def initialize(message:, path: nil, extensions: nil)
        @message = message
        @path = path
        @extensions = extensions
      end

      # @param data [Hash] one entry of +errors+, as decoded JSON
      # @return [GraphQLError]
      def self.from_h(data)
        data = {} unless data.is_a?(Hash)
        new(message: data["message"].is_a?(String) ? data["message"] : "The request failed.",
            path: data["path"].is_a?(Array) ? data["path"] : nil,
            extensions: data["extensions"].is_a?(Hash) ? data["extensions"] : nil)
      end

      # +extensions.code+, when the API sent one.
      # @return [String, nil]
      def code
        code = extensions&.dig("code")
        code.is_a?(String) ? code : nil
      end
    end

    # Everything a {Session} call can fail with: a {#code} from the API's vocabulary (or the SDK's own, for failures
    # before a response), a message for the person, and what detail there is.
    #
    # Compare {#code} with the constants below. The API sends +extensions.code+ on GraphQL errors and +error+ on REST
    # ones; a code the SDK doesn't know is passed through as the API sent it.
    #
    # @example
    #   begin
    #     session.rsvp_event(event_id, "ATTENDING")
    #   rescue Audience::Kit::Error => e
    #     redirect_to sign_in_path if e.unauthenticated?
    #     flash[:alert] = e.message
    #   end
    class Error < StandardError
      # The API rejected the session (HTTP 401). The session has already forgotten the credential; sign in again.
      UNAUTHENTICATED = "UNAUTHENTICATED"
      # Signed in, but not allowed here (HTTP 403).
      FORBIDDEN = "FORBIDDEN"
      # The audience, record or host doesn't exist (HTTP 404).
      NOT_FOUND = "NOT_FOUND"
      # The input was refused; {#fields} says which parts.
      INVALID = "INVALID"
      # Too many requests (HTTP 429).
      RATE_LIMITED = "RATE_LIMITED"
      # The change clashed with the record's state (HTTP 409).
      CONFLICT = "CONFLICT"
      # The API failed (HTTP 5xx, or a GraphQL error it couldn't classify).
      INTERNAL = "INTERNAL"
      # There is no stored credential; sign in first.
      NOT_SIGNED_IN = "NOT_SIGNED_IN"
      # The API refused the Facebook, Google, Apple or review-code login (HTTP 401).
      SIGN_IN_REJECTED = "SIGN_IN_REJECTED"
      # Sign-in failed (HTTP 400). The message is the API's when it sent one.
      SIGN_IN_FAILED = "SIGN_IN_FAILED"
      # Any other unsuccessful HTTP status; see {#status}.
      HTTP = "HTTP"
      # The request never got a response: offline, timed out, TLS failure and so on.
      NETWORK = "NETWORK"
      # The response wasn't the JSON the SDK expected.
      DECODING = "DECODING"
      # A GraphQL error with no +extensions.code+, such as a validation failure of the document itself.
      GRAPHQL = "GRAPHQL"
      # The configuration is missing something this call needs, e.g. a host.
      MISSING_CONFIGURATION = "MISSING_CONFIGURATION"
      # The credential store couldn't save the session.
      STORAGE = "STORAGE"
      # The API no longer serves this SDK version (HTTP 426); see {#minimum_sdk_version}.
      UPDATE_REQUIRED = "UPDATE_REQUIRED"
      # The API no longer serves the API version this SDK speaks (HTTP 400 +unsupported_api_version+).
      UNSUPPORTED_API_VERSION = "UNSUPPORTED_API_VERSION"
      # The REST body's +error+ for an API version the API no longer serves.
      UNSUPPORTED_API_VERSION_ERROR = "unsupported_api_version"

      # @return [String] one of the constants above, or whatever the API sent
      attr_reader :code
      # @return [Integer, nil] the HTTP status, when there was a response
      attr_reader :status
      # @return [Hash{String => Array<String>}] INVALID only: the API's messages per field
      attr_reader :fields
      # @return [Array<GraphQLError>] the GraphQL response's +errors+, when it returned any
      attr_reader :errors
      # @return [String, nil] UPDATE_REQUIRED only: the oldest SDK version the API serves
      attr_reader :minimum_sdk_version

      def initialize(message = "The request failed.", code: HTTP, status: nil, fields: {}, errors: [],
                     minimum_sdk_version: nil)
        super(message)
        @code = code
        @status = status
        @fields = fields
        @errors = errors
        @minimum_sdk_version = minimum_sdk_version
      end

      class << self
        # @!visibility private
        def not_signed_in = new("You're not signed in.", code: NOT_SIGNED_IN)

        # @!visibility private
        def unauthorized = new("Your session has ended. Sign in again to continue.", code: UNAUTHENTICATED, status: 401)

        # @!visibility private
        def sign_in_rejected
          new("Sign-in was refused. The login isn't valid for this app.", code: SIGN_IN_REJECTED, status: 401)
        end

        # @!visibility private
        def sign_in_failed(message) = new(message || "Sign-in failed.", code: SIGN_IN_FAILED, status: 400)

        # @!visibility private
        def forbidden(message = nil) = new(message || "You don't have access to this.", code: FORBIDDEN, status: 403)

        # @!visibility private
        def not_found(message = nil) = new(message || "That isn't available.", code: NOT_FOUND, status: 404)

        # @!visibility private
        def http(status, code = nil, message = nil)
          new(message || "The server responded with status #{status}.", code: code || HTTP, status: status)
        end

        # @!visibility private
        def network(error) = new(error.message, code: NETWORK)

        # @!visibility private
        def decoding(detail)
          new("The server sent a response the app didn't understand. #{detail}", code: DECODING)
        end

        # @!visibility private
        def missing_configuration(detail)
          new("AudienceKit isn't configured: #{detail}", code: MISSING_CONFIGURATION)
        end

        # @!visibility private
        def storage(detail) = new("The session couldn't be saved. #{detail}", code: STORAGE)

        # @!visibility private
        def update_required(minimum, message)
          new(message || "This version of the app is out of date. Update it to keep going.",
              code: UPDATE_REQUIRED, status: 426, minimum_sdk_version: minimum)
        end

        # The GraphQL operation returned +errors+: the code and message are the first one's, and INVALID errors'
        # +extensions.fields+ become {#fields}.
        # @param errors [Array<GraphQLError>]
        # @return [Error]
        def graphql(errors)
          first = errors.first
          fields = {}
          sent = first&.extensions&.dig("fields")
          if sent.is_a?(Hash)
            sent.each do |field, value|
              fields[field.to_s] = Array(value).grep(String)
            end
          end
          new(first&.message || "The request failed.", code: first&.code || GRAPHQL, fields: fields, errors: errors)
        end
      end

      # Whether the API refused the session ({UNAUTHENTICATED}).
      # @return [Boolean]
      def unauthenticated?
        code == UNAUTHENTICATED
      end

      # Whether the API refused the query because it asks for a field this audience's schema doesn't have: one a
      # module adds that the audience hasn't installed (or one from a newer API).
      # @return [Boolean]
      def undefined_field?
        errors.any? { |error| error.code == "undefinedField" }
      end
    end
  end
end
