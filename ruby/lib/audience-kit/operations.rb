# frozen_string_literal: true

module Audience
  module Kit
    # The calls every AudienceKit app makes, so apps are built with little custom code: the same operations the
    # Swift, Kotlin, Node, Python and PHP SDKs run, returning {Model}s with typed readers that are also readable as
    # the API's JSON. Fields a module adds are missing where the audience hasn't installed that module: the SDK asks
    # for them and, if the audience's schema doesn't have one, asks again without.
    #
    # Included in {Session}.
    module Operations
      # @!group The audience and its listings

      # The audience: its name, subdomain and theme.
      # @return [Audience]
      def audience
        Kit::Audience.new(graphql(Queries::AUDIENCE, operation_name: "Audience"))
      end

      # The signed-in person's own profile, or nil when there is none (an API key or service token's session).
      # @return [SelfUser, nil]
      def me
        SelfUser.from(graphql(Queries::ME, operation_name: "Me").dig("me", "self"))
      end

      # The audience's venues.
      # @return [Array<Venue>]
      def venues
        Venue.list(shaped(Queries::LISTING_TYPES, :venues, nil, "Venues").dig("venues", "list"))
      end

      # The audience's people: promoters, DJs, drag artists and acts.
      # @return [Array<Person>]
      def people
        Person.list(shaped(Queries::LISTING_TYPES, :people, nil, "People").dig("people", "list"))
      end

      # The audience's locales.
      # @return [Array<Locale>]
      def locales
        Locale.list(shaped(Queries::LISTING_TYPES, :locales, nil, "Locales")["locales"])
      end

      # The locale closest to a point, or nil when the audience has none.
      # @param near [Coordinate]
      # @return [Locale, nil]
      # @example
      #   session.closest_locale(Audience::Kit::Coordinate.new(latitude: 33.45, longitude: -112.07))
      def closest_locale(near)
        data = shaped(Queries::LISTING_TYPES, :closest_locale, { "near" => near.to_input }, "ClosestLocale")
        Locale.from(data["closestLocale"])
      end

      # Records the signed-in person's position and says where that is (+venue+, +locale+, +nearbyVenues+,
      # +audience+). Select the fields the app needs and read the result yourself.
      # @param position [Coordinate]
      # @param fields [String] e.g. +"venue { id name } locale { id name }"+
      # @return [Hash]
      def report_location(position, fields)
        data = graphql(Queries.report_location(fields), { "position" => position.to_input },
                       operation_name: "ReportLocation")
        object(data, "reportLocation")
      end

      # Everything the audience lists, read in one go: the audience, its locales, venues, people, upcoming events and
      # event series. A part whose module the audience doesn't have comes back empty.
      # @return [Community]
      def community
        Community.new(audience: optional { audience }, locales: optional { locales } || [],
                      venues: optional { venues } || [], people: optional { people } || [],
                      events: optional { events } || [], event_series: optional { event_series } || [])
      end

      # The audience's events: upcoming (soonest first) or past, for one locale or venue when given.
      # @param window [String] UPCOMING or PAST
      # @param locale_id [String, nil]
      # @param venue_id [String, nil]
      # @param first [Integer]
      # @return [Array<Event>]
      def events(window: "UPCOMING", locale_id: nil, venue_id: nil, first: 100)
        variables = { "window" => window, "first" => first, "localeId" => locale_id, "venueId" => venue_id }.compact
        Event.list(shaped(Queries::EVENT_TYPES, :events, variables, "Events").dig("events", "list"))
      end

      # One event, or nil when there is none with that ID.
      # @param id [String]
      # @return [Event, nil]
      def event(id)
        Event.from(shaped(Queries::EVENT_TYPES, :event, { "id" => id }, "Event").dig("events", "event"))
      end

      # The audience's recurring event series.
      # @return [Array<EventSeries>]
      def event_series(locale_id: nil, venue_id: nil, first: 100)
        variables = { "first" => first, "localeId" => locale_id, "venueId" => venue_id }.compact
        EventSeries.list(shaped(Queries::EVENT_TYPES, :event_series, variables, "EventSeries").dig("events", "series"))
      end

      # A venue's page: the venue with its description, profile (address, phone, website, social links), chat
      # (whether open, and its latest +recent_messages+ messages) and upcoming events, as far as the audience's
      # modules go. Nil when there is no venue with that ID.
      # @param id [String]
      # @param recent_messages [Integer]
      # @return [Venue, nil]
      def venue_detail(id, recent_messages: 20)
        data = shaped(Queries::VENUE_DETAIL_TYPES, :venue_detail, { "id" => id, "recentMessages" => recent_messages },
                      "VenueDetail")
        Venue.from(data.dig("venues", "venue"))
      end

      # Which type a global ID names (+__typename+), or nil when there is no such node.
      # @return [String, nil]
      def node_type(id)
        type = graphql(Queries::NODE, { "id" => id }, operation_name: "Node").dig("node", "__typename")
        type.is_a?(String) ? type : nil
      end

      # @!endgroup

      # @!group Public listings (service token with public:read)

      # One page (from 1) of the audience's public listings: up to 500 venues, then events, then posts, as its
      # websites show them.
      # @param page [Integer]
      # @return [PublicListingsPage]
      def public_listings_page(page = 1)
        PublicListingsPage.from_h(json(request("/v1/public/listings", query: { "page" => [1, page].max })))
      end

      # Every public listing, page by page.
      # @return [Array<PublicListing>]
      def public_listings
        listings = []
        page = 1
        loop do
          found = public_listings_page(page)
          listings.concat(found.listings)
          return listings if found.next_page.nil? || found.next_page <= page

          page = found.next_page
        end
      end

      # One public listing, or nil when there's none.
      # @param kind [String, Symbol] venue, event or post
      # @param id [String]
      # @return [PublicListing, nil]
      # @raise [ArgumentError] for any other kind
      def public_listing(kind, id)
        path = { "venue" => "venues", "event" => "events", "post" => "posts" }.fetch(kind.to_s) do
          raise ArgumentError, "A listing is a venue, event or post, not #{kind}."
        end
        PublicListing.from(json(request("/v1/public/#{path}/#{URI.encode_uri_component(id)}")))
      rescue Error => e
        raise unless e.code == Error::NOT_FOUND
      end

      # Tonight at a venue, as a screen facing the room shows it: tonight's event, who's on and what's next.
      # @return [Hash]
      def public_tonight(venue_id)
        json(request("/v1/public/venues/#{URI.encode_uri_component(venue_id)}/tonight"))
      end

      # @!endgroup

      # @!group RSVP, tribes and notifications

      # Answers an event's RSVP and returns the person's answer as stored.
      # @param event_id [String]
      # @param state [String] ATTENDING, MAYBE, DECLINED or UNSURE
      # @return [String]
      def rsvp_event(event_id, state)
        data = graphql(Queries::RSVP_EVENT, { "eventId" => event_id, "state" => state }, operation_name: "RSVPEvent")
        mine = data.dig("rsvpEvent", "event", "rsvp", "mine")
        raise Error.decoding("The RSVP had no answer.") unless mine.is_a?(String)

        mine
      end

      # Takes back the signed-in person's RSVP, as if they'd never answered, and returns the event's RSVPs
      # afterwards. Someone holding a ticket stays going.
      # @return [EventRSVP]
      def cancel_rsvp(event_id)
        data = graphql(Queries::CANCEL_RSVP, { "eventId" => event_id }, operation_name: "CancelRSVP")
        EventRSVP.from(data.dig("cancelRsvp", "event", "rsvp")) || raise(Error.decoding("The response had no rsvp."))
      end

      # Who's going to an event and the first +first+ of them, or nil when there's no such event.
      # @return [EventRSVP, nil]
      def event_rsvp(event_id, first: 50)
        data = graphql(Queries::EVENT_RSVP, { "id" => event_id, "first" => first }, operation_name: "EventRSVP")
        EventRSVP.from(data.dig("events", "event", "rsvp"))
      end

      # The tribes people can identify with here, and the signed-in person's own.
      # @return [Tribes]
      def tribes
        data = graphql(Queries::TRIBES, operation_name: "Tribes")
        Tribes.new(tribes: Tag.list(data["tribes"]), mine: TribeIdentification.list(data.dig("me", "self", "tribes")))
      end

      # Identifies the signed-in person with a tribe and returns their tribes.
      # @param tag_id [String]
      # @param private [Boolean, nil] whether only they see it
      # @return [Array<TribeIdentification>]
      def identify_with_tribe(tag_id, private: nil)
        data = graphql(Queries::IDENTIFY_WITH_TRIBE, { "tagId" => tag_id, "isPrivate" => private }.compact,
                       operation_name: "IdentifyWithTribe")
        TribeIdentification.list(object(data, "identifyWithTribe")["tribes"])
      end

      # Removes a tribe from the signed-in person and returns their tribes.
      # @return [Array<TribeIdentification>]
      def leave_tribe(tag_id)
        data = graphql(Queries::LEAVE_TRIBE, { "tagId" => tag_id }, operation_name: "LeaveTribe")
        TribeIdentification.list(object(data, "leaveTribe")["tribes"])
      end

      # Registers a push notification token for the signed-in person.
      # @return [Boolean] whether the API took it
      def register_device(notification_token, app_id: nil, sandbox: nil)
        variables = { "notificationToken" => notification_token, "appId" => app_id, "sandbox" => sandbox }.compact
        graphql(Queries::REGISTER_DEVICE, variables, operation_name: "RegisterDevice")
          .dig("registerDevice", "registered") == true
      end

      # @!endgroup

      # @!group Cover and coat check

      # A venue's cover charge tonight, with the signed-in person's pass and coat check ticket if they have them; nil
      # when there is no such venue.
      # @return [VenueCover, nil]
      def venue_cover(venue_id)
        VenueCover.from(shaped(Queries::VENUE_TICKET_TYPES, :venue_cover, { "id" => venue_id }, "VenueCover")
                          .dig("venues", "venue"))
      end

      # Every way into a venue on a night.
      # @param night [String, nil] +YYYY-MM-DD+; tonight by default
      # @return [Array<AdmissionOffer>]
      def venue_offers(venue_id, night: nil)
        variables = { "id" => venue_id, "night" => night }.compact
        AdmissionOffer.list(shaped(Queries::VENUE_TICKET_TYPES, :venue_offers, variables, "VenueOffers")
                              .dig("venues", "venue", "tickets", "offers"))
      end

      # The signed-in person's admissions (cover passes and coat check tickets), newest first.
      # @return [Array<Admission>]
      def admissions
        Admission.list(graphql(Queries::ADMISSIONS, operation_name: "Admissions").dig("me", "cover", "admissions"))
      end

      # Starts buying tonight's cover at a venue: the pending admission and the payment provider's keys. For a Stripe
      # venue, finish the payment with Stripe.js and call {#confirm_cover}; for a Square venue, make a payment token
      # and call {#pay_cover}. Asking again the same night returns the same pass.
      # @param amount_cents [Integer, nil] on a sliding scale, what the buyer chose; the suggested amount by default
      # @return [CoverPurchase]
      def buy_cover(venue_id, amount_cents: nil, currency: "usd")
        variables = { "venueId" => venue_id }
        variables["amount"] = { "cents" => amount_cents, "currency" => currency } if amount_cents
        CoverPurchase.new(object(graphql(Queries::BUY_COVER, variables, operation_name: "BuyCover"), "buyCover"))
      end

      # Starts paying tonight's coat check at a venue for +quantity+ coats, the same way as {#buy_cover}.
      # @return [CoverPurchase]
      def buy_coat_check(venue_id, quantity: 1)
        data = graphql(Queries::BUY_COAT_CHECK, { "venueId" => venue_id, "quantity" => quantity },
                       operation_name: "BuyCoatCheck")
        CoverPurchase.new(object(data, "buyCoatCheck"))
      end

      # Pays a Square venue's pending admission with a payment token from Square's Web Payments SDK.
      # @return [Admission]
      def pay_cover(admission_id, source_id:, verification_token: nil)
        variables = { "admissionId" => admission_id, "sourceId" => source_id,
                      "verificationToken" => verification_token }.compact
        admission(graphql(Queries::PAY_COVER, variables, operation_name: "PayCover"), "payCover")
      end

      # Confirms a Stripe venue's admission once Stripe has taken the payment.
      # @return [Admission]
      def confirm_cover(admission_id)
        data = graphql(Queries::CONFIRM_COVER, { "admissionId" => admission_id }, operation_name: "ConfirmCover")
        admission(data, "confirmCover")
      end

      # Refunds an admission that is {Admission#refundable?}.
      # @return [Admission]
      def refund_admission(admission_id)
        data = graphql(Queries::REFUND_ADMISSION, { "admissionId" => admission_id }, operation_name: "RefundAdmission")
        admission(data, "refundAdmission")
      end

      # @!endgroup

      # @!group News (Soapbox)

      # The audience's live articles, pinned first, then newest: a locale's news, or one publication's, when given.
      # Empty when the audience doesn't have Soapbox.
      # @return [Array<Article>]
      def articles(locale_id: nil, publication_id: nil, first: nil)
        variables = { "localeId" => locale_id, "publicationId" => publication_id, "first" => first }.compact
        Article.list(shaped(Queries::SOAPBOX_TYPES, :articles, variables.empty? ? nil : variables, "Articles")
                       .dig("soapbox", "articles"))
      end

      # A page of the audience's live articles, for lists that "Show more". Pass the last page's
      # {ArticlesPage#end_cursor} as +after+ for the next.
      # @return [ArticlesPage]
      def articles_page(locale_id: nil, publication_id: nil, first: 20, after: nil)
        variables = { "localeId" => locale_id, "publicationId" => publication_id, "first" => first,
                      "after" => after }.compact
        ArticlesPage.from_connection(shaped(Queries::SOAPBOX_TYPES, :articles_page, variables, "ArticlesPage")
                                       .dig("soapbox", "articles"))
      end

      # The audience's national news: articles its admins featured nationally in the last 14 days, most recently
      # featured first (a locale's share of it, when given).
      # @return [Array<Article>]
      def national_articles(locale_id: nil, first: nil)
        variables = { "localeId" => locale_id, "first" => first }.compact
        data = shaped(Queries::SOAPBOX_TYPES, :national_articles, variables.empty? ? nil : variables,
                      "NationalArticles")
        Article.list(data.dig("soapbox", "articles"))
      end

      # One article with its body and what it's about; nil when there's none, or the audience has no Soapbox.
      # @return [Article, nil]
      def article(id)
        Article.from(shaped(Queries::SOAPBOX_TYPES, :article, { "id" => id }, "Article").dig("soapbox", "article"))
      end

      # Live articles about a venue, event or person, newest first, or a locale's news ("In the news").
      # @param topic [String, Symbol] venue, event, person or locale
      # @return [Array<Article>]
      def articles_about(topic, id, first: nil)
        type, document = Queries.articles_about(topic)
        data = shaped_graphql(Queries::SOAPBOX_TYPES + [type], { "id" => id, "first" => first }.compact,
                              "ArticlesAbout", &document)
        listing = data.dig("venues", "venue") || data.dig("events", "event") || data.dig("people", "person") ||
                  data["locale"]
        Article.list(listing.is_a?(Hash) ? listing.dig("articles", "list") : nil)
      end

      # The audience's publications.
      # @return [Array<Publication>]
      def publications
        Publication.list(shaped(Queries::SOAPBOX_TYPES, :publications, nil, "Publications")
                           .dig("soapbox", "publications"))
      end

      # The publications covering a locale, the "local publishers" at the top of its news.
      # @return [Array<Publication>]
      def local_publications(locale_id)
        publications.select { |publication| publication.locale&.id&.casecmp?(locale_id) }
      end

      # One publication, for its page and its "Write an op-ed" button.
      # @return [Publication, nil]
      def publication(id)
        Publication.from(shaped(Queries::SOAPBOX_TYPES, :publication, { "id" => id }, "Publication")
                           .dig("soapbox", "publication"))
      end

      # The op-eds the signed-in person sent, newest first, with their status and the publication's note.
      # @return [Array<Article>]
      def my_op_eds
        Article.list(shaped(Queries::SOAPBOX_TYPES, :my_op_eds, nil, "MyOpEds").dig("soapbox", "myOpEds"))
      end

      # Sends a publication an op-ed under the signed-in person's name (+byline+ overrides it). The publication runs
      # it or declines it with a note; {#my_op_eds} shows which.
      # @return [Article]
      def submit_op_ed(publication_id, title:, body:, summary: nil, byline: nil)
        variables = { "publicationId" => publication_id, "title" => title, "body" => body, "summary" => summary,
                      "byline" => byline }
        data = graphql(Queries::SUBMIT_OP_ED, variables, operation_name: "SubmitOpEd")
        Article.new(object(object(data, "submitOpEd"), "article"))
      end

      # @!endgroup

      # @!group Calendar subscriptions

      # The signed-in person's calendar subscription, or nil before they made one.
      # @return [CalendarFeed, nil]
      def calendar_feed
        CalendarFeed.from(graphql(Queries::CALENDAR_FEED, operation_name: "CalendarFeed").dig("me", "calendarFeed"))
      end

      # Their subscription, made on first ask; +reset+ gives it a new link, so the old one stops working.
      # @return [CalendarFeed]
      def create_calendar_feed(reset: false)
        data = graphql(Queries::CREATE_CALENDAR_FEED, { "reset" => reset }, operation_name: "CreateCalendarFeed")
        CalendarFeed.new(object(object(data, "createCalendarFeed"), "calendarFeed"))
      end

      # Follows a venue in their subscription, so every event there shows up in their calendar (or, with
      # +following: false+, stops). Makes the subscription on first ask.
      # @return [CalendarFeed]
      def follow_venue_in_calendar(venue_id, following: true)
        data = graphql(Queries::SET_CALENDAR_FEED_VENUE, { "venueId" => venue_id, "following" => following },
                       operation_name: "SetCalendarFeedVenue")
        CalendarFeed.new(object(object(data, "setCalendarFeedVenue"), "calendarFeed"))
      end

      # Ends their subscription: calendars subscribed to it stop updating.
      # @return [Boolean]
      def delete_calendar_feed
        graphql(Queries::DELETE_CALENDAR_FEED, operation_name: "DeleteCalendarFeed")
          .dig("deleteCalendarFeed", "deleted") == true
      end

      # @!endgroup

      # @!group Chat and moderation

      # Posts a message as the signed-in person in a venue's or locale's chat room, answering a prompt when
      # +prompt_id+ is given.
      # @param message [String]
      # @param venue_id [String, nil]
      # @param locale_id [String, nil]
      # @param prompt_id [String, nil]
      # @return [ChatMessage]
      def send_chat_message(message, venue_id: nil, locale_id: nil, prompt_id: nil)
        input = { "venueId" => venue_id, "localeId" => locale_id, "message" => message,
                  "promptId" => prompt_id }.compact
        data = graphql(Queries::SEND_CHAT_MESSAGE, { "input" => input }, operation_name: "SendMyChatMessage")
        ChatMessage.new(object(object(data, "sendMyChatMessage"), "message"))
      end

      # Removes one of the signed-in person's own chat messages.
      # @return [String] the removed message's ID
      def remove_chat_message(message_id)
        data = graphql(Queries::REMOVE_CHAT_MESSAGE, { "messageId" => message_id },
                       operation_name: "RemoveMyChatMessage")
        deleted = data.dig("removeMyChatMessage", "deletedId")
        deleted.is_a?(String) ? deleted : message_id
      end

      # Files a report with the audience's admins (App Store guideline 1.2, Google Play's user-generated content
      # policy). Offer {ReportTarget::REASONS} as reasons.
      # @param target_type [String] one of {ReportTarget}'s constants
      # @param id [String]
      # @param reason [String, nil]
      # @param block [Boolean] whether to block the person behind it too
      # @return [ReportResult]
      def report_content(target_type, id, reason: nil, block: false)
        data = graphql(Queries::REPORT_CONTENT,
                       { "targetType" => target_type, "targetId" => id, "reason" => reason, "block" => block },
                       operation_name: "ReportContent")
        result = data["reportContent"].is_a?(Hash) ? data["reportContent"] : {}
        ReportResult.new(reported: result["reported"] == true, blocked: result["blocked"] == true)
      end

      # Blocks a member (their user ID): they and the signed-in person stop seeing each other's messages.
      # @return [void]
      def block_user(user_id)
        graphql(Queries::BLOCK_USER, { "userId" => user_id }, operation_name: "BlockUser")
        nil
      end

      # Unblocks a member blocked with {#block_user} or a report.
      # @return [void]
      def unblock_user(user_id)
        graphql(Queries::UNBLOCK_USER, { "userId" => user_id }, operation_name: "UnblockUser")
        nil
      end

      # @!endgroup

      private

      def shaped(types, document, variables, operation_name)
        shaped_graphql(types, variables, operation_name) { |shape| Queries.public_send(document, shape) }
      end

      def optional
        yield
      rescue Error => e
        raise unless e.undefined_field?
      end

      def object(data, key)
        data[key].is_a?(Hash) ? data[key] : raise(Error.decoding("The response had no #{key}."))
      end

      def admission(data, key)
        Admission.new(object(object(data, key), "admission"))
      end

      def json(body)
        decoded = JSON.parse(body)
        decoded.is_a?(Hash) ? decoded : raise(Error.decoding("The response was not a JSON object."))
      rescue JSON::ParserError => e
        raise Error.decoding(e.message)
      end
    end
  end
end
