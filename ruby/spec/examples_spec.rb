# frozen_string_literal: true

require "stringio"
%w[listings_page news_digest community_export member_actions].each do |example|
  require_relative "../examples/#{example}"
end

RSpec.describe "Examples" do
  let(:session) { instance_double(Audience::Kit::Session) }

  def listing(json) = Audience::Kit::PublicListing.from(json)

  describe ListingsPage do
    it "renders the public listings, escaped, by kind" do
      allow(session).to receive(:public_listings).and_return([
                                                               listing("kind" => "venue", "id" => "1", "title" => "Bar & Grill", "address" => "1 Main St"),
                                                               listing("kind" => "event", "id" => "2", "title" => "Drag Bingo", "start_at" => "2026-11-27T03:00:00Z",
                                                                       "venue_name" => "Bar & Grill", "ticket_url" => "https://t.example/2"),
                                                               listing("kind" => "event", "id" => "3", "title" => "Karaoke", "is_canceled" => true),
                                                               listing("kind" => "post", "id" => "4", "title" => "Hello", "description" => "News"),
                                                               listing("kind" => "post", "id" => "5", "title" => "Members", "visibility" => "community")
                                                             ])
      page = described_class.render(session)
      expect(page).to include("<h2>Venues</h2>", "Bar &amp; Grill, 1 Main St", "Fri Nov 27, 3:00am: Drag Bingo at Bar &amp; Grill")
      expect(page).to include(%(<a href="https://t.example/2">), "<s>Karaoke</s> (canceled)", "Hello: News")
      expect(page).not_to include("Members")
    end

    it "leaves out kinds with nothing listed" do
      allow(session).to receive(:public_listings).and_return([])
      expect(described_class.render(session, title: "Tonight")).not_to include("<h2>")
    end
  end

  describe NewsDigest do
    let(:phoenix) { Audience::Kit::Locale.from("id" => "l1", "name" => "Phoenix") }

    it "writes a locale's news and national news" do
      article = Audience::Kit::Article.from(
        "id" => "a1", "title" => "Opening night", "summary" => "A new bar.", "teaser" => true,
        "canonicalUrl" => "https://paper.example/a1", "disclosure" => "Sponsored.",
        "publishedAt" => "2026-11-20T12:00:00Z", "publication" => { "id" => "p1", "name" => "The Paper" }
      )
      allow(session).to receive(:articles).with(locale_id: "l1", first: 10).and_return([article])
      national = Audience::Kit::Article.from("id" => "n1", "title" => "Nationwide")
      allow(session).to receive_messages(locales: [phoenix], national_articles: [national])
      digest = described_class.markdown(session, locale_name: "phoenix")
      expect(digest).to include("## News in Phoenix", "[Opening night](https://paper.example/a1)",
                                "(The Paper, Nov 20)", "  A new bar.", "_Sponsored._", "- **Nationwide**\n")
    end

    it "is empty without locales or news" do
      allow(session).to receive_messages(locales: [], national_articles: [])
      expect(described_class.markdown(session)).to eq("")
    end
  end

  describe CommunityExport do
    it "exports the community as JSON, without hidden venues or canceled events" do
      community = Audience::Kit::Community.new(
        audience: Audience::Kit::Audience.from("id" => "aud-1", "name" => "Hot Mess"),
        locales: Audience::Kit::Locale.list([{ "id" => "l1" }]),
        venues: Audience::Kit::Venue.list([{ "id" => "v1" }, { "id" => "v2", "hidden" => true }]),
        people: [],
        events: Audience::Kit::Event.list([{ "id" => "e1" }, { "id" => "e2", "isCanceled" => true }]),
        event_series: []
      )
      allow(session).to receive(:community).and_return(community)
      json = described_class.to_h(session)
      expect(json["audience"]["name"]).to eq("Hot Mess")
      expect(json["venues"].map { |venue| venue["id"] }).to eq(["v1"])
      expect(json["events"].map { |event| event["id"] }).to eq(["e1"])
    end
  end

  describe MemberActions do
    let(:out) { StringIO.new }
    let(:event) do
      Audience::Kit::Event.from("id" => "e1", "name" => "Drag Bingo", "startAt" => "2026-11-27T03:00:00Z",
                                "venue" => { "name" => "The Eagle", "venue" => { "id" => "v1" } })
    end

    let(:rsvp) do
      Audience::Kit::EventRSVP.from("count" => 2, "counts" => { "going" => 2 },
                                    "attendees" => [{ "profile" => { "id" => "p", "name" => "Sam" } }])
    end
    let(:cover) do
      Audience::Kit::VenueCover.from("tickets" => { "cover" => {
                                       "charge" => { "payable" => true, "total" => { "cents" => 1200 } },
                                       "viewerAdmission" => { "id" => "ad1", "status" => "PAID", "passSecret" => "c2VjcmV0" }
                                     } })
    end

    before do
      allow(session).to receive_messages(
        me: Audience::Kit::SelfUser.from("id" => "u1", "name" => "Pat"),
        create_calendar_feed: Audience::Kit::CalendarFeed.from("url" => "https://cal.example/f.ics")
      )
    end

    it "walks through RSVP, the calendar, cover and chat" do
      allow(session).to receive(:events).with(first: 1).and_return([event])
      allow(session).to receive(:rsvp_event).with("e1", "ATTENDING").and_return("ATTENDING")
      allow(session).to receive(:event_rsvp).and_return(rsvp)
      allow(session).to receive(:venue_cover).with("v1").and_return(cover)
      allow(session).to receive(:send_chat_message).with("Hi", venue_id: "v1")
                                                   .and_return(Audience::Kit::ChatMessage.from("body" => "Hi"))
      described_class.run(session, rsvp: true, say: "Hi", out: out)
      expect(out.string).to include("Signed in as Pat", "Next: Drag Bingo at The Eagle", "Your RSVP: ATTENDING",
                                    "2 going: Sam", "webcal://cal.example/f.ics", "Cover tonight: $12.00",
                                    "Your pass code (show it as a QR code): HMC1.ad1.", "Said: Hi")
    end

    it "stops when nothing is coming up" do
      allow(session).to receive(:events).and_return([])
      described_class.run(session, out: out)
      expect(out.string).to include("Nothing coming up.")
    end

    it "skips what isn't there" do
      allow(session).to receive_messages(events: [Audience::Kit::Event.from("id" => "e2", "name" => "Show")],
                                         event_rsvp: Audience::Kit::EventRSVP.from("count" => 0))
      described_class.run(session, out: out)
      expect(out.string).to include("at TBA", "0 going\n")
      expect(out.string).not_to include("Cover")
    end
  end
end
