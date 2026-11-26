# frozen_string_literal: true

module Audience
  module Kit
    # A Facebook Page: a venue's or person's (Listings and Facebook).
    class Page < Model
      # @!method id
      #   @return [String]
      attribute :id, default: ""
      # @!method name
      #   @return [String]
      attribute :name, default: ""
      # @!method photo_url
      #   @return [String, nil]
      attribute :photo_url
      # @!method banner_url
      #   @return [String, nil]
      attribute :banner_url
    end

    # A person as a list shows them: a host, an act, an attendee, a chat member.
    class Profile < Model
      # @!method id
      #   @return [String]
      attribute :id, default: ""
      # @!method name
      #   @return [String]
      attribute :name, default: ""
      # @!method avatar_url
      #   @return [String, nil]
      attribute :avatar_url
    end

    # The audience itself: its name, subdomain and theme.
    class Audience < Model
      # @!method id
      #   @return [String]
      attribute :id, default: ""
      # @!method name
      #   @return [String]
      attribute :name, default: ""
      # @!method subdomain
      #   @return [String, nil]
      attribute :subdomain
      # @!method theme
      #   @return [Hash, nil] +preset+, +tagline+, and +light+ and +dark+ lists of +{ name, value }+ tokens
      attribute :theme, :hash

      # A theme token's color, preferring its dark override in dark mode.
      # @param token [String]
      # @param dark [Boolean]
      # @return [Color, nil]
      def color(token, dark: false) = Color.from_theme(theme, token, dark: dark)
    end

    # The signed-in person's own profile (+me { self }+).
    class SelfUser < Model
      # @!method id
      #   @return [String]
      attribute :id, default: ""
      # @!method name
      #   @return [String]
      attribute :name, default: ""
      # @!method first_name
      #   @return [String, nil]
      attribute :first_name
      # @!method last_name
      #   @return [String, nil]
      attribute :last_name
      # @!method email_address
      #   @return [String, nil]
      attribute :email_address
      # @!method admin?
      #   @return [Boolean]
      attribute :admin?, :boolean, path: "isAdmin", default: false
      # @!method presence
      #   @return [String, nil]
      attribute :presence
    end

    # A tag on a venue, person or event, or a tribe people identify with.
    class Tag < Model
      # @!method id
      #   @return [String]
      attribute :id, default: ""
      # @!method name
      #   @return [String]
      attribute :name, default: ""
      # @!method color_hex
      #   @return [String, nil] its chip color, e.g. +"#ff2d55"+
      attribute :color_hex, path: "color"
      # @!method tribe?
      #   @return [Boolean] whether people can identify with it
      attribute :tribe?, :boolean, path: "tribe", default: false

      # @return [Color, nil]
      def color = color_hex && Color.from_hex(color_hex)
    end

    # One of the signed-in person's tribes.
    class TribeIdentification < Model
      # @!method private?
      #   @return [Boolean] whether only they see it
      attribute :private?, :boolean, path: "isPrivate", default: true
      # @!method tag
      #   @return [Tag, nil]
      attribute :tag, "Tag"
    end

    # A locale: a city or area the audience lists.
    class Locale < Model
      # @!method id
      #   @return [String]
      attribute :id, default: ""
      # @!method name
      #   @return [String]
      attribute :name, default: ""
      # @!method label
      #   @return [String, nil]
      attribute :label
      # @!method city_names
      #   @return [Array<String>]
      attribute :city_names, :strings
      # @!method banner_url
      #   @return [String, nil]
      attribute :banner_url
      # @!method place_id
      #   @return [String, nil] its Google place ID (Listings and Google Places)
      attribute :place_id, path: %w[profile places placeId]
    end

    # Where a venue is.
    class Location < Model
      # @!method id
      #   @return [String, nil]
      attribute :id
      # @!method address
      #   @return [String, nil]
      attribute :address
      # @!method place_id
      #   @return [String, nil] its Google place ID (Google Places)
      attribute :place_id, path: %w[places placeId]

      # Where it is on the map, from its WKT point.
      # @return [Coordinate, nil]
      def coordinate = self["point"].is_a?(String) ? Coordinate.from_wkt(self["point"]) : nil
    end

    # An amount of money in a currency's minor unit.
    class Money < Model
      # The symbols {#format} writes before amounts in the currencies AudienceKit audiences use.
      SYMBOLS = { "usd" => "$", "cad" => "CA$", "aud" => "A$", "gbp" => "£", "eur" => "€", "mxn" => "MX$" }.freeze

      # @!method cents
      #   @return [Integer]
      attribute :cents, :integer, default: 0

      # @return [String] the ISO currency code, lowercase
      def currency = (self["currency"].is_a?(String) ? self["currency"] : "usd").downcase

      # @return [Float] the amount in the major unit
      def amount = cents / 100.0

      # The amount for people, e.g. "$12.00" or "12.00 CHF".
      # @return [String]
      def format
        whole, fraction = Kernel.format("%.2f", amount.abs).split(".")
        sign = "-" if cents.negative?
        number = "#{whole.reverse.scan(/\d{1,3}/).join(",").reverse}.#{fraction}"
        SYMBOLS.key?(currency) ? "#{sign}#{SYMBOLS[currency]}#{number}" : "#{sign}#{number} #{currency.upcase}"
      end
      alias to_s format
    end

    # A ticket seller's offer to get into an event or venue.
    class AdmissionOffer < Model
      # @!method price
      #   @return [Money, nil]
      attribute :price, "Money"
      # @!method url
      #   @return [String, nil] where to buy it
      attribute :url
      # @!method seller_key
      #   @return [String, nil]
      attribute :seller_key, path: %w[seller key]
      # @!method seller_name
      #   @return [String, nil]
      attribute :seller_name, path: %w[seller name]
    end

    # A message in a venue's or locale's chat.
    class ChatMessage < Model
      # @!method id
      #   @return [String]
      attribute :id, default: ""
      # @!method name
      #   @return [String, nil] who sent it
      attribute :name
      # @!method user_id
      #   @return [String, nil]
      attribute :user_id
      # @!method avatar_url
      #   @return [String, nil]
      attribute :avatar_url
      # @!method photo_url
      #   @return [String, nil]
      attribute :photo_url
      # @!method sent_at
      #   @return [Time, nil]
      attribute :sent_at, :time
      # @!method role
      #   @return [String, nil]
      attribute :role
      # @!method kind
      #   @return [String, nil]
      attribute :kind
      # @!method title
      #   @return [String, nil]
      attribute :title
      # @!method pinned?
      #   @return [Boolean]
      attribute :pinned?, :boolean, path: "pinned", default: false

      # @return [String, nil] the text
      def body = Model.cast(self["body"], :string, nil) || Model.cast(self["message"], :string, nil)
    end

    # A venue: a bar, club or space. In a list it carries its locale, location, tags and Facebook Page; on its page
    # ({Operations#venue_detail}) also its description, profile, chat and upcoming events, as far as the audience's
    # modules go.
    class Venue < Model
      # @!method id
      #   @return [String]
      attribute :id, default: ""
      # @!method name
      #   @return [String]
      attribute :name, default: ""
      # @!method hidden?
      #   @return [Boolean]
      attribute :hidden?, :boolean, path: "hidden", default: false
      # @!method order
      #   @return [Integer, nil]
      attribute :order, :integer
      # @!method photo_url
      #   @return [String, nil]
      attribute :photo_url
      # @!method banner_url
      #   @return [String, nil]
      attribute :banner_url
      # @!method locale
      #   @return [Locale, nil]
      attribute :locale, "Locale"
      # @!method location
      #   @return [Location, nil]
      attribute :location, "Location"
      # @!method tags
      #   @return [Array<Tag>]
      attribute :tags, ["Tag"]
      # @!method facebook_page
      #   @return [Page, nil] its Facebook Page (Listings and Facebook)
      attribute :facebook_page, "Page", path: %w[profile facebook page]
      # @!method description
      #   @return [String, nil] on its page: what it says about itself
      attribute :description
      # @!method address
      #   @return [String, nil] on its page: its street address
      attribute :address, path: %w[profile address]
      # @!method phone
      #   @return [String, nil] on its page
      attribute :phone, path: %w[profile phone]
      # @!method website
      #   @return [String, nil] on its page
      attribute :website, path: %w[profile website]
      # @!method social_links
      #   @return [Array<Hash>] on its page: its links elsewhere, each +id handle provider url+
      attribute :social_links, :hashes, path: %w[profile socialLinks]
      # @!method recent_messages
      #   @return [Array<ChatMessage>] on its page: its chat's latest messages, oldest first
      attribute :recent_messages, ["ChatMessage"], path: %w[chat recentMessages]
      # @!method upcoming_events
      #   @return [Array<Event>] on its page: what's coming up there
      attribute :upcoming_events, ["Event"], path: %w[events upcoming]

      # On its page: whether its chat is open (Chat); nil when the audience has no chat.
      # @return [Boolean, nil]
      def chat_open = self["chat"].is_a?(Hash) ? self["chat"]["open"] == true : nil

      # Where it is on the map, when its location has a point.
      # @return [Coordinate, nil]
      def coordinate = location&.coordinate

      # Reads a venue's page with the module-level session ({Kit.session}).
      # @param id [String]
      # @return [Venue]
      # @raise [Error] {Error::NOT_FOUND} when there is no such venue
      def self.find(id)
        Kit.session.venue_detail(id.to_s) || raise(Error.not_found("There is no venue #{id}."))
      end
    end

    # A person the audience lists: a promoter, DJ, drag artist or act.
    class Person < Model
      # @!method id
      #   @return [String]
      attribute :id, default: ""
      # @!method name
      #   @return [String]
      attribute :name, default: ""
      # @!method avatar_url
      #   @return [String, nil]
      attribute :avatar_url
      # @!method banner_url
      #   @return [String, nil]
      attribute :banner_url
      # @!method order
      #   @return [Integer, nil]
      attribute :order, :integer
      # @!method global?
      #   @return [Boolean] whether they are listed in every locale
      attribute :global?, :boolean, path: "global", default: false
      # @!method like_required?
      #   @return [Boolean]
      attribute :like_required?, :boolean, path: "likeRequired", default: false
      # @!method tags
      #   @return [Array<Tag>]
      attribute :tags, ["Tag"]
      # @!method locales
      #   @return [Array<Locale>]
      attribute :locales, ["Locale"]
      # @!method facebook_page
      #   @return [Page, nil]
      attribute :facebook_page, "Page", path: %w[profile facebook page]
      # @!method home_venue
      #   @return [Venue, nil] where they're usually found
      attribute :home_venue, "Venue", path: %w[venues home]
      # @!method involvements
      #   @return [Array<Hash>] their events, each +relationship role via node+
      attribute :involvements, :hashes, path: %w[events involvements edges]
    end

    # A cover charge on a night: the amount, the fee and the total the buyer pays, whether it can be paid in the app,
    # its coat check, and on a sliding scale the range the buyer picks from.
    class CoverCharge < Model
      # @!method amount
      #   @return [Money, nil]
      attribute :amount, "Money"
      # @!method fee
      #   @return [Money, nil]
      attribute :fee, "Money"
      # @!method total
      #   @return [Money, nil]
      attribute :total, "Money"
      # @!method night
      #   @return [String, nil] +YYYY-MM-DD+
      attribute :night
      # @!method from
      #   @return [Time, nil] when it starts being charged
      attribute :from, :time
      # @!method payable?
      #   @return [Boolean] whether it can be paid in the app
      attribute :payable?, :boolean, path: "payable", default: false
      # @!method event
      #   @return [Hash, nil] +id name+
      attribute :event, :hash
      # @!method coat_check
      #   @return [Hash, nil] +amount fee total night payable+
      attribute :coat_check, :hash
      # @!method scale_min
      #   @return [Money, nil]
      attribute :scale_min, "Money", path: %w[scale min]
      # @!method scale_max
      #   @return [Money, nil]
      attribute :scale_max, "Money", path: %w[scale max]
      # @!method scale_suggested
      #   @return [Money, nil]
      attribute :scale_suggested, "Money", path: %w[scale suggested]

      # Whether the buyer picks what to pay.
      # @return [Boolean]
      def sliding_scale? = !scale_min.nil? && !scale_max.nil?

      # Whether the venue checks coats that night and takes payment for it in the app.
      # @return [Boolean]
      def coat_check? = coat_check&.dig("payable") == true
    end

    # An event: its own fields, then those of the Venues, RSVP, People and Ticketing modules the audience has. A
    # module the audience doesn't have leaves its readers nil or empty.
    class Event < Model
      # @!method id
      #   @return [String]
      attribute :id, default: ""
      # @!method name
      #   @return [String]
      attribute :name, default: ""
      # @!method description
      #   @return [String, nil]
      attribute :description
      # @!method start_at
      #   @return [Time, nil]
      attribute :start_at, :time
      # @!method end_at
      #   @return [Time, nil]
      attribute :end_at, :time
      # @!method featured?
      #   @return [Boolean]
      attribute :featured?, :boolean, path: "isFeatured", default: false
      # @!method canceled?
      #   @return [Boolean]
      attribute :canceled?, :boolean, path: "isCanceled", default: false
      # @!method banner_url
      #   @return [String, nil]
      attribute :banner_url
      # @!method source_url
      #   @return [String, nil] where it came from, e.g. its Facebook event
      attribute :source_url
      # @!method locale
      #   @return [Locale, nil]
      attribute :locale, "Locale"
      # @!method tags
      #   @return [Array<Tag>]
      attribute :tags, ["Tag"]
      # @!method venue_name
      #   @return [String, nil] the venue's name as the event gives it, even where the venue isn't listed (Venues)
      attribute :venue_name, path: %w[venue name]
      # @!method venue
      #   @return [Venue, nil] the listed venue it's at (Venues)
      attribute :venue, "Venue", path: %w[venue venue]
      # @!method rsvp
      #   @return [String, nil] the signed-in person's answer: ATTENDING, MAYBE, DECLINED or UNSURE (RSVP)
      attribute :rsvp, path: %w[rsvp mine]
      # @!method rsvp_count
      #   @return [Integer, nil] how many are going (RSVP)
      attribute :rsvp_count, :integer, path: %w[rsvp count]
      # @!method hosts
      #   @return [Array<Profile>] (People)
      attribute :hosts, ["Profile"], path: %w[people hosts]
      # @!method lineup
      #   @return [Array<Profile>] (People)
      attribute :lineup, ["Profile"], path: %w[people lineup]
      # @!method jockeys
      #   @return [Array<Profile>] its KJ, DJ or VJ (People)
      attribute :jockeys, ["Profile"], path: %w[people jockeys]
      # @!method jockey_label
      #   @return [String, nil] what to call them, e.g. "KJ"
      attribute :jockey_label, path: %w[people jockeyLabel]
      # @!method ticket_url
      #   @return [String, nil] where tickets are sold (Ticketing)
      attribute :ticket_url, path: %w[tickets url]
      # @!method offers
      #   @return [Array<AdmissionOffer>] (Ticketing)
      attribute :offers, ["AdmissionOffer"], path: %w[tickets offers]
      # @!method cover
      #   @return [CoverCharge, nil] tonight's cover charge (Ticketing and Cover)
      attribute :cover, "CoverCharge", path: %w[tickets cover charge]

      # Who runs the night: its hosts, or, when nobody else is linked to it, its KJ, DJ or VJ (a jockey who is the
      # only person on an event is its host everywhere).
      # @return [Array<Profile>]
      def effective_hosts = hosts.empty? && lineup.empty? ? jockeys : hosts

      # Whether it has ended at +at+ (now by default); an event with no end has ended once it started.
      # @param at [Time]
      # @return [Boolean]
      def ended?(at = Time.now)
        finish = end_at || start_at
        !finish.nil? && finish <= at
      end

      # Reads an event with the module-level session ({Kit.session}).
      # @param id [String]
      # @return [Event]
      # @raise [Error] {Error::NOT_FOUND} when there is no such event
      def self.find(id)
        Kit.session.event(id.to_s) || raise(Error.not_found("There is no event #{id}."))
      end
    end

    # A recurring event series, e.g. "Karaoke every Tuesday".
    class EventSeries < Model
      # @!method id
      #   @return [String]
      attribute :id, default: ""
      # @!method name
      #   @return [String]
      attribute :name, default: ""
      # @!method description
      #   @return [String, nil]
      attribute :description
      # @!method recurrence_text
      #   @return [String, nil] e.g. "Every Tuesday"
      attribute :recurrence_text
      # @!method starts_on
      #   @return [String, nil] +YYYY-MM-DD+
      attribute :starts_on
      # @!method start_time
      #   @return [String, nil] +HH:MM+, in {#time_zone}
      attribute :start_time
      # @!method time_zone
      #   @return [String, nil] an IANA zone, e.g. America/Phoenix
      attribute :time_zone
      # @!method duration_minutes
      #   @return [Integer, nil]
      attribute :duration_minutes, :integer
      # @!method banner_url
      #   @return [String, nil]
      attribute :banner_url
      # @!method locale
      #   @return [Locale, nil]
      attribute :locale, "Locale"
      # @!method tags
      #   @return [Array<Tag>]
      attribute :tags, ["Tag"]
      # @!method venue_name
      #   @return [String, nil]
      attribute :venue_name, path: %w[venue name]
      # @!method venue
      #   @return [Venue, nil]
      attribute :venue, "Venue", path: %w[venue venue]
    end

    # An event's RSVPs: how many are going, the signed-in person's own answer and, where asked for, who's going.
    class EventRSVP < Model
      # @!method count
      #   @return [Integer] how many are going
      attribute :count, :integer, default: 0
      # @!method mine
      #   @return [String, nil] the signed-in person's answer; nil when they haven't answered
      attribute :mine
      # @!method mine_source
      #   @return [String, nil] why they count as going: RSVP, or TICKET when they hold one
      attribute :mine_source
      # @!method going
      #   @return [Integer, nil] staff only
      attribute :going, :integer, path: %w[counts going]
      # @!method interested
      #   @return [Integer, nil] staff only
      attribute :interested, :integer, path: %w[counts interested]
      # @!method tickets
      #   @return [Integer, nil] staff only
      attribute :tickets, :integer, path: %w[counts tickets]
      # @!method attendees
      #   @return [Array<Hash>] the first attendees, each +profile friend source+
      attribute :attendees, :hashes

      # @return [Boolean] whether the signed-in person is going
      def going? = mine == "ATTENDING"

      # @return [Array<Profile>] the attendees' profiles
      def attendee_profiles = Profile.list(attendees.map { |attendee| attendee["profile"] })
    end

    # A cover pass or coat check ticket the signed-in person bought, with the secret its door code is made from
    # ({#pass_code}).
    class Admission < Model
      # @!method id
      #   @return [String]
      attribute :id, default: ""
      # @!method status
      #   @return [String] PENDING, PAID, FAILED, CANCELED, REFUNDED or DISPUTED
      attribute :status, default: "PENDING"
      # @!method kind
      #   @return [String] COVER or COAT_CHECK
      attribute :kind, default: "COVER"
      # @!method night
      #   @return [String, nil] +YYYY-MM-DD+
      attribute :night
      # @!method quantity
      #   @return [Integer] how many: coats, for coat check
      attribute :quantity, :integer, default: 1
      # @!method tier
      #   @return [String, nil]
      attribute :tier
      # @!method claim_check_number
      #   @return [String, nil] the coat check number to show at the counter
      attribute :claim_check_number
      # @!method amount
      #   @return [Money, nil]
      attribute :amount, "Money"
      # @!method fee
      #   @return [Money, nil]
      attribute :fee, "Money"
      # @!method total
      #   @return [Money, nil]
      attribute :total, "Money"
      # @!method refundable?
      #   @return [Boolean]
      attribute :refundable?, :boolean, path: "isRefundable", default: false
      # @!method pass_secret
      #   @return [String, nil] Base64; never log it. Nil once it can't get anyone in.
      attribute :pass_secret
      # @!method scan_count
      #   @return [Integer]
      attribute :scan_count, :integer, default: 0
      # @!method checked_in_at
      #   @return [Time, nil]
      attribute :checked_in_at, :time
      # @!method created_at
      #   @return [Time, nil]
      attribute :created_at, :time
      # @!method profile
      #   @return [Profile, nil] the buyer, for the door
      attribute :profile, "Profile"
      # @!method venue
      #   @return [Hash, nil] +id name photoUrl+
      attribute :venue, :hash
      # @!method event
      #   @return [Hash, nil] +id name+
      attribute :event, :hash

      # @return [Boolean] whether it's paid for and gets its holder in
      def paid? = status == "PAID"

      # The code to show at the door at +epoch_seconds+ (now by default); nil without a pass secret.
      # @param epoch_seconds [Integer, nil]
      # @return [String, nil]
      def pass_code(epoch_seconds = nil) = pass_secret && CoverPass.code(id, pass_secret, epoch_seconds)
    end

    # What starting to buy cover returns: the pending admission and the payment provider's keys.
    class CoverPurchase < Model
      # @!method admission
      #   @return [Admission, nil]
      attribute :admission, "Admission"
      # @!method provider
      #   @return [String, nil] STRIPE or SQUARE
      attribute :provider
      # @!method payment_intent_client_secret
      #   @return [String, nil] Stripe
      attribute :payment_intent_client_secret
      # @!method publishable_key
      #   @return [String, nil] Stripe
      attribute :publishable_key
      # @!method stripe_account_id
      #   @return [String, nil] Stripe
      attribute :stripe_account_id
      # @!method square_application_id
      #   @return [String, nil] Square
      attribute :square_application_id
      # @!method square_location_id
      #   @return [String, nil] Square
      attribute :square_location_id
    end

    # A venue's cover tonight, with the signed-in person's pass and coat check ticket.
    class VenueCover < Model
      # @!method id
      #   @return [String]
      attribute :id, default: ""
      # @!method name
      #   @return [String]
      attribute :name, default: ""
      # @!method charge
      #   @return [CoverCharge, nil]
      attribute :charge, "CoverCharge", path: %w[tickets cover charge]
      # @!method viewer_admission
      #   @return [Admission, nil]
      attribute :viewer_admission, "Admission", path: %w[tickets cover viewerAdmission]
      # @!method viewer_coat_check
      #   @return [Admission, nil]
      attribute :viewer_coat_check, "Admission", path: %w[tickets cover viewerCoatCheck]
    end

    # A Soapbox publication: a newsroom, blog or columnist that publishes to the audience.
    class Publication < Model
      # @!method id
      #   @return [String]
      attribute :id, default: ""
      # @!method name
      #   @return [String]
      attribute :name, default: ""
      # @!method masthead
      #   @return [String, nil]
      attribute :masthead
      # @!method about
      #   @return [String, nil]
      attribute :about
      # @!method website_url
      #   @return [String, nil]
      attribute :website_url
      # @!method photo_url
      #   @return [String, nil]
      attribute :photo_url
      # @!method trusted?
      #   @return [Boolean]
      attribute :trusted?, :boolean, path: "trusted", default: false
      # @!method accepts_op_eds?
      #   @return [Boolean]
      attribute :accepts_op_eds?, :boolean, path: "acceptsOpEds", default: false
      # @!method op_ed_guidelines
      #   @return [String, nil]
      attribute :op_ed_guidelines, path: "opEdGuidelines"
      # @!method locale
      #   @return [Locale, nil]
      attribute :locale, "Locale"
      # @!method person
      #   @return [Profile, nil]
      attribute :person, "Profile"
      # @!method ad_free_offered?
      #   @return [Boolean] whether readers can tip to read it without ads
      attribute :ad_free_offered?, :boolean, path: "adFreeOffered", default: false
      # @!method ad_free_tip_cents
      #   @return [Integer, nil]
      attribute :ad_free_tip_cents, :integer
      # @!method ad_free_days
      #   @return [Integer, nil]
      attribute :ad_free_days, :integer
    end

    # A Soapbox article: news a publication ran, or an op-ed a reader sent one. In a list it has its summary and
    # teaser; read on its own ({Operations#article}) also its body and what it's about.
    class Article < Model
      # @!method id
      #   @return [String]
      attribute :id, default: ""
      # @!method slug
      #   @return [String, nil]
      attribute :slug
      # @!method title
      #   @return [String]
      attribute :title, default: ""
      # @!method summary
      #   @return [String, nil]
      attribute :summary
      # @!method byline
      #   @return [String, nil]
      attribute :byline
      # @!method kind
      #   @return [String, nil] ARTICLE or OP_ED
      attribute :kind
      # @!method published_at
      #   @return [Time, nil]
      attribute :published_at, :time
      # @!method edited?
      #   @return [Boolean] whether it changed after it ran ("Updated")
      attribute :edited?, :boolean, path: "edited", default: false
      # @!method pinned?
      #   @return [Boolean]
      attribute :pinned?, :boolean, path: "pinned", default: false
      # @!method teaser?
      #   @return [Boolean] whether only a teaser runs here and the rest is at {#canonical_url}
      attribute :teaser?, :boolean, path: "teaser", default: false
      # @!method canonical_url
      #   @return [String, nil]
      attribute :canonical_url
      # @!method disclosure
      #   @return [String, nil] a disclosure to show with it, e.g. a paid placement
      attribute :disclosure
      # @!method hero_photo_url
      #   @return [String, nil]
      attribute :hero_photo_url
      # @!method hero_alt_text
      #   @return [String, nil]
      attribute :hero_alt_text
      # @!method publication
      #   @return [Publication, nil]
      attribute :publication, "Publication"
      # @!method body
      #   @return [String, nil] read on its own: the body, as Markdown
      attribute :body
      # @!method viewer_ad_free?
      #   @return [Boolean] whether the signed-in reader tipped to read its publication without ads
      attribute :viewer_ad_free?, :boolean, path: "viewerAdFree", default: false
      # @!method featured_nationally?
      #   @return [Boolean]
      attribute :featured_nationally?, :boolean, path: "featuredNationally", default: false
      # @!method status
      #   @return [String, nil] an op-ed's review: SUBMITTED, DRAFT, IN_REVIEW, PUBLISHED, UNPUBLISHED or DECLINED
      attribute :status
      # @!method review_note
      #   @return [String, nil] the publication's note on an op-ed
      attribute :review_note
      # @!method submitted_at
      #   @return [Time, nil]
      attribute :submitted_at, :time

      # Read on its own: the venues, events, people and locales it is about, each +id name+.
      # @return [Hash{String => Array<Hash>}]
      def subjects
        %w[venues events people locales].to_h { |key| [key, self[key]] }
                                        .select { |_, list| list.is_a?(Array) }
                                        .transform_values { |list| list.grep(Hash) }
      end
    end

    # The signed-in person's calendar subscription: a feed of the events they're going to and the venues they follow.
    class CalendarFeed < Model
      # @return [String] the feed's https URL
      def url = Model.cast(self["url"], :string, "")

      # @return [String] the +webcal://+ link calendar apps subscribe with
      def webcal_url = Model.cast(self["webcalUrl"], :string, nil) || url.sub(%r{\Ahttps?://}, "webcal://")

      # @return [String] the link that adds it to Google Calendar
      def google_url
        Model.cast(self["googleUrl"], :string, nil) ||
          "https://calendar.google.com/calendar/render?cid=#{URI.encode_www_form_component(webcal_url)}"
      end

      # @return [Array<String>] the venues it follows
      def venue_ids = Model.hashes(self["venues"]).map { |venue| venue["id"] }.grep(String)

      # @param venue_id [String]
      # @return [Boolean]
      def follows?(venue_id) = venue_ids.include?(venue_id)
    end

    # A venue, event or post as the audience's websites show it (+GET /v1/public/listings+). Plain text; the keys are
    # snake_case, as the REST API sends them.
    class PublicListing < Model
      # @!method kind
      #   @return [String] venue, event or post
      attribute :kind, default: ""
      # @!method id
      #   @return [String]
      attribute :id, default: ""
      # @!method path
      #   @return [String, nil] its path on the audience's website
      attribute :path
      # @!method visibility
      #   @return [String, nil] public, or community (shown in full only to members)
      attribute :visibility
      # @!method title
      #   @return [String, nil]
      attribute :title
      # @!method description
      #   @return [String, nil]
      attribute :description
      # @!method address
      #   @return [String, nil]
      attribute :address
      # @!method phone
      #   @return [String, nil]
      attribute :phone
      # @!method website
      #   @return [String, nil]
      attribute :website
      # @!method listed
      #   @return [Boolean, nil]
      attribute :listed, :boolean
      # @!method image
      #   @return [String, nil]
      attribute :image
      # @!method start_at
      #   @return [Time, nil]
      attribute :start_at, :time, path: "start_at"
      # @!method end_at
      #   @return [Time, nil]
      attribute :end_at, :time, path: "end_at"
      # @!method venue_name
      #   @return [String, nil]
      attribute :venue_name, path: "venue_name"
      # @!method ticket_url
      #   @return [String, nil]
      attribute :ticket_url, path: "ticket_url"
      # @!method canceled
      #   @return [Boolean, nil]
      attribute :canceled, :boolean, path: "is_canceled"
      # @!method cover_cents
      #   @return [Integer, nil]
      attribute :cover_cents, :integer, path: "cover_cents"

      # Whether anyone may see it in full ("community" listings show in full only to members).
      # @return [Boolean]
      def public? = visibility.nil? || visibility == "public"
    end

    # One page of {Operations#public_listings_page}.
    # @!attribute [r] listings
    #   @return [Array<PublicListing>]
    # @!attribute [r] page_count
    #   @return [Integer]
    # @!attribute [r] next_page
    #   @return [Integer, nil] the next page's number, or nil on the last page
    PublicListingsPage = Data.define(:listings, :page_count, :next_page) do
      # @param json [Hash]
      # @return [PublicListingsPage]
      def self.from_h(json)
        new(listings: PublicListing.list(json["listings"]),
            page_count: Model.integer(json["page_count"]) || 1, next_page: Model.integer(json["next_page"]))
      end
    end

    # One page of {Operations#articles_page}: pass {#end_cursor} as +after:+ for the next.
    # @!attribute [r] articles
    #   @return [Array<Article>]
    # @!attribute [r] end_cursor
    #   @return [String, nil]
    # @!attribute [r] next_page
    #   @return [Boolean] whether there are more
    ArticlesPage = Data.define(:articles, :end_cursor, :next_page) do
      # @param connection [Hash, nil] the +articles+ connection
      # @return [ArticlesPage]
      def self.from_connection(connection)
        return new(articles: [], end_cursor: nil, next_page: false) unless connection.is_a?(Hash)

        cursor = connection.dig("pageInfo", "endCursor")
        more = connection.dig("pageInfo", "hasNextPage") == true && cursor.is_a?(String)
        new(articles: Article.list(connection["nodes"]), end_cursor: more ? cursor : nil, next_page: more)
      end

      # @return [Boolean]
      def next_page? = next_page
    end

    # Everything the audience lists, from {Operations#community}. A part whose module the audience doesn't have is
    # empty.
    # @!attribute [r] audience
    #   @return [Audience, nil]
    # @!attribute [r] locales
    #   @return [Array<Locale>]
    # @!attribute [r] venues
    #   @return [Array<Venue>]
    # @!attribute [r] people
    #   @return [Array<Person>]
    # @!attribute [r] events
    #   @return [Array<Event>]
    # @!attribute [r] event_series
    #   @return [Array<EventSeries>]
    Community = Data.define(:audience, :locales, :venues, :people, :events, :event_series)

    # What {Operations#report_content} did.
    # @!attribute [r] reported
    #   @return [Boolean]
    # @!attribute [r] blocked
    #   @return [Boolean] whether the person behind it was blocked too
    ReportResult = Data.define(:reported, :blocked) do
      # @return [Boolean]
      def reported? = reported

      # @return [Boolean]
      def blocked? = blocked
    end

    # The signed-in person's tribes and the ones they can pick from, from {Operations#tribes}.
    # @!attribute [r] tribes
    #   @return [Array<Tag>] the tribes people can identify with here
    # @!attribute [r] mine
    #   @return [Array<TribeIdentification>] the signed-in person's own
    Tribes = Data.define(:tribes, :mine)
  end
end
