# frozen_string_literal: true

# Writes a static HTML page of what an audience lists publicly: its venues, upcoming events and posts.
#
#   AUDIENCEKIT_TOKEN=akst_... AUDIENCEKIT_HOST=hotmess.social ruby examples/listings_page.rb listings.html
#
# The token is a service token with the public:read scope. Without a file name, the page goes to standard output.

require "audience-kit"
require "cgi"

# Renders the public listings as one HTML page.
module ListingsPage
  HEADINGS = { "venue" => "Venues", "event" => "Events", "post" => "News" }.freeze

  module_function

  # @param session [Audience::Kit::Session]
  # @param title [String]
  # @return [String] the page
  def render(session, title: "What's on")
    listings = session.public_listings.select(&:public?)
    sections = HEADINGS.filter_map do |kind, heading|
      items = listings.select { |listing| listing.kind == kind }
      next if items.empty?

      "<h2>#{heading}</h2>\n<ul>\n#{items.map { |listing| "  <li>#{item(listing)}</li>" }.join("\n")}\n</ul>"
    end
    <<~HTML
      <!doctype html>
      <html lang="en">
      <head><meta charset="utf-8"><title>#{h(title)}</title></head>
      <body>
      <h1>#{h(title)}</h1>
      #{sections.join("\n")}
      </body>
      </html>
    HTML
  end

  # One listing's line.
  # @param listing [Audience::Kit::PublicListing]
  # @return [String]
  def item(listing)
    case listing.kind
    when "venue" then [h(listing.title), h(listing.address)].compact.join(", ")
    when "event" then event(listing)
    else [h(listing.title), h(listing.description)].compact.join(": ")
    end
  end

  # An event's line: when, what and where, struck through when it's canceled.
  # @param listing [Audience::Kit::PublicListing]
  # @return [String]
  def event(listing)
    line = [listing.start_at&.strftime("%a %b %-d, %-l:%M%P"), h(listing.title)].compact.join(": ")
    line += " at #{h(listing.venue_name)}" if listing.venue_name
    line = %(<a href="#{h(listing.ticket_url)}">#{line}</a>) if listing.ticket_url
    listing.canceled ? "<s>#{line}</s> (canceled)" : line
  end

  # @param text [String, nil]
  # @return [String, nil]
  def h(text) = text && CGI.escapeHTML(text)
end

if $PROGRAM_NAME == __FILE__
  page = ListingsPage.render(Audience::Kit::Session.from_env)
  ARGV[0] ? File.write(ARGV[0], page) : puts(page)
end
