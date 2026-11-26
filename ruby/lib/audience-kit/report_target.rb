# frozen_string_literal: true

module Audience
  module Kit
    # What {Operations#report_content} reports: the API's +ReportTarget+, and the words around reporting that the
    # apps use, so every app says the same thing.
    module ReportTarget
      # A chat message (its frame ID).
      MESSAGE = "MESSAGE"
      # A member (their user ID, as chat gives it).
      PERSON = "PERSON"
      # A photo someone posted.
      PHOTO = "PHOTO"
      # A Ping: a wave from one member to another.
      PING = "PING"
      # A line in a Ping or Quickie chat; it and the lines before it are kept with the report.
      PRIVATE_MESSAGE = "PRIVATE_MESSAGE"
      # A post in the feed.
      POST = "POST"
      # A comment on a post.
      POST_COMMENT = "POST_COMMENT"
      # A venue listing.
      VENUE = "VENUE"
      # Every target.
      ALL = [MESSAGE, PERSON, PHOTO, PING, PRIVATE_MESSAGE, POST, POST_COMMENT, VENUE].freeze

      # The reason for an intimate image shared without the consent of the person in it. The API gives a report with
      # this reason a 48-hour deadline (the US Take It Down Act), so keep the wording.
      INTIMATE_IMAGE = "Intimate image shared without consent"
      # The reasons to offer.
      REASONS = ["Spam", "Harassment or hate", "Sexual content", INTIMATE_IMAGE, "Scam or fraud", "Other"].freeze
    end
  end
end
