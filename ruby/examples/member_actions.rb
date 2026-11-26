# frozen_string_literal: true

# Walks through what a signed-in person can do: who they are, the next event and who's going, a calendar
# subscription, and tonight's cover at that venue. With --rsvp it answers the event's RSVP, and with --say "text" it
# says hello in the venue's chat.
#
#   AUDIENCEKIT_HOST=hotmess.social AUDIENCEKIT_CREDENTIAL=credential.json ruby examples/member_actions.rb --rsvp
#
# AUDIENCEKIT_CREDENTIAL names a file with a credential a site saved (Audience::Kit::Credential#to_h as JSON). On a
# site, the person signs in first (see docs/sign-in.md) and the session already has one.

require "audience-kit"
require "json"

# The walk-through.
module MemberActions
  module_function

  # @param session [Audience::Kit::Session] a signed-in session
  # @param rsvp [Boolean] answer the next event's RSVP with ATTENDING
  # @param say [String, nil] a chat message for the event's venue
  # @param out [#puts]
  # @return [void]
  def run(session, rsvp: false, say: nil, out: $stdout)
    out.puts "Signed in as #{session.me&.name}"
    event = session.events(first: 1).first
    return out.puts("Nothing coming up.") unless event

    out.puts "Next: #{event.name} at #{event.venue_name || "TBA"}, #{event.start_at&.strftime("%a %b %-d %-l:%M%P")}"
    attend(session, event, rsvp, out)
    feed = session.create_calendar_feed
    out.puts "Add your events to a calendar: #{feed.webcal_url} (Google: #{feed.google_url})"
    venue_id = event.venue&.id
    return unless venue_id

    cover(session, venue_id, out)
    out.puts "Said: #{session.send_chat_message(say, venue_id: venue_id).body}" if say
  end

  # Answers the RSVP when asked to, then says who's going.
  # @return [void]
  def attend(session, event, rsvp, out)
    out.puts "Your RSVP: #{session.rsvp_event(event.id, "ATTENDING")}" if rsvp
    going = session.event_rsvp(event.id, first: 5)
    return unless going

    names = going.attendee_profiles.map(&:name)
    out.puts "#{going.going || going.count} going#{": #{names.join(", ")}" if names.any?}"
  end

  # Tonight's cover at the venue, and the person's pass if they have one.
  # @return [void]
  def cover(session, venue_id, out)
    cover = session.venue_cover(venue_id)
    charge = cover&.charge
    out.puts "Cover tonight: #{charge.total&.format}" if charge&.payable?
    pass = cover&.viewer_admission
    out.puts "Your pass code (show it as a QR code): #{pass.pass_code}" if pass&.paid?
  end
end

if $PROGRAM_NAME == __FILE__
  session = Audience::Kit::Session.from_env
  session.adopt(Audience::Kit::Credential.from_h(JSON.parse(File.read(ENV.fetch("AUDIENCEKIT_CREDENTIAL")))))
  say = ARGV.index("--say")&.then { |index| ARGV[index + 1] }
  MemberActions.run(session, rsvp: ARGV.include?("--rsvp"), say: say)
end
