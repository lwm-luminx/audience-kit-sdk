# frozen_string_literal: true

module Audience
  module Kit
    # The QR code on a cover pass, made from the admission's +passSecret+ every {WINDOW_SECONDS} so it works with no
    # signal and a screenshot stops scanning within a minute:
    #
    #   HMC1.<admission id>.<window>.<signature>
    #
    # where window is the Unix time divided by the window length and signature is the first 16 characters of the
    # unpadded URL-safe Base64 HMAC-SHA256 of +<admission id>.<window>+, keyed with the Base64-decoded secret. The
    # door accepts a couple of windows either side, for clock drift. The same codes the apps and other SDKs make.
    module CoverPass
      # What every code starts with.
      PREFIX = "HMC1"
      # How long each code lasts.
      WINDOW_SECONDS = 30

      module_function

      # The window +epoch_seconds+ falls in.
      # @param epoch_seconds [Integer]
      # @return [Integer]
      def window(epoch_seconds) = epoch_seconds.floor.div(WINDOW_SECONDS)

      # Seconds from +epoch_seconds+ until the code changes.
      # @param epoch_seconds [Integer]
      # @return [Integer]
      def seconds_until_next_window(epoch_seconds) = WINDOW_SECONDS - epoch_seconds.floor.modulo(WINDOW_SECONDS)

      # @return [String] the code's signature for one window
      def signature(admission_id, pass_secret, window)
        key = pass_secret.to_s.unpack1("m")
        mac = OpenSSL::HMAC.digest("SHA256", key, "#{admission_id}.#{window}")
        [mac].pack("m0").tr("+/", "-_").delete("=")[0, 16]
      end

      # The pass's code at +epoch_seconds+ (now by default).
      # @param admission_id [String]
      # @param pass_secret [String] the admission's +passSecret+ (Base64)
      # @param epoch_seconds [Integer, nil]
      # @return [String]
      def code(admission_id, pass_secret, epoch_seconds = nil)
        current = window(epoch_seconds || Time.now.to_i)
        [PREFIX, admission_id, current.to_s, signature(admission_id, pass_secret, current)].join(".")
      end

      # Whether +code+ looks like a cover pass, before asking the API.
      # @param code [String]
      # @return [Boolean]
      def code?(code)
        parts = code.to_s.strip.split(".", -1)
        parts.length == 4 && parts[0] == PREFIX && !parts[1].empty? && parts[2].match?(/\A\d+\z/) && !parts[3].empty?
      end
    end
  end
end
