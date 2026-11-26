# frozen_string_literal: true

module Audience
  module Kit
    # A color from the API's hex strings (a theme token, a tag's chip color), with components from 0 to 1, for pages
    # that draw with the audience's branding.
    Color = Data.define(:red, :green, :blue, :alpha) do
      def initialize(red:, green:, blue:, alpha: 1.0)
        super
      end

      # Parses +#rgb+, +#rrggbb+ or +#rrggbbaa+ (the +#+ is optional); nil when it is none of those.
      # @param hex [String]
      # @return [Color, nil]
      def self.from_hex(hex)
        digits = hex.to_s.strip.delete_prefix("#")
        digits = digits.chars.map { |digit| digit * 2 }.join if digits.length == 3
        return nil unless digits.match?(/\A(\h{6}|\h{8})\z/)

        digits += "ff" if digits.length == 6
        red, green, blue, alpha = digits.scan(/../).map { |pair| pair.to_i(16) / 255.0 }
        new(red: red, green: green, blue: blue, alpha: alpha)
      end

      # A branding theme token's color, preferring its dark override in dark mode. +theme+ is branding's or the
      # audience's +theme+: +light+ and +dark+ either as +{ token => hex }+ maps (REST branding) or as lists of
      # +{ name, value }+ (GraphQL).
      # @param theme [Hash, nil]
      # @param token [String] e.g. +"accent"+
      # @param dark [Boolean]
      # @return [Color, nil]
      def self.from_theme(theme, token, dark: false)
        return nil unless theme.is_a?(Hash)

        hex = (token_value(theme["dark"], token) if dark) || token_value(theme["light"], token)
        hex && from_hex(hex)
      end

      def self.token_value(tokens, token)
        case tokens
        when Hash then tokens[token].is_a?(String) ? tokens[token] : nil
        when Array
          entry = tokens.find { |e| e.is_a?(Hash) && e["name"] == token && e["value"].is_a?(String) }
          entry && entry["value"]
        end
      end
      private_class_method :token_value

      # The color as CSS +rgba(r, g, b, a)+.
      # @return [String]
      def to_css
        alpha_text = format("%.3f", alpha.clamp(0.0, 1.0)).sub(/0+\z/, "").sub(/\.\z/, "")
        "rgba(#{channel(red)}, #{channel(green)}, #{channel(blue)}, #{alpha_text})"
      end

      # The color as +#rrggbb+, or +#rrggbbaa+ when it isn't opaque.
      # @return [String]
      def to_hex
        hex = format("#%<r>02x%<g>02x%<b>02x", r: channel(red), g: channel(green), b: channel(blue))
        alpha >= 1.0 ? hex : hex + format("%02x", channel(alpha))
      end

      private

      def channel(value) = (value.clamp(0.0, 1.0) * 255).round
    end
  end
end
