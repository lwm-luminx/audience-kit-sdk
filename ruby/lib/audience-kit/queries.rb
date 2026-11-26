# frozen_string_literal: true

module Audience
  module Kit
    # The GraphQL documents behind {Operations}: the same operations the Swift, Kotlin, Node, Python and PHP SDKs
    # run. Documents with module fields take the audience's {SchemaShape}: the API leaves a module's fields out of an
    # audience that hasn't installed it, and asking for one fails the whole operation.
    #
    # Run your own operations with {Session#graphql}; the field lists here (+Queries.event_fields(shape)+,
    # {ADMISSION_FIELDS}...) are there to build them from.
    module Queries
      # A selection of fields, for documents of your own.
      PAGE_FIELDS = "id name photoUrl bannerUrl"
      # A tag on a venue, person or event: its name and chip color.
      TAG_FIELDS = "id name color"
      # A selection of fields, for documents of your own.
      MONEY_FIELDS = "cents currency"
      # A selection of fields, for documents of your own.
      PROFILE_FIELDS = "id name avatarUrl"
      # A cover charge: the amount, fee and total, its coat check, and on a sliding scale the range to pick from.
      COVER_CHARGE_FIELDS = "amount { cents currency } total { cents currency } fee { cents currency } " \
                            "night from payable event { id name } " \
                            "coatCheck { amount { cents currency } fee { cents currency } total { cents currency } " \
                            "night payable } " \
                            "scale { min { cents currency } max { cents currency } suggested { cents currency } }"
      # An admission: the pass secret the door code is made from, and the buyer's profile for the door.
      ADMISSION_FIELDS = "id status kind night quantity tier claimCheckNumber amount { cents currency } " \
                         "fee { cents currency } total { cents currency } isRefundable passSecret scanCount " \
                         "checkedInAt createdAt profile { id name avatarUrl } venue { id name photoUrl } " \
                         "event { id name }"
      # An event's rsvp for the signed-in person: how many are going, and their own answer and why.
      RSVP_FIELDS = "count mine mineSource"
      # A selection of fields, for documents of your own.
      EVENT_ATTENDEE_FIELDS = "profile { id name avatarUrl } friend source"
      # A selection of fields, for documents of your own.
      ADMISSION_OFFER_FIELDS = "price { cents currency } url seller { key name }"
      # A selection of fields, for documents of your own.
      CHAT_MESSAGE_FIELDS = "id body message name userId avatarUrl photoUrl sentAt role kind title pinned"
      # A selection of fields, for documents of your own.
      PURCHASE_FIELDS = "provider paymentIntentClientSecret publishableKey stripeAccountId squareApplicationId " \
                        "squareLocationId"

      # The types whose fields the listing documents depend on.
      LISTING_TYPES = %w[Locale ListingProfile Venue Location Person Event].freeze
      # The types the event documents depend on.
      EVENT_TYPES = (LISTING_TYPES + %w[EventSeries EventTickets EventPeopleView]).freeze
      # The types +venue_cover+ and +venue_offers+ depend on.
      VENUE_TICKET_TYPES = %w[Venue VenueTickets].freeze
      # The types the venue page document depends on.
      VENUE_DETAIL_TYPES = EVENT_TYPES
      # The types the Soapbox documents depend on: the root's +soapbox+ and each listing's +articles+.
      SOAPBOX_TYPES = %w[Audience Venue Event Person Locale Article Publication].freeze

      # A selection of fields, for documents of your own.
      PUBLICATION_SUMMARY_FIELDS = "id name photoUrl trusted acceptsOpEds"
      # A selection of fields, for documents of your own.
      ARTICLE_FIELDS = "id slug title summary byline kind publishedAt edited pinned teaser canonicalUrl " \
                       "disclosure heroPhotoUrl heroAltText publication { #{PUBLICATION_SUMMARY_FIELDS} }".freeze
      # A selection of fields, for documents of your own.
      ARTICLE_SUBJECT_FIELDS = "venues { id name } events { id name } people { id name } locales { id name }"
      # A selection of fields, for documents of your own.
      PUBLICATION_FIELDS = "id name masthead about websiteUrl photoUrl trusted acceptsOpEds opEdGuidelines " \
                           "locale { id name } person { id name }"
      # A selection of fields, for documents of your own.
      CALENDAR_FEED_FIELDS = "url webcalUrl googleUrl venues { id }"

      # The +query Audience+ document.
      AUDIENCE = <<~GRAPHQL
        query Audience {
          id name subdomain theme { preset tagline light { name value } dark { name value } }
        }
      GRAPHQL

      # The +query Me+ document.
      ME = <<~GRAPHQL
        query Me {
          me { self { id name firstName lastName emailAddress isAdmin presence } }
        }
      GRAPHQL

      # The +mutation RSVPEvent+ document.
      RSVP_EVENT = <<~GRAPHQL
        mutation RSVPEvent($eventId: ID!, $state: RSVPState!) {
          rsvpEvent(input: { eventId: $eventId, state: $state }) { event { id rsvp { count mine mineSource } } }
        }
      GRAPHQL

      # Takes back the signed-in person's RSVP, as if they'd never answered.
      CANCEL_RSVP = <<~GRAPHQL
        mutation CancelRSVP($eventId: ID!) {
          cancelRsvp(input: { eventId: $eventId }) { event { id rsvp { count mine mineSource } } }
        }
      GRAPHQL

      # Who's going to an event: the counts (staff-only ones too) and the first +$first+ attendees.
      EVENT_RSVP = <<~GRAPHQL
        query EventRSVP($id: ID!, $first: Int) {
          events {
            event(id: $id) {
              id
              rsvp {
                count mine mineSource counts { going interested tickets }
                attendees(first: $first) { nodes { profile { id name avatarUrl } friend source } }
              }
            }
          }
        }
      GRAPHQL

      # The tribes people can identify with here, and the signed-in person's own.
      TRIBES = <<~GRAPHQL
        query Tribes {
          id tribes: tags(tribes: true) { id name color tribe }
          me { self { id tribes { isPrivate tag { id name color tribe } } } }
        }
      GRAPHQL

      # The +mutation IdentifyWithTribe+ document.
      IDENTIFY_WITH_TRIBE = <<~GRAPHQL
        mutation IdentifyWithTribe($tagId: ID!, $isPrivate: Boolean) {
          identifyWithTribe(input: { tagId: $tagId, isPrivate: $isPrivate }) {
            tribes { isPrivate tag { id name color tribe } }
          }
        }
      GRAPHQL

      # The +mutation LeaveTribe+ document.
      LEAVE_TRIBE = <<~GRAPHQL
        mutation LeaveTribe($tagId: ID!) {
          leaveTribe(input: { tagId: $tagId }) { tribes { isPrivate tag { id name color tribe } } }
        }
      GRAPHQL

      # The +mutation RegisterDevice+ document.
      REGISTER_DEVICE = <<~GRAPHQL
        mutation RegisterDevice($notificationToken: String!, $appId: String, $sandbox: Boolean) {
          registerDevice(input: { notificationToken: $notificationToken, appId: $appId, sandbox: $sandbox }) { registered }
        }
      GRAPHQL

      # The +query Node+ document.
      NODE = <<~GRAPHQL
        query Node($id: ID!) {
          node(id: $id) { __typename id }
        }
      GRAPHQL

      # The +mutation SendMyChatMessage+ document.
      SEND_CHAT_MESSAGE = <<~GRAPHQL.freeze
        mutation SendMyChatMessage($input: ChatMessageSendOwnInput!) {
          sendMyChatMessage(input: $input) { message { #{CHAT_MESSAGE_FIELDS} } }
        }
      GRAPHQL

      # The +mutation RemoveMyChatMessage+ document.
      REMOVE_CHAT_MESSAGE = <<~GRAPHQL
        mutation RemoveMyChatMessage($messageId: ID!) {
          removeMyChatMessage(input: { messageId: $messageId }) { deletedId }
        }
      GRAPHQL

      # Deletes the signed-in person's account for good.
      DELETE_ACCOUNT = <<~GRAPHQL
        mutation DeleteAccount($confirm: Boolean!) {
          deleteAccount(input: { confirm: $confirm }) { deleted }
        }
      GRAPHQL

      # Files a report with the audience's admins, blocking the person behind it when +$block+.
      REPORT_CONTENT = <<~GRAPHQL
        mutation ReportContent($targetType: ReportTarget!, $targetId: ID!, $reason: String, $block: Boolean) {
          reportContent(input: { targetType: $targetType, targetId: $targetId, reason: $reason, block: $block }) {
            reported
            blocked
          }
        }
      GRAPHQL

      # The +mutation BlockUser+ document.
      BLOCK_USER = <<~GRAPHQL
        mutation BlockUser($userId: ID!) {
          blockUser(input: { userId: $userId }) { blockedUsers { id } }
        }
      GRAPHQL

      # The +mutation UnblockUser+ document.
      UNBLOCK_USER = <<~GRAPHQL
        mutation UnblockUser($userId: ID!) {
          unblockUser(input: { userId: $userId }) { blockedUsers { id } }
        }
      GRAPHQL

      # The +query CalendarFeed+ document.
      CALENDAR_FEED = <<~GRAPHQL.freeze
        query CalendarFeed {
          me { calendarFeed { #{CALENDAR_FEED_FIELDS} } }
        }
      GRAPHQL

      # The +mutation CreateCalendarFeed+ document.
      CREATE_CALENDAR_FEED = <<~GRAPHQL.freeze
        mutation CreateCalendarFeed($reset: Boolean) {
          createCalendarFeed(input: { reset: $reset }) { calendarFeed { #{CALENDAR_FEED_FIELDS} } }
        }
      GRAPHQL

      # The +mutation SetCalendarFeedVenue+ document.
      SET_CALENDAR_FEED_VENUE = <<~GRAPHQL.freeze
        mutation SetCalendarFeedVenue($venueId: ID!, $following: Boolean) {
          setCalendarFeedVenue(input: { venueId: $venueId, following: $following }) { calendarFeed { #{CALENDAR_FEED_FIELDS} } }
        }
      GRAPHQL

      # The +mutation DeleteCalendarFeed+ document.
      DELETE_CALENDAR_FEED = <<~GRAPHQL
        mutation DeleteCalendarFeed {
          deleteCalendarFeed(input: {}) { deleted }
        }
      GRAPHQL

      # The +query Admissions+ document.
      ADMISSIONS = <<~GRAPHQL.freeze
        query Admissions {
          me { cover { admissions { nodes { #{ADMISSION_FIELDS} } } } }
        }
      GRAPHQL

      # The +mutation BuyCover+ document.
      BUY_COVER = <<~GRAPHQL.freeze
        mutation BuyCover($venueId: ID!, $amount: MoneyInput) {
          buyCover(input: { venueId: $venueId, amount: $amount }) {
            admission { #{ADMISSION_FIELDS} }
            #{PURCHASE_FIELDS}
          }
        }
      GRAPHQL

      # The +mutation BuyCoatCheck+ document.
      BUY_COAT_CHECK = <<~GRAPHQL.freeze
        mutation BuyCoatCheck($venueId: ID!, $quantity: Int) {
          buyCoatCheck(input: { venueId: $venueId, quantity: $quantity }) {
            admission { #{ADMISSION_FIELDS} }
            #{PURCHASE_FIELDS}
          }
        }
      GRAPHQL

      # The +mutation PayCover+ document.
      PAY_COVER = <<~GRAPHQL.freeze
        mutation PayCover($admissionId: ID!, $sourceId: String!, $verificationToken: String) {
          payCover(input: { admissionId: $admissionId, sourceId: $sourceId, verificationToken: $verificationToken }) {
            admission { #{ADMISSION_FIELDS} }
          }
        }
      GRAPHQL

      # The +mutation ConfirmCover+ document.
      CONFIRM_COVER = <<~GRAPHQL.freeze
        mutation ConfirmCover($admissionId: ID!) {
          confirmCover(input: { admissionId: $admissionId }) { admission { #{ADMISSION_FIELDS} } }
        }
      GRAPHQL

      # The +mutation RefundAdmission+ document.
      REFUND_ADMISSION = <<~GRAPHQL.freeze
        mutation RefundAdmission($admissionId: ID!) {
          refundAdmission(input: { admissionId: $admissionId }) { admission { #{ADMISSION_FIELDS} } }
        }
      GRAPHQL

      # The +mutation SubmitOpEd+ document.
      SUBMIT_OP_ED = <<~GRAPHQL.freeze
        mutation SubmitOpEd($publicationId: ID!, $title: String!, $body: String!, $summary: String, $byline: String) {
          submitOpEd(input: { publicationId: $publicationId, title: $title, body: $body, summary: $summary, byline: $byline }) {
            article { #{ARTICLE_FIELDS} status reviewNote submittedAt }
          }
        }
      GRAPHQL

      module_function

      # Records the person's position and says where that is: +venue+ when they're in one, else +locale+ and its
      # +nearbyVenues+, plus +audience+. Select the fields the app needs.
      # @param fields [String] e.g. +"venue { id name } locale { id name }"+
      # @return [String]
      def report_location(fields)
        "mutation ReportLocation($position: CoordinatesInput!) {\n  reportLocation(input: { position: $position }) " \
          "{ #{fields} }\n}\n"
      end

      # A chat room's subscription (+kind+ :venue or :locale), aliased to +room+ whichever field it is, for an app
      # with its own Action Cable client. With +watch+, a staff member watches without joining.
      # @return [String]
      def chat_room(kind, watch: false)
        field, argument = kind.to_s == "venue" ? %w[venueChat venueId] : %w[localeChat localeId]
        <<~GRAPHQL
          subscription ChatRoom($id: ID!) {
            room: #{field}(#{argument}: $id#{", watch: true" if watch}) {
              __typename
              ... on ChatJoined {
                outOfRange
                roster { people { userId name avatarUrl friend } }
                history { message { ...Line } }
                pinnedMessage { message { ...Line } }
              }
              ... on ChatMessagePosted { message { ...Line } }
              ... on ChatMessageUpdated { message { ...Line } }
              ... on ChatMessageRemoved { messageId }
              ... on ChatPinChanged { messageId pinned announcement { ...Line } }
              ... on ChatRoomCleared { clearedAt expired }
              ... on ChatPresenceChanged { userId name avatarUrl presence }
              ... on ChatRangeChanged { outOfRange }
              ... on ChatLeft { reason }
            }
          }
          fragment Line on ChatMessage { #{CHAT_MESSAGE_FIELDS} }
        GRAPHQL
      end

      # A locale, with its Google place ID (Listings and Google Places).
      def locale_fields(shape)
        places = shape.has?("Locale", "profile") && shape.has?("ListingProfile", "places")
        "id name label cityNames bannerUrl#{" profile { places { placeId } }" if places}"
      end

      # A venue in a list: its Facebook Page (Listings and Facebook) and its location's Google place ID.
      def venue_fields(shape)
        page = shape.has?("Venue", "profile") && shape.has?("ListingProfile", "facebook")
        place = shape.has?("Location", "places")
        "id name hidden order photoUrl bannerUrl#{" profile { facebook { page { #{PAGE_FIELDS} } } }" if page} " \
          "locale { #{locale_fields(shape)} } location { id point address#{" places { placeId }" if place} } " \
          "tags { #{TAG_FIELDS} }"
      end

      # A person's home venue, and which of the signed-in person's friends are there now (Friends).
      def person_venue_fields(shape)
        friends = shape.has?("Venue", "friends")
        "id name photoUrl locale { id name }#{" friends { list { nodes { id name facebookId presence } } }" if friends}"
      end

      # One of a person's events (+PersonEvent+).
      def person_event_fields(shape)
        venue = shape.has?("Event", "venue") ? " venue { name venue { #{person_venue_fields(shape)} } }" : ""
        "id name startAt locale { id name }#{venue} tags { #{TAG_FIELDS} }"
      end

      # The +venues+ document or selection, for what +shape+ says the audience has.
      # @param shape [SchemaShape]
      # @return [String]
      def venues(shape)
        "query Venues {\n  venues { list { nodes { #{venue_fields(shape)} } } }\n}\n"
      end

      # The +people+ document or selection, for what +shape+ says the audience has.
      # @param shape [SchemaShape]
      # @return [String]
      def people(shape)
        page = if shape.has?("Person", "profile") && shape.has?("ListingProfile", "facebook")
                 " profile { facebook { page { #{PAGE_FIELDS} } } }"
               end
        venues = " venues { home { #{person_venue_fields(shape)} } }" if shape.has?("Person", "venues")
        if shape.has?("Person", "events")
          events = " events { involvements { edges { relationship role via { id name } node { " \
                   "#{person_event_fields(shape)} } } } }"
        end
        "query People {\n  people { list { nodes { id name avatarUrl bannerUrl order global likeRequired" \
          "#{page}#{venues} locales { id name }#{events} tags { #{TAG_FIELDS} } } } }\n}\n"
      end

      # The +locales+ document or selection, for what +shape+ says the audience has.
      # @param shape [SchemaShape]
      # @return [String]
      def locales(shape)
        "query Locales {\n  locales { #{locale_fields(shape)} }\n}\n"
      end

      # The +closest_locale+ document or selection, for what +shape+ says the audience has.
      # @param shape [SchemaShape]
      # @return [String]
      def closest_locale(shape)
        "query ClosestLocale($near: CoordinatesInput!) {\n  closestLocale(near: $near) { #{locale_fields(shape)} }\n}\n"
      end

      # A venue's cover tonight, or just the venue where the audience doesn't have the Ticketing and Cover modules.
      def venue_cover(shape)
        if shape.has?("Venue", "tickets") && shape.has?("VenueTickets", "cover")
          cover = " tickets { cover { charge { #{COVER_CHARGE_FIELDS} } viewerAdmission { #{ADMISSION_FIELDS} } " \
                  "viewerCoatCheck { #{ADMISSION_FIELDS} } } }"
        end
        "query VenueCover($id: ID!) {\n  venues { venue(id: $id) { id name#{cover} } }\n}\n"
      end

      # Every way into a venue on a night, or just the venue where the audience doesn't have Ticketing.
      def venue_offers(shape)
        # A variable the document doesn't use is an error, so $night goes with the field.
        if shape.has?("Venue", "tickets")
          "query VenueOffers($id: ID!, $night: ISO8601Date) {\n  venues { venue(id: $id) { id tickets " \
            "{ offers(night: $night) { nodes { #{ADMISSION_OFFER_FIELDS} } } } } }\n}\n"
        else
          "query VenueOffers($id: ID!) {\n  venues { venue(id: $id) { id } }\n}\n"
        end
      end

      # The Ticketing module's part of an event, with the Cover module's charge when the audience has it.
      def event_tickets_fields(shape)
        cover = " cover { charge { #{COVER_CHARGE_FIELDS} } }" if shape.has?("EventTickets", "cover")
        "tickets { url offers { nodes { #{ADMISSION_OFFER_FIELDS} } }#{cover} }"
      end

      # The Venues module's part of an event or series: a display name and the venue.
      def event_venue_fields(shape)
        place = " places { placeId }" if shape.has?("Location", "places")
        "venue { name venue { id name photoUrl location { id point address#{place} } } }"
      end

      # An event: its own fields, then those of the Venues, RSVP, People and Ticketing modules the audience has.
      def event_fields(shape)
        fields = "id name description startAt endAt isFeatured isCanceled bannerUrl sourceUrl " \
                 "locale { #{locale_fields(shape)} } tags { #{TAG_FIELDS} }"
        fields << " #{event_venue_fields(shape)}" if shape.has?("Event", "venue")
        fields << " rsvp { mine count }" if shape.has?("Event", "rsvp")
        if shape.has?("Event", "people")
          jockeys = " jockeys { nodes { id name avatarUrl } } jockeyLabel" if shape.has?("EventPeopleView", "jockeys")
          fields << " people { hosts { nodes { id name avatarUrl } } lineup { nodes { id name avatarUrl } }" \
                    "#{jockeys} }"
        end
        fields << " #{event_tickets_fields(shape)}" if shape.has?("Event", "tickets")
        fields
      end

      # The +event_series_fields+ document or selection, for what +shape+ says the audience has.
      # @param shape [SchemaShape]
      # @return [String]
      def event_series_fields(shape)
        venue = " #{event_venue_fields(shape)}" if shape.has?("EventSeries", "venue")
        "id name description recurrenceText startsOn startTime timeZone durationMinutes bannerUrl " \
          "locale { #{locale_fields(shape)} } tags { #{TAG_FIELDS} }#{venue}"
      end

      # The +events+ document or selection, for what +shape+ says the audience has.
      # @param shape [SchemaShape]
      # @return [String]
      def events(shape)
        "query Events($window: EventWindow, $localeId: ID, $venueId: ID, $first: Int) {\n  " \
          "events { list(window: $window, localeId: $localeId, venueId: $venueId, first: $first) {\n    " \
          "nodes { #{event_fields(shape)} }\n  } }\n}\n"
      end

      # The +event+ document or selection, for what +shape+ says the audience has.
      # @param shape [SchemaShape]
      # @return [String]
      def event(shape)
        "query Event($id: ID!) {\n  events { event(id: $id) { #{event_fields(shape)} } }\n}\n"
      end

      # The +event_series+ document or selection, for what +shape+ says the audience has.
      # @param shape [SchemaShape]
      # @return [String]
      def event_series(shape)
        "query EventSeries($localeId: ID, $venueId: ID, $first: Int) {\n  " \
          "events { series(localeId: $localeId, venueId: $venueId, first: $first) { nodes { " \
          "#{event_series_fields(shape)} } } }\n}\n"
      end

      # A venue's page: the venue and what the modules its audience has add to it.
      def venue_detail(shape)
        fields = "#{venue_fields(shape)} description"
        if shape.has?("Venue", "profile")
          fields << " profile { address phone website socialLinks { nodes { id handle provider url } } }"
        end
        chat = shape.has?("Venue", "chat")
        fields << " chat { open recentMessages(limit: $recentMessages) { nodes { #{CHAT_MESSAGE_FIELDS} } } }" if chat
        if shape.has?("Venue", "events")
          fields << " events { upcoming(first: 20) { nodes { #{event_fields(shape)} } } }"
        end
        "query VenueDetail($id: ID!#{", $recentMessages: Int" if chat}) {\n  " \
          "venues { venue(id: $id) { #{fields} } }\n}\n"
      end

      # The article fields this audience's API has: the tip to read without ads came later.
      def article_fields(shape)
        return ARTICLE_FIELDS unless shape.has?("Article", "viewerAdFree") && shape.has?("Publication", "adFreeOffered")

        "#{ARTICLE_FIELDS.sub(PUBLICATION_SUMMARY_FIELDS, "#{PUBLICATION_SUMMARY_FIELDS} adFreeOffered")} viewerAdFree"
      end

      # The +publication_fields+ document or selection, for what +shape+ says the audience has.
      # @param shape [SchemaShape]
      # @return [String]
      def publication_fields(shape)
        extra = " adFreeOffered adFreeTipCents adFreeDays viewerAdFree viewerAdFreeUntil"
        "#{PUBLICATION_FIELDS}#{extra if shape.has?("Publication", "adFreeOffered")}"
      end

      # The document when the audience has no Soapbox: asks for nothing the helpers read, under the operation's name.
      def no_soapbox(name)
        "query #{name} { id }\n"
      end

      # The +articles+ document or selection, for what +shape+ says the audience has.
      # @param shape [SchemaShape]
      # @return [String]
      def articles(shape)
        return no_soapbox("Articles") unless shape.has?("Audience", "soapbox")

        "query Articles($localeId: ID, $publicationId: ID, $first: Int) {\n  " \
          "soapbox { articles(localeId: $localeId, publicationId: $publicationId, first: $first) {\n    " \
          "nodes { #{article_fields(shape)} }\n  } }\n}\n"
      end

      # A page of the audience's live articles (pinned first, then newest), for lists that load more.
      def articles_page(shape)
        return no_soapbox("ArticlesPage") unless shape.has?("Audience", "soapbox")

        "query ArticlesPage($localeId: ID, $publicationId: ID, $first: Int, $after: String) {\n  " \
          "soapbox { articles(localeId: $localeId, publicationId: $publicationId, first: $first, " \
          "after: $after) {\n    nodes { #{article_fields(shape)} }\n    pageInfo { endCursor hasNextPage }\n  } }\n}\n"
      end

      # The audience's national news; an API from before national news gets a document that asks for none.
      def national_articles(shape)
        unless shape.has?("Audience", "soapbox") && shape.has?("Article", "featuredNationally")
          return no_soapbox("NationalArticles")
        end

        "query NationalArticles($localeId: ID, $first: Int) {\n  " \
          "soapbox { articles(national: true, localeId: $localeId, first: $first) {\n    " \
          "nodes { #{article_fields(shape)} featuredNationally }\n  } }\n}\n"
      end

      # The +article+ document or selection, for what +shape+ says the audience has.
      # @param shape [SchemaShape]
      # @return [String]
      def article(shape)
        return no_soapbox("Article") unless shape.has?("Audience", "soapbox")

        "query Article($id: ID!) {\n  soapbox { article(id: $id) { #{article_fields(shape)} body " \
          "#{ARTICLE_SUBJECT_FIELDS} } }\n}\n"
      end

      # The +publications+ document or selection, for what +shape+ says the audience has.
      # @param shape [SchemaShape]
      # @return [String]
      def publications(shape)
        return no_soapbox("Publications") unless shape.has?("Audience", "soapbox")

        "query Publications {\n  soapbox { publications { #{publication_fields(shape)} } }\n}\n"
      end

      # The +publication+ document or selection, for what +shape+ says the audience has.
      # @param shape [SchemaShape]
      # @return [String]
      def publication(shape)
        return no_soapbox("Publication") unless shape.has?("Audience", "soapbox")

        "query Publication($id: ID!) {\n  soapbox { publication(id: $id) { #{publication_fields(shape)} } }\n}\n"
      end

      # The +my_op_eds+ document or selection, for what +shape+ says the audience has.
      # @param shape [SchemaShape]
      # @return [String]
      def my_op_eds(shape)
        return no_soapbox("MyOpEds") unless shape.has?("Audience", "soapbox")

        "query MyOpEds {\n  soapbox { myOpEds { #{ARTICLE_FIELDS} status reviewNote submittedAt } }\n}\n"
      end

      # Where articles about each kind of listing are read from: its type, and the selection around +articles+.
      ARTICLES_ABOUT = {
        "venue" => ["Venue", "venues { venue(id: $id) { ", " } }"],
        "event" => ["Event", "events { event(id: $id) { ", " } }"],
        "person" => ["Person", "people { person(id: $id) { ", " } }"],
        "locale" => ["Locale", "locale(id: $id) { ", " }"]
      }.freeze

      # Live articles about a venue, event, person or locale: the listing type the document depends on, and a
      # lambda that builds the document for a shape.
      # @param topic [String, Symbol] venue, event, person or locale
      # @return [Array(String, Proc)]
      # @raise [ArgumentError] for any other topic
      def articles_about(topic)
        type, open, close = ARTICLES_ABOUT.fetch(topic.to_s) do
          raise ArgumentError, "Articles are about a venue, event, person or locale, not #{topic}."
        end
        document = lambda do |shape|
          return no_soapbox("ArticlesAbout") unless shape.has?(type, "articles")

          "query ArticlesAbout($id: ID!, $first: Int) {\n  #{open}articles { list(first: $first) { nodes { " \
            "#{article_fields(shape)} } } }#{close}\n}\n"
        end
        [type, document]
      end

      # Every document the SDK can send, built for an audience with every module, by operation name. CI checks them
      # against the API schema (+bin/graphql-documents+).
      # @return [Hash{String => String}]
      def all
        everything = SchemaShape.everything
        documents = {
          "Audience" => AUDIENCE, "Me" => ME, "RSVPEvent" => RSVP_EVENT, "CancelRSVP" => CANCEL_RSVP,
          "EventRSVP" => EVENT_RSVP, "DeleteAccount" => DELETE_ACCOUNT, "ReportContent" => REPORT_CONTENT,
          "BlockUser" => BLOCK_USER, "UnblockUser" => UNBLOCK_USER, "CalendarFeed" => CALENDAR_FEED,
          "CreateCalendarFeed" => CREATE_CALENDAR_FEED, "SetCalendarFeedVenue" => SET_CALENDAR_FEED_VENUE,
          "DeleteCalendarFeed" => DELETE_CALENDAR_FEED,
          "ReportLocation" => report_location("venue { id name } locale { id name }"),
          "ChatRoom" => chat_room(:venue),
          "LocaleChatRoom" => renamed(chat_room(:locale, watch: true), "LocaleChatRoom"),
          "Tribes" => TRIBES, "IdentifyWithTribe" => IDENTIFY_WITH_TRIBE, "LeaveTribe" => LEAVE_TRIBE,
          "RegisterDevice" => REGISTER_DEVICE, "Node" => NODE, "SendMyChatMessage" => SEND_CHAT_MESSAGE,
          "RemoveMyChatMessage" => REMOVE_CHAT_MESSAGE, "Admissions" => ADMISSIONS, "BuyCover" => BUY_COVER,
          "BuyCoatCheck" => BUY_COAT_CHECK, "PayCover" => PAY_COVER, "ConfirmCover" => CONFIRM_COVER,
          "RefundAdmission" => REFUND_ADMISSION, "SubmitOpEd" => SUBMIT_OP_ED
        }
        %w[venues people locales closest_locale venue_cover venue_offers events event event_series venue_detail
           articles articles_page national_articles article publications publication my_op_eds].each do |name|
          document = public_send(name, everything)
          documents[document[/\A\w+ (\w+)/, 1]] = document
        end
        ARTICLES_ABOUT.each_key do |topic|
          name = "ArticlesAbout#{topic.capitalize}"
          documents[name] = renamed(articles_about(topic).last.call(everything), name)
        end
        documents
      end

      # +document+ with its operation renamed, so the schema check sees each variant under its own name.
      def renamed(document, name)
        document.sub(/\A(query|mutation|subscription) \w+/, "\\1 #{name}")
      end
    end
  end
end
