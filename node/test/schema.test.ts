import { readFileSync } from "node:fs";
import { buildSchema, parse, validate } from "graphql";
import { describe, expect, it } from "vitest";
import { Queries, SchemaShape } from "../src/index.js";

// Every document the SDK sends, as it is for an audience with every module, must validate against the API's consumer
// schema (graphql/schema.graphql, the API's next branch), so a renamed or removed field fails here instead of at runtime.
const schema = buildSchema(readFileSync(new URL("../../graphql/schema.graphql", import.meta.url), "utf8"));

const documents: Record<string, string> = {
  audience: Queries.audience,
  venues: Queries.venues(),
  people: Queries.people(),
  locales: Queries.locales(),
  me: Queries.me,
  closestLocale: Queries.closestLocale(),
  reportLocation: Queries.reportLocation("venue { id } locale { id } nearbyVenues { id }"),
  rsvpEvent: Queries.rsvpEvent,
  cancelRsvp: Queries.cancelRsvp,
  eventRsvp: Queries.eventRsvp,
  tribes: Queries.tribes,
  identifyWithTribe: Queries.identifyWithTribe,
  leaveTribe: Queries.leaveTribe,
  registerDevice: Queries.registerDevice,
  admissions: Queries.admissions,
  venueCover: Queries.venueCover(),
  buyCover: Queries.buyCover,
  buyCoatCheck: Queries.buyCoatCheck,
  payCover: Queries.payCover,
  confirmCover: Queries.confirmCover,
  refundAdmission: Queries.refundAdmission,
  node: Queries.node,
  events: Queries.events(),
  event: Queries.event(),
  eventSeries: Queries.eventSeries(),
  venueOffers: Queries.venueOffers(),
  venueDetail: Queries.venueDetail(),
  sendChatMessage: Queries.sendChatMessage,
  removeChatMessage: Queries.removeChatMessage,
  venueChatRoom: Queries.chatRoom({ kind: "venue", id: "v" }, true),
  localeChatRoom: Queries.chatRoom({ kind: "locale", id: "l" }),
  articles: Queries.articles(),
  articlesPage: Queries.articlesPage(),
  nationalArticles: Queries.nationalArticles(),
  article: Queries.article(),
  articlesAboutVenue: Queries.articlesAbout("venue"),
  articlesAboutEvent: Queries.articlesAbout("event"),
  articlesAboutPerson: Queries.articlesAbout("person"),
  articlesAboutLocale: Queries.articlesAbout("locale"),
  publications: Queries.publications(),
  publication: Queries.publication(),
  myOpEds: Queries.myOpEds(),
  submitOpEd: Queries.submitOpEd,
  calendarFeed: Queries.calendarFeed,
  createCalendarFeed: Queries.createCalendarFeed,
  setCalendarFeedVenue: Queries.setCalendarFeedVenue,
  deleteCalendarFeed: Queries.deleteCalendarFeed,
  reportContent: Queries.reportContent,
  blockUser: Queries.blockUser,
  unblockUser: Queries.unblockUser,
  deleteAccount: Queries.deleteAccount,
};

describe("the SDK's documents", () => {
  for (const [name, document] of Object.entries(documents)) {
    it(`${name} validates against the consumer schema`, () => {
      const errors = validate(schema, parse(document));
      expect(errors.map((e) => e.message)).toEqual([]);
    });
  }

  it("still parse for an audience with no modules", () => {
    const bare = new SchemaShape({});
    for (const build of [Queries.venues, Queries.people, Queries.locales, Queries.closestLocale, Queries.venueCover, Queries.events, Queries.event, Queries.eventSeries, Queries.venueOffers, Queries.venueDetail]) {
      expect(() => parse(build(bare))).not.toThrow();
    }
    expect(Queries.venueOffers(bare)).not.toContain("$night");
    expect(Queries.venueDetail(bare)).not.toContain("$recentMessages");
    expect(Queries.events(bare)).not.toContain("rsvp");
    for (const build of [Queries.articles, Queries.articlesPage, Queries.nationalArticles, Queries.article, Queries.publications, Queries.publication, Queries.myOpEds]) {
      expect(build(bare)).toMatch(/^query \w+ \{ id \}$/);
    }
    expect(Queries.articlesAbout("locale", bare)).toBe("query ArticlesAbout { id }");
    const beforeTips = new SchemaShape({ Audience: ["soapbox"], Article: ["id"], Publication: ["id"] });
    expect(Queries.articles(beforeTips)).not.toContain("viewerAdFree");
    expect(Queries.publication(beforeTips)).not.toContain("adFreeOffered");
    expect(Queries.nationalArticles(beforeTips)).toBe("query NationalArticles { id }");
  });
});
