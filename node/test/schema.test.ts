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
  });
});
