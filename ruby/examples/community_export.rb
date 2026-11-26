# frozen_string_literal: true

# Writes an audience's whole community (the audience, locales, venues, people, upcoming events and series) as JSON,
# for a static site generator: Jekyll's _data/, Bridgetown, Middleman.
#
#   AUDIENCEKIT_TOKEN=... AUDIENCEKIT_HOST=hotmess.social ruby examples/community_export.rb _data/community.json
#
# The token is an application API key. Without a file name, the JSON goes to standard output.

require "audience-kit"
require "json"

# Exports the community.
module CommunityExport
  module_function

  # The community as the API's JSON, ready to write. Read it back with Audience::Kit::Venue.list(json["venues"]) and
  # so on.
  # @param session [Audience::Kit::Session]
  # @return [Hash]
  def to_h(session)
    community = session.community
    {
      "audience" => community.audience&.to_h,
      "locales" => community.locales.map(&:to_h),
      "venues" => community.venues.reject(&:hidden?).map(&:to_h),
      "people" => community.people.map(&:to_h),
      "events" => community.events.reject(&:canceled?).map(&:to_h),
      "eventSeries" => community.event_series.map(&:to_h)
    }
  end
end

if $PROGRAM_NAME == __FILE__
  json = JSON.pretty_generate(CommunityExport.to_h(Audience::Kit::Session.from_env))
  ARGV[0] ? File.write(ARGV[0], json) : puts(json)
end
