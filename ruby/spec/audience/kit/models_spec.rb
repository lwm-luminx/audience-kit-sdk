# frozen_string_literal: true

RSpec.describe Audience::Kit::Model do
  let(:venue) do
    Audience::Kit::Venue.new(
      "id" => 7, "name" => "The Eagle", "order" => "3", "hidden" => "yes", "description" => "Bar",
      "location" => { "point" => "SRID=4326;POINT (-112.07 33.45)", "places" => { "placeId" => "g1" } },
      "profile" => { "address" => "1 Main", "socialLinks" => { "nodes" => [{ "url" => "https://ig" }, 1] },
                     "facebook" => { "page" => { "id" => "fb", "name" => "Eagle" } } },
      "chat" => { "open" => false, "recentMessages" => { "nodes" => [{ "id" => "m", "body" => "hi", "sentAt" => "bad" }] } },
      "events" => { "upcoming" => { "nodes" => [{ "id" => "e1" }] } }
    )
  end

  it "reads typed fields over the raw JSON" do
    expect(venue).to have_attributes(id: "7", order: 3, hidden?: false, description: "Bar", address: "1 Main",
                                     chat_open: false)
    expect(venue.location.place_id).to eq("g1")
    expect(venue.coordinate.to_wkt).to eq("POINT (-112.07 33.45)")
    expect(venue.facebook_page.name).to eq("Eagle")
    expect(venue.social_links).to eq([{ "url" => "https://ig" }])
    expect(venue.recent_messages.first).to have_attributes(body: "hi", sent_at: nil, pinned?: false)
    expect(venue.upcoming_events.map(&:id)).to eq(["e1"])
    expect(venue["name"]).to eq("The Eagle")
    expect(venue[:name]).to eq("The Eagle")
    expect(venue.data).to equal(venue.raw)
    expect(venue.dig(:profile, :address)).to eq("1 Main")
    expect(venue.dig(:name, :x)).to be_nil
    expect(JSON.parse(venue.to_json)).to eq(venue.to_h)
    expect(venue.inspect).to eq('#<Audience::Kit::Venue id="7" name="The Eagle" hidden?=false order=3>')
  end

  it "compares by class and JSON" do
    same = Audience::Kit::Venue.new(venue.raw.dup)
    expect(same).to eq(venue)
    expect(same.hash).to eq(venue.hash)
    expect(Audience::Kit::Event.new(venue.raw)).not_to eq(venue)
  end

  it "builds models from JSON, skipping what isn't an object" do
    expect(Audience::Kit::Tag.from(nil)).to be_nil
    expect(Audience::Kit::Tag.list("x")).to eq([])
    expect(Audience::Kit::Tag.list("nodes" => nil)).to eq([])
    expect(Audience::Kit::Tag.list([{ "id" => "a", "color" => "#0f0" }, nil]).first.color.to_hex).to eq("#00ff00")
    expect(Audience::Kit::Tag.new({}).color).to be_nil
    expect(Audience::Kit::Venue.new({}).chat_open).to be_nil
    expect(Audience::Kit::Venue.new({}).coordinate).to be_nil
    expect(Audience::Kit::Location.new({}).coordinate).to be_nil
    expect(Audience::Kit::CoverCharge.new({})).not_to be_coat_check
    expect(Audience::Kit::Locale.new("cityNames" => ["Phoenix", 1]).city_names).to eq(["Phoenix"])
    expect(Audience::Kit::Locale.new({}).city_names).to eq([])
  end

  it "casts integers and times" do
    expect(described_class.integer(2.9)).to eq(2)
    expect(described_class.integer("x")).to be_nil
    expect(described_class.time("2026-11-26T20:00:00Z")).to eq(Time.utc(2026, 11, 26, 20))
    expect(described_class.time("")).to be_nil
    expect(described_class.cast(1.5, :string, nil)).to eq("1.5")
    expect(described_class.cast(nil, :hashes, nil)).to eq([])
  end

  describe Audience::Kit::Event do
    let(:at) { Time.utc(2026, 11, 26, 20) }

    it "reads module fields and who hosts it" do
      event = described_class.new(
        "id" => "e1", "startAt" => "2026-11-26T19:00:00Z", "isCanceled" => true,
        "venue" => { "name" => "Eagle", "venue" => { "id" => "v1" } }, "rsvp" => { "mine" => "MAYBE", "count" => 4 },
        "people" => { "hosts" => { "nodes" => [] }, "lineup" => { "nodes" => [] },
                      "jockeys" => { "nodes" => [{ "id" => "kj" }] }, "jockeyLabel" => "KJ" },
        "tickets" => { "url" => "https://t", "offers" => { "nodes" => [{ "price" => { "cents" => 500 }, "seller" => { "key" => "dice", "name" => "DICE" } }] },
                       "cover" => { "charge" => { "scale" => { "min" => { "cents" => 0 }, "max" => { "cents" => 2000 } },
                                                  "coatCheck" => { "payable" => true }, "from" => "2026-11-26T21:00:00Z" } } }
      )
      expect(event).to have_attributes(canceled?: true, venue_name: "Eagle", rsvp: "MAYBE", rsvp_count: 4,
                                       jockey_label: "KJ", ticket_url: "https://t")
      expect(event.venue.id).to eq("v1")
      expect(event.effective_hosts.map(&:id)).to eq(["kj"])
      expect(event.offers.first).to have_attributes(seller_key: "dice", seller_name: "DICE")
      expect(event.offers.first.price.format).to eq("$5.00")
      expect(event.cover).to be_sliding_scale
      expect(event.cover).to be_coat_check
      expect(event).to be_ended(at)
      expect(described_class.new("startAt" => "2026-11-26T19:00:00Z", "endAt" => "2026-11-26T23:00:00Z")).not_to be_ended(at)
      expect(described_class.new({})).not_to be_ended
      expect(described_class.new("people" => { "hosts" => { "nodes" => [{ "id" => "h" }] } }).effective_hosts.map(&:id)).to eq(["h"])
    end

    it "is found with the module-level session" do
      Audience::Kit.session = signed_in_session
      answer("events" => { "event" => { "id" => "e1" } })
      answer("events" => { "event" => nil })
      expect(described_class.find("e1").id).to eq("e1")
      expect { described_class.find(2) }.to raise_error(Audience::Kit::Error) { |e| expect(e.code).to eq("NOT_FOUND") }
    end
  end

  describe Audience::Kit::Venue do
    it "is found with the module-level session" do
      Audience::Kit.session = signed_in_session
      answer("venues" => { "venue" => { "id" => "1" } })
      answer("venues" => { "venue" => nil })
      expect(described_class.find(1).data).to eq("id" => "1")
      expect { described_class.find(0) }.to raise_error(Audience::Kit::Error, "There is no venue 0.")
    end
  end

  it "reads people, series, publications and articles" do
    person = Audience::Kit::Person.new("id" => "p", "global" => true, "venues" => { "home" => { "id" => "v" } },
                                       "events" => { "involvements" => { "edges" => [{ "role" => "DJ" }] } },
                                       "locales" => [{ "id" => "l" }])
    expect(person).to have_attributes(global?: true, like_required?: false)
    expect(person.home_venue.id).to eq("v")
    expect(person.involvements).to eq([{ "role" => "DJ" }])
    series = Audience::Kit::EventSeries.new("durationMinutes" => 120, "venue" => { "name" => "Eagle" })
    expect(series).to have_attributes(duration_minutes: 120, venue_name: "Eagle", venue: nil)
    publication = Audience::Kit::Publication.new("acceptsOpEds" => true, "adFreeTipCents" => 300, "person" => { "id" => "x" })
    expect(publication).to have_attributes(accepts_op_eds?: true, ad_free_tip_cents: 300, ad_free_offered?: false)
    article = Audience::Kit::Article.new("teaser" => true, "publication" => { "name" => "News" }, "publishedAt" => "2026-11-01T00:00:00Z")
    expect(article).to have_attributes(teaser?: true, title: "", published_at: Time.utc(2026, 11, 1))
    expect(article.publication.name).to eq("News")
    expect(article.subjects).to eq({})
  end

  it "reads admissions and their door codes" do
    admission = Audience::Kit::Admission.new("id" => "a1", "passSecret" => "c2VjcmV0", "quantity" => 2,
                                             "total" => { "cents" => 123_456, "currency" => "CHF" }, "venue" => { "id" => "v" })
    expect(admission).to have_attributes(status: "PENDING", kind: "COVER", quantity: 2, paid?: false, venue: { "id" => "v" })
    expect(admission.total.format).to eq("1,234.56 CHF")
    expect(admission.pass_code(1_000_000_000)).to eq(Audience::Kit::CoverPass.code("a1", "c2VjcmV0", 1_000_000_000))
    expect(Audience::Kit::Admission.new({}).pass_code).to be_nil
    expect(Audience::Kit::Money.new("cents" => -50).to_s).to eq("-$0.50")
  end

  it "reads calendar feeds, listings and pages" do
    feed = Audience::Kit::CalendarFeed.new("url" => "http://x/c.ics", "googleUrl" => "https://g")
    expect([feed.webcal_url, feed.google_url, feed.venue_ids]).to eq(["webcal://x/c.ics", "https://g", []])
    expect(Audience::Kit::CalendarFeed.new({}).google_url).to eq("https://calendar.google.com/calendar/render?cid=")
    listing = Audience::Kit::PublicListing.new("kind" => "event", "start_at" => "2026-11-26T20:00:00Z", "cover_cents" => 500, "is_canceled" => false)
    expect(listing).to have_attributes(public?: true, start_at: Time.utc(2026, 11, 26, 20), cover_cents: 500, canceled: false)
    expect(Audience::Kit::ArticlesPage.from_connection(nil)).to have_attributes(articles: [], next_page?: false)
    page = Audience::Kit::ArticlesPage.from_connection("nodes" => [], "pageInfo" => { "hasNextPage" => true })
    expect(page.end_cursor).to be_nil
  end
end
