# frozen_string_literal: true

RSpec.describe Audience::Kit::Operations do
  let(:session) { signed_in_session }

  describe "the audience and its listings" do
    it "reads the audience and the signed-in person" do
      answer("id" => "aud-1", "name" => "Hot Mess", "theme" => { "light" => [{ "name" => "accent", "value" => "#ff0000" }] })
      answer("me" => { "self" => { "id" => "u1", "name" => "Pat", "isAdmin" => true } })
      expect(session.audience.color("accent").to_hex).to eq("#ff0000")
      expect(session.me).to have_attributes(name: "Pat", admin?: true)
      expect(http.graphql_bodies.last["operationName"]).to eq("Me")
    end

    it "reads venues, people and locales" do
      answer("venues" => { "list" => { "nodes" => [{ "id" => "v1", "name" => "The Eagle" }, nil] } })
      answer("people" => { "list" => { "nodes" => [{ "id" => "p1", "name" => "DJ" }] } })
      answer("locales" => [{ "id" => "l1", "name" => "Phoenix" }])
      expect(session.venues.map(&:name)).to eq(["The Eagle"])
      expect(session.people.map(&:id)).to eq(["p1"])
      expect(session.locales.first.name).to eq("Phoenix")
    end

    it "finds the closest locale and reports a position" do
      answer("closestLocale" => { "id" => "l1" })
      answer("reportLocation" => { "venue" => { "id" => "v1" } })
      near = Audience::Kit::Coordinate.new(latitude: 33.4, longitude: -112.0, beacon_major: 7)
      expect(session.closest_locale(near).id).to eq("l1")
      expect(http.graphql_bodies.last["variables"]).to eq("near" => { "latitude" => 33.4, "longitude" => -112.0, "beaconMajor" => 7 })
      expect(session.report_location(near, "venue { id }")).to eq("venue" => { "id" => "v1" })
      expect(http.graphql_bodies.last["query"]).to include("reportLocation(input: { position: $position }) { venue { id } }")
    end

    it "reads events, one event, series and a venue's page" do
      answer("events" => { "list" => { "nodes" => [{ "id" => "e1" }] } })
      answer("events" => { "event" => { "id" => "e2" } })
      answer("events" => { "series" => { "nodes" => [{ "id" => "s1" }] } })
      answer("venues" => { "venue" => { "id" => "v1", "chat" => { "open" => true } } })
      expect(session.events(window: "PAST", venue_id: "v1").map(&:id)).to eq(["e1"])
      expect(http.graphql_bodies.last["variables"]).to eq("window" => "PAST", "first" => 100, "venueId" => "v1")
      expect(session.event("e2").id).to eq("e2")
      expect(session.event_series(locale_id: "l1").first.id).to eq("s1")
      expect(http.graphql_bodies.last["variables"]).to eq("first" => 100, "localeId" => "l1")
      expect(session.venue_detail("v1", recent_messages: 5)).to have_attributes(id: "v1", chat_open: true)
      expect(http.graphql_bodies.last["variables"]).to eq("id" => "v1", "recentMessages" => 5)
    end

    it "reads the community, leaving out what the audience doesn't have" do
      answer("id" => "aud-1", "name" => "Hot Mess")
      answer("locales" => [{ "id" => "l1" }])
      answer("venues" => { "list" => { "nodes" => [] } })
      answer { undefined_field }
      answer("t0" => nil) # the schema has no Person fields...
      answer { undefined_field } # ...and still refuses
      answer("events" => { "list" => { "nodes" => [{ "id" => "e1" }] } })
      answer("events" => { "series" => { "nodes" => [] } })
      community = session.community
      expect(community.audience.name).to eq("Hot Mess")
      expect(community.people).to eq([])
      expect(community.events.map(&:id)).to eq(["e1"])
    end

    it "passes on other errors from the community" do
      answer { [200, { "errors" => [{ "message" => "x", "extensions" => { "code" => "FORBIDDEN" } }] }] }
      expect { session.community }.to raise_error(Audience::Kit::Error)
    end

    it "names a node's type" do
      answer("node" => { "__typename" => "Venue" })
      answer("node" => nil)
      expect(session.node_type("x")).to eq("Venue")
      expect(session.node_type("y")).to be_nil
    end
  end

  describe "public listings" do
    it "reads every page" do
      http.on(:get, "/v1/public/listings", 200, { "listings" => [{ "kind" => "venue", "id" => "1" }], "page_count" => 2, "next_page" => 2 })
          .on(:get, "/v1/public/listings", 200, { "listings" => [{ "kind" => "event", "id" => "2" }], "page_count" => "2" })
      expect(session.public_listings.map(&:kind)).to eq(%w[venue event])
      expect(http.sent.map(&:query)).to eq([{ "page" => "1" }, { "page" => "2" }])
    end

    it "reads one listing, nil when it's gone, and tonight at a venue" do
      http.on(:get, "/v1/public/posts/a%20b", 200, { "kind" => "post", "id" => "a b", "visibility" => "community" })
          .on(:get, "/v1/public/venues/9", 404, {})
          .on(:get, "/v1/public/events/9", 500, {})
          .on(:get, "/v1/public/venues/1/tonight", 200, { "event" => nil })
      expect(session.public_listing(:post, "a b")).not_to be_public
      expect(session.public_listing("venue", "9")).to be_nil
      expect { session.public_listing("event", "9") }.to raise_error(Audience::Kit::Error)
      expect { session.public_listing("photo", "1") }.to raise_error(ArgumentError)
      expect(session.public_tonight("1")).to eq("event" => nil)
    end

    it "reports listings that aren't a JSON object" do
      http.on(:get, "/v1/public/venues/1/tonight", 200, "[1]").on(:get, "/v1/public/venues/2/tonight", 200, "nope")
      expect { session.public_tonight("1") }.to raise_error(Audience::Kit::Error, /not a JSON object/)
      expect { session.public_tonight("2") }.to raise_error(Audience::Kit::Error) { |e| expect(e.code).to eq("DECODING") }
    end
  end

  describe "RSVP, tribes and notifications" do
    it "answers, cancels and reads RSVPs" do
      answer("rsvpEvent" => { "event" => { "rsvp" => { "mine" => "ATTENDING" } } })
      answer("rsvpEvent" => nil)
      answer("cancelRsvp" => { "event" => { "rsvp" => { "count" => 3 } } })
      answer("cancelRsvp" => nil)
      answer("events" => { "event" => { "rsvp" => { "count" => 1, "mine" => "ATTENDING", "attendees" => { "nodes" => [{ "profile" => { "id" => "p" } }] } } } })
      expect(session.rsvp_event("e1", "ATTENDING")).to eq("ATTENDING")
      expect { session.rsvp_event("e1", "MAYBE") }.to raise_error(Audience::Kit::Error, /no answer/)
      expect(session.cancel_rsvp("e1").count).to eq(3)
      expect { session.cancel_rsvp("e1") }.to raise_error(Audience::Kit::Error, /no rsvp/)
      rsvp = session.event_rsvp("e1", first: 10)
      expect(rsvp).to be_going
      expect(rsvp.attendee_profiles.map(&:id)).to eq(["p"])
    end

    it "reads, joins and leaves tribes, and registers a device" do
      answer("tribes" => [{ "id" => "t1", "tribe" => true }], "me" => { "self" => { "tribes" => [{ "isPrivate" => false, "tag" => { "id" => "t1" } }] } })
      answer("identifyWithTribe" => { "tribes" => [{ "tag" => { "id" => "t1" } }] })
      answer("leaveTribe" => { "tribes" => [] })
      answer("registerDevice" => { "registered" => true })
      tribes = session.tribes
      expect(tribes.tribes.first).to be_tribe
      expect(tribes.mine.first).not_to be_private
      expect(session.identify_with_tribe("t1", private: true).first).to be_private
      expect(http.graphql_bodies.last["variables"]).to eq("tagId" => "t1", "isPrivate" => true)
      expect(session.leave_tribe("t1")).to eq([])
      expect(session.register_device("apns", sandbox: true)).to be(true)
      expect(http.graphql_bodies.last["variables"]).to eq("notificationToken" => "apns", "sandbox" => true)
    end
  end

  describe "cover and coat check" do
    let(:admission) { { "id" => "a1", "status" => "PAID", "passSecret" => "c2VjcmV0" } }

    it "reads tonight's cover and offers" do
      answer("venues" => { "venue" => { "id" => "v1", "tickets" => { "cover" => { "charge" => { "payable" => true }, "viewerAdmission" => admission } } } })
      answer("venues" => { "venue" => { "tickets" => { "offers" => { "nodes" => [{ "url" => "https://t" }] } } } })
      cover = session.venue_cover("v1")
      expect(cover.charge).to be_payable
      expect(cover.viewer_admission).to be_paid
      expect(session.venue_offers("v1", night: "2026-11-27").first.url).to eq("https://t")
      expect(http.graphql_bodies.last["variables"]).to eq("id" => "v1", "night" => "2026-11-27")
    end

    it "buys, pays, confirms and refunds" do
      answer("me" => { "cover" => { "admissions" => { "nodes" => [admission] } } })
      answer("buyCover" => { "admission" => admission, "provider" => "STRIPE" })
      answer("buyCover" => { "admission" => admission })
      answer("buyCoatCheck" => { "admission" => admission, "provider" => "SQUARE" })
      answer("payCover" => { "admission" => admission })
      answer("confirmCover" => { "admission" => admission })
      answer("refundAdmission" => { "admission" => admission.merge("status" => "REFUNDED") })
      expect(session.admissions.first.id).to eq("a1")
      expect(session.buy_cover("v1", amount_cents: 1500).provider).to eq("STRIPE")
      expect(http.graphql_bodies.last["variables"]).to eq("venueId" => "v1", "amount" => { "cents" => 1500, "currency" => "usd" })
      session.buy_cover("v1")
      expect(http.graphql_bodies.last["variables"]).to eq("venueId" => "v1")
      expect(session.buy_coat_check("v1", quantity: 2).provider).to eq("SQUARE")
      expect(session.pay_cover("a1", source_id: "cnon").id).to eq("a1")
      expect(http.graphql_bodies.last["variables"]).to eq("admissionId" => "a1", "sourceId" => "cnon")
      expect(session.confirm_cover("a1")).to be_paid
      expect(session.refund_admission("a1").status).to eq("REFUNDED")
    end

    it "reports a purchase with no admission" do
      answer("payCover" => {})
      expect { session.pay_cover("a1", source_id: "x") }.to raise_error(Audience::Kit::Error, /no admission/)
    end
  end

  describe "news" do
    it "reads articles, pages of them and national news" do
      answer("soapbox" => { "articles" => { "nodes" => [{ "id" => "a1", "title" => "Hi" }] } })
      answer("soapbox" => { "articles" => { "nodes" => [] } })
      answer("soapbox" => { "articles" => { "nodes" => [], "pageInfo" => { "endCursor" => "c", "hasNextPage" => true } } })
      answer("soapbox" => { "articles" => { "nodes" => [{ "id" => "n1" }] } })
      answer("soapbox" => { "articles" => { "nodes" => [] } })
      expect(session.articles(locale_id: "l1").map(&:title)).to eq(["Hi"])
      expect(http.graphql_bodies.last["variables"]).to eq("localeId" => "l1")
      expect(session.articles).to eq([])
      expect(http.graphql_bodies.last).not_to have_key("variables")
      page = session.articles_page(locale_id: "l1", after: "b")
      expect([page.end_cursor, page.next_page?]).to eq(["c", true])
      expect(session.national_articles(first: 3).map(&:id)).to eq(["n1"])
      expect(session.national_articles).to eq([])
    end

    it "reads an article, articles about a listing and publications" do
      answer("soapbox" => { "article" => { "id" => "a1", "body" => "# Hi", "venues" => [{ "id" => "v1" }] } })
      answer("venues" => { "venue" => { "articles" => { "list" => { "nodes" => [{ "id" => "a2" }] } } } })
      answer("locale" => { "articles" => { "list" => { "nodes" => [{ "id" => "a3" }] } } })
      answer("id" => "aud-1")
      answer("soapbox" => { "publications" => [{ "id" => "p1", "locale" => { "id" => "L1" } }, { "id" => "p2" }] })
      answer("soapbox" => { "publication" => { "id" => "p1" } })
      answer("soapbox" => { "myOpEds" => [{ "id" => "o1", "status" => "IN_REVIEW" }] })
      expect(session.article("a1").subjects).to eq("venues" => [{ "id" => "v1" }])
      expect(session.articles_about(:venue, "v1").map(&:id)).to eq(["a2"])
      expect(session.articles_about("locale", "l1", first: 2).map(&:id)).to eq(["a3"])
      expect(session.articles_about("person", "p")).to eq([])
      expect(session.local_publications("l1").map(&:id)).to eq(["p1"])
      expect(session.publication("p1").id).to eq("p1")
      expect(session.my_op_eds.first.status).to eq("IN_REVIEW")
    end

    it "submits an op-ed" do
      answer("submitOpEd" => { "article" => { "id" => "o1", "status" => "SUBMITTED" } })
      expect(session.submit_op_ed("p1", title: "T", body: "B").status).to eq("SUBMITTED")
      expect(http.graphql_bodies.last["variables"]).to eq("publicationId" => "p1", "title" => "T", "body" => "B", "summary" => nil, "byline" => nil)
    end
  end

  describe "calendar subscriptions" do
    it "reads, makes, follows venues in and deletes the subscription" do
      feed = { "url" => "https://api.test/cal/x.ics", "venues" => [{ "id" => "v1" }] }
      answer("me" => { "calendarFeed" => feed })
      answer("createCalendarFeed" => { "calendarFeed" => feed })
      answer("setCalendarFeedVenue" => { "calendarFeed" => feed })
      answer("deleteCalendarFeed" => { "deleted" => true })
      expect(session.calendar_feed).to be_follows("v1")
      expect(session.create_calendar_feed(reset: true).webcal_url).to eq("webcal://api.test/cal/x.ics")
      expect(session.follow_venue_in_calendar("v1", following: false).venue_ids).to eq(["v1"])
      expect(http.graphql_bodies.last["variables"]).to eq("venueId" => "v1", "following" => false)
      expect(session.delete_calendar_feed).to be(true)
    end
  end

  describe "chat and moderation" do
    it "sends and removes messages" do
      answer("sendMyChatMessage" => { "message" => { "id" => "m1", "message" => "hey" } })
      answer("removeMyChatMessage" => { "deletedId" => "m1" })
      answer("removeMyChatMessage" => nil)
      expect(session.send_chat_message("hey", venue_id: "v1", prompt_id: "p").body).to eq("hey")
      expect(http.graphql_bodies.last["variables"]).to eq("input" => { "venueId" => "v1", "message" => "hey", "promptId" => "p" })
      expect(session.remove_chat_message("m1")).to eq("m1")
      expect(session.remove_chat_message("m2")).to eq("m2")
    end

    it "reports content and blocks people" do
      answer("reportContent" => { "reported" => true, "blocked" => true })
      answer("reportContent" => nil)
      answer("blockUser" => {})
      answer("unblockUser" => {})
      result = session.report_content(Audience::Kit::ReportTarget::MESSAGE, "m1", reason: Audience::Kit::ReportTarget::INTIMATE_IMAGE, block: true)
      expect([result.reported?, result.blocked?]).to eq([true, true])
      expect(session.report_content("PERSON", "u2").reported?).to be(false)
      expect(session.block_user("u2")).to be_nil
      expect(session.unblock_user("u2")).to be_nil
      expect(http.graphql_bodies.last["variables"]).to eq("userId" => "u2")
    end
  end
end
