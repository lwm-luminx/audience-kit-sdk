# frozen_string_literal: true

module Audience
  module Kit
    # Where a {Session} keeps its credential. Any object with +load+, +save(credential)+ and +delete+ works; back it
    # with something private to the signed-in person (a server-side session, an encrypted cookie), because the token
    # is as good as a password. Raise on failure: the session reports it as {Error::STORAGE}.
    module CredentialStore
      # @return [Credential, nil]
      def load = raise(NotImplementedError)

      # @param credential [Credential]
      # @return [void]
      def save(credential) = raise(NotImplementedError)

      # @return [void]
      def delete = raise(NotImplementedError)
    end

    # Keeps the credential in memory, for as long as the store object lives: the store for a script, a job or one
    # request.
    class MemoryCredentialStore
      include CredentialStore

      def initialize(credential = nil)
        @credential = credential
      end

      # @return [Credential, nil]
      def load = @credential

      # @param credential [Credential]
      def save(credential)
        @credential = credential
      end

      # Forgets the credential.
      def delete
        @credential = nil
      end
    end

    # Keeps the credential in a Hash-like session under +key+: Rails' +session+, Rack's +env["rack.session"]+,
    # Sinatra's +session+. Use a server-side or encrypted session store (Rails' default cookie store is encrypted),
    # and call +reset_session+ when signing someone in, so a session ID planted before sign-in isn't reused.
    #
    # @example In a Rails controller
    #   def audience_kit
    #     @audience_kit ||= Audience::Kit::Session.new(
    #       configuration: Audience::Kit::Configuration.new(host: "hotmess.social"),
    #       store: Audience::Kit::SessionCredentialStore.new(session)
    #     )
    #   end
    class SessionCredentialStore
      include CredentialStore

      # @return [String]
      attr_reader :key

      # @param session [#[], #[]=, #delete] the session
      # @param key [String] where in it the credential goes
      def initialize(session, key: "audiencekit.credential")
        @session = session
        @key = key
      end

      # @return [Credential, nil] the stored credential, or nil when there is none or it is unreadable
      def load
        data = @session[key]
        data.is_a?(Hash) ? Credential.from_h(data.transform_keys(&:to_s)) : nil
      rescue ArgumentError
        nil
      end

      # @param credential [Credential]
      def save(credential)
        @session[key] = credential.to_h
      end

      # Removes the credential from the session.
      def delete
        @session.delete(key)
      end
    end
  end
end
