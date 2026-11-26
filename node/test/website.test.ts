import { describe, expect, it } from "vitest";
import { AudienceKitClient, AudienceKitError, InMemoryTokenStore, Website } from "../src/index.js";
import { AUDIENCE_ID, BASE_URL, StubTransport, data, json, type RecordedRequest, type Reply } from "./stubTransport.js";

const HOST = "hotmess.admin.audiencekit.com";

function website(respond: (request: RecordedRequest) => Reply, token: string | null = "session-token") {
  const stub = new StubTransport(respond);
  const client = new AudienceKitClient({
    configuration: { baseUrl: BASE_URL, audienceId: AUDIENCE_ID, host: HOST },
    tokenStore: new InMemoryTokenStore(token, AUDIENCE_ID),
    transport: stub,
  });
  return { site: new Website.WebsiteClient(client), client, stub };
}

async function rejects(promise: Promise<unknown>): Promise<AudienceKitError> {
  try {
    await promise;
  } catch (error) {
    expect(error).toBeInstanceOf(AudienceKitError);
    return error as AudienceKitError;
  }
  throw new Error("expected a rejection");
}

const venue = { id: "v", name: "Milk+", photoUrl: null, bannerUrl: null };
const event = { id: "e", name: "Bear Night", startAt: null, endAt: null, facebookId: null, bannerUrl: null, venue: { name: "Milk+", venue } };
const alert = { id: "a", state: "OPEN", venue: { id: "v", name: "Milk+" }, messages: [] };

describe("WebsiteClient pages", () => {
  it("reports where someone is and reads what's around them", async () => {
    const { site, stub } = website(() => data({ reportLocation: { venue, locale: null, nearbyVenues: [] } }));
    expect((await site.now(45.5, -122.6)).venue).toEqual(venue);
    expect(stub.last.path).toBe(`/v1/audience/${AUDIENCE_ID}/graphql`);
    expect(stub.last.query).toBe(Website.Queries.now);
    expect(stub.last.variables).toEqual({ position: { latitude: 45.5, longitude: -122.6 } });
    expect(stub.last.json().operationName).toBe("ReportLocation");
  });

  it("lists the cities someone is in, innermost first", async () => {
    const { site } = website(() => data({ reportLocation: { locale: { id: "pdx", label: "PDX" }, locales: [{ id: "west", label: null }] } }));
    expect(await site.whereAmI(1, 2)).toEqual([{ id: "west", label: null }, { id: "pdx", label: "PDX" }]);
    const none = website(() => data({ reportLocation: { locale: null, locales: null } }));
    expect(await none.site.whereAmI(1, 2)).toEqual([]);
  });

  it("reads a venue with its events, and NOT_FOUND for one that isn't there", async () => {
    const { site } = website(() => data({ venues: { venue: { ...venue, events: { upcoming: { nodes: [event, null] } } } } }));
    expect(await site.venue("v")).toEqual({ venue, events: [event] });
    const bare = website(() => data({ venues: { venue } }));
    expect(await bare.site.venue("v")).toEqual({ venue, events: [] });
    const missing = website(() => data({ venues: { venue: null } }));
    expect((await rejects(missing.site.venue("v"))).code).toBe("NOT_FOUND");
  });

  it("reads an event, a person, a post and the viewer", async () => {
    const { site, stub } = website((request) => {
      if (request.query.startsWith("query Event")) return data({ events: { event } });
      if (request.query.startsWith("query Person")) return data({ people: { person: { id: "p", name: "Aurora" } } });
      if (request.query.startsWith("query Post")) return data({ posts: { post: { id: "post" } } });
      return data({ me: { self: { id: "u" } } });
    });
    expect(await site.event("e")).toEqual(event);
    expect(stub.last.variables).toEqual({ id: "e" });
    expect((await site.person("p")).name).toBe("Aurora");
    expect((await site.post("post")).id).toBe("post");
    expect(await site.viewerId()).toBe("u");
    const signedOut = website(() => data({ me: null }));
    expect(await signedOut.site.viewerId()).toBeNull();
  });
});

describe("WebsiteClient posters", () => {
  it("searches venues and reads their nights", async () => {
    const { site, stub } = website((request) =>
      request.query.startsWith("query PosterSearch")
        ? data({ venues: { list: { nodes: [{ id: "v", name: "Milk+", locale: null, profile: null }] } } })
        : data({ venues: { venue: { events: { upcoming: { nodes: [{ id: "e" }] } } } } }),
    );
    expect((await site.posterSearch("milk")).map((v) => v.id)).toEqual(["v"]);
    expect(stub.last.variables).toEqual({ search: "milk" });
    expect(await site.posterNights("v")).toEqual([{ id: "e" }]);
  });

  it("reads a series, a venue, an event with its share link, and a cover", async () => {
    const series = { id: "s", name: "Bear Night", recurrenceText: "Every week", startTime: "21:00", timeZone: "America/Los_Angeles" };
    const { site, stub } = website((request) => {
      if (request.query.startsWith("query PosterSeries")) return data({ events: { eventSeries: { ...series, events: [{ id: "e" }] } } });
      if (request.query.startsWith("query PosterVenue")) return data({ venues: { venue: { id: "v" } } });
      if (request.query.startsWith("query PosterEvent")) return data({ events: { event: { id: "e" } }, shareLink: { url: "https://hotmess.social/events/e?e=v3.x" } });
      return data({ venues: { venue: { id: "v", tickets: { cover: { cents: 1000, payable: true } } } } });
    });
    expect(await site.posterSeries("s")).toEqual({ series, events: [{ id: "e" }] });
    expect((await site.posterVenue("v")).id).toBe("v");
    expect(await site.posterEvent("e")).toEqual({ event: { id: "e" }, link: "https://hotmess.social/events/e?e=v3.x" });
    expect(stub.last.variables).toEqual({ id: "e", path: "/events/e" });
    expect(await site.posterCover("v")).toEqual({ cents: 1000, payable: true });
  });

  it("reads a series without dates, an event without a link, and a venue without a cover", async () => {
    const { site } = website((request) => {
      if (request.query.startsWith("query PosterSeries")) return data({ events: { eventSeries: { id: "s", events: null } } });
      if (request.query.startsWith("query PosterEvent")) return data({ events: { event: { id: "e" } }, shareLink: null });
      return data({ venues: { venue: { id: "v", tickets: null } } });
    });
    expect((await site.posterSeries("s")).events).toEqual([]);
    expect((await site.posterEvent("e", "/custom")).link).toBeNull();
    expect(await site.posterCover("v")).toBeNull();
  });

  it("prints a safety poster, and fails when the API returns none", async () => {
    const { site } = website(() => data({ printSafetyPoster: { safetyPoster: { code: "abc", url: "https://hotmess.social/help/abc" } } }));
    expect(await site.printSafetyPoster("v")).toBe("https://hotmess.social/help/abc");
    const empty = website(() => data({ printSafetyPoster: null }));
    expect((await rejects(empty.site.printSafetyPoster("v"))).code).toBe("DECODING");
  });
});

describe("WebsiteClient safety alerts", () => {
  it("sends, updates, reminds, cancels and messages an alert", async () => {
    const { site, stub } = website((request) => {
      const operation = /mutation (\w+)/.exec(request.query)![1]!;
      const key = operation.charAt(0).toLowerCase() + operation.slice(1);
      return data({ [key]: { safetyAlert: alert } });
    });
    const draft = { place: "BAR" as const, concerns: ["FOLLOWING" as const], description: "  near the bar " };
    expect(await site.sendSafetyAlert("v", draft)).toEqual(alert);
    expect(stub.last.variables).toEqual({ venueId: "v", place: "BAR", concerns: ["FOLLOWING"], description: "near the bar" });
    await site.updateSafetyAlert("a", { ...draft, description: " " });
    expect(stub.last.variables).toEqual({ id: "a", place: "BAR", concerns: ["FOLLOWING"], description: null });
    await site.remindSafetyAlert("a");
    await site.cancelSafetyAlert("a");
    await site.sendSafetyAlertMessage("a", " on my way ");
    expect(stub.last.variables).toEqual({ id: "a", body: "on my way" });
  });

  it("fails when a mutation returns no alert", async () => {
    const { site } = website(() => data({ remindSafetyAlert: { safetyAlert: null } }));
    expect((await rejects(site.remindSafetyAlert("a"))).code).toBe("DECODING");
  });

  it("reads alerts, the venue's safety and support", async () => {
    const { site } = website((request) => {
      if (request.query.startsWith("query SafetyAlert(")) return data({ me: { safetyAlert: alert } });
      if (request.query.startsWith("query MySafetyAlerts")) return data({ me: { safetyAlerts: [alert] } });
      if (request.query.startsWith("query VenueSafety")) return data({ venues: { venue: { id: "v", point: null, canSendSafetyAlert: true, safetyStaffOnShift: false } } });
      if (request.query.startsWith("query SupportRides")) return data({ supportResources: { rides: [{ id: "uber" }] } });
      return data({ supportResources: { region: "US", name: "United States", emergency: "911", checkedAt: null, lines: [] } });
    });
    expect(await site.safetyAlert("a")).toEqual(alert);
    expect(await site.mySafetyAlerts()).toEqual([alert]);
    expect((await site.venueSafety("v"))?.canSendSafetyAlert).toBe(true);
    expect((await site.supportResources()).emergency).toBe("911");
    expect(await site.supportRides("US")).toEqual([{ id: "uber" }]);
  });

  it("reads no alerts when signed out", async () => {
    const { site } = website((request) =>
      request.query.startsWith("query SupportRides") ? data({ supportResources: { rides: null } }) : data({ me: null }),
    );
    expect(await site.safetyAlert("a")).toBeNull();
    expect(await site.mySafetyAlerts()).toEqual([]);
    expect(await site.supportRides()).toEqual([]);
  });
});

describe("WebsiteClient privacy choices", () => {
  it("reads, changes and buys a pass", async () => {
    const privacy = { saleShareOptedOut: true };
    const { site, stub } = website((request) => {
      if (request.query.startsWith("query Privacy")) return data({ privacyOffer: { choices: [], passCents: null, passDays: 30 }, me: null });
      if (request.query.startsWith("mutation UpdatePrivacyChoices")) return data({ updatePrivacyChoices: { privacy } });
      return data({ startPrivacyPass: { checkoutUrl: "https://checkout", passId: "p" } });
    });
    expect((await site.privacy()).privacyOffer.passDays).toBe(30);
    expect(await site.updatePrivacyChoices({ saleShareOptOut: true })).toEqual(privacy);
    expect(stub.last.variables).toEqual({ saleShareOptOut: true });
    expect(await site.startPrivacyPass("https://hotmess.social/privacy")).toEqual({ checkoutUrl: "https://checkout", passId: "p" });
    await site.startPrivacyPass();
    expect(stub.last.variables).toEqual({ returnUrl: null });
  });
});

describe("WebsiteClient public REST", () => {
  it("reads the sign-in methods without a session, and null from an API without them", async () => {
    const { site, stub } = website(() => json(200, { methods: ["apple", "facebook"], warnings: { facebook: "Heads up" } }), null);
    expect(await site.signInMethods()).toEqual({ methods: ["apple", "facebook"], warnings: { facebook: "Heads up" } });
    expect(stub.last.path).toBe("/v1/token/methods");
    expect(stub.last.url.searchParams.get("host")).toBe(HOST);
    expect(stub.last.header("Authorization")).toBeUndefined();
    const bare = website(() => json(200, { methods: ["facebook"] }));
    expect(await bare.site.signInMethods("other.host")).toEqual({ methods: ["facebook"], warnings: {} });
    expect(bare.stub.last.url.searchParams.get("host")).toBe("other.host");
    const old = website(() => json(404, { error: "NOT_FOUND" }));
    expect(await old.site.signInMethods()).toBeNull();
    const empty = website(() => json(200, {}));
    expect(await empty.site.signInMethods()).toBeNull();
  });

  it("answers a share link's status and card", async () => {
    const { site, stub } = website((request) =>
      request.url.searchParams.get("e") === "forged" ? json(410, { error: "GONE" }) : json(200, { title: "Bear Night" }),
    );
    expect(await site.shareLink("/events/e")).toEqual({ status: 200, card: { title: "Bear Night" } });
    expect(stub.last.url.searchParams.has("e")).toBe(false);
    expect(await site.shareLink("/events/e", "forged")).toEqual({ status: 410, card: null });
    const offline = website(() => ({ error: new Error("offline") }));
    expect((await rejects(offline.site.shareLink("/events/e"))).code).toBe("NETWORK");
  });

  it("reads an invitation, null when it ended, and fails when the API does", async () => {
    const { site, stub } = website(() => json(200, { note: "Come out" }));
    expect(await site.invitation("p", "sig", "hotmess.social")).toEqual({ note: "Come out" });
    expect(Object.fromEntries(stub.last.url.searchParams)).toEqual({ host: "hotmess.social", path: "/pings/p", e: "sig" });
    const ended = website(() => json(410, {}));
    expect(await ended.site.invitation("p", "sig")).toBeNull();
    const down = website(() => json(503, {}));
    expect((await rejects(down.site.invitation("p", "sig"))).status).toBe(503);
  });

  it("reads the rate card and community resources", async () => {
    const { site, stub } = website((request) => {
      if (request.path === "/v1/promoted/rate_card") return json(200, { currency: "usd" });
      if (request.path.endsWith("/locales")) return json(200, { locales: [] });
      return request.url.searchParams.get("locale_id") === "gone" ? json(404, {}) : json(200, { locale: { id: "pdx" } });
    });
    expect(await site.rateCard()).toEqual({ currency: "usd" });
    expect(await site.communityResourceLocales()).toEqual({ locales: [] });
    expect(stub.last.path).toBe(`/v1/audience/${AUDIENCE_ID}/community_resources/locales`);
    expect(await site.communityResources("pdx")).toEqual({ locale: { id: "pdx" } });
    expect(await site.communityResources("gone")).toBeNull();
  });

  it("follows a short link with the session, null for none", async () => {
    const { site, stub } = website((request) => (request.path.endsWith("/nope1234") ? json(404, {}) : json(200, { path: "/venues/v/chat" })));
    expect(await site.publicShortLink("abcd1234")).toBe("/venues/v/chat");
    expect(stub.last.header("Authorization")).toBe("Bearer session-token");
    expect(await site.publicShortLink("nope1234")).toBeNull();
    const odd = website(() => json(200, { path: 7 }));
    expect(await odd.site.publicShortLink("abcd1234")).toBeNull();
  });

  it("fails on a body that isn't JSON, and keeps the API's error details", async () => {
    const { site } = website(() => json(200, "<html>"));
    expect((await rejects(site.rateCard())).code).toBe("DECODING");
    const invalid = website(() => json(422, { error: "INVALID", message: "Pick a tier", fields: { tier: ["is not offered"] } }));
    const error = await rejects(invalid.site.startGuestCover("v", 1, "vip"));
    expect([error.code, error.status, error.apiCode, error.message, error.fields]).toEqual(["HTTP", 422, "INVALID", "Pick a tier", { tier: ["is not offered"] }]);
  });

  it("needs a host for the calls that name the audience", async () => {
    const stub = new StubTransport(() => json(200, {}));
    const site = new Website.WebsiteClient(new AudienceKitClient({ configuration: { baseUrl: BASE_URL, audienceId: AUDIENCE_ID }, transport: stub }));
    expect((await rejects(site.signInMethods())).code).toBe("MISSING_CONFIGURATION");
  });
});

describe("WebsiteClient cover poster", () => {
  it("reads a poster and checks a guest out", async () => {
    const { site, stub } = website((request) => {
      if (request.path === "/v1/cover/gone") return json(404, {});
      if (request.method === "GET") return json(200, { venue: { id: "v" } });
      if (request.path.endsWith("/confirm")) return json(200, { admission: { id: "adm" } });
      return json(200, { claim_token: "claim" });
    });
    expect(await site.coverPoster("abcd1234")).toEqual({ venue: { id: "v" } });
    expect(stub.last.url.searchParams.get("host")).toBe(HOST);
    expect(await site.coverPoster("gone", "hotmess.social")).toBeNull();
    expect(stub.last.url.searchParams.get("host")).toBe("hotmess.social");
    await site.startGuestCover("v", 2, null);
    expect(stub.last.json()).toEqual({ host: HOST, venue_id: "v", quantity: 2, tier: null });
    await site.startGuestCover("v", 1, "sliding", 1500);
    expect(stub.last.json()).toEqual({ host: HOST, venue_id: "v", quantity: 1, tier: "sliding", amount_cents: 1500 });
    expect(stub.last.header("Authorization")).toBeUndefined();
    expect(await site.confirmGuestCover("adm", "claim")).toEqual({ admission: { id: "adm" } });
    expect(stub.last.json()).toEqual({ host: HOST, claim_token: "claim" });
  });
});

describe("WebsiteClient safety poster", () => {
  it("reads a poster, sends an alert and follows it with the guest token", async () => {
    const { site, stub } = website((request) => {
      if (request.path === "/v1/safety/posters/gone") return json(404, {});
      if (request.path === "/v1/safety/posters/abc") return json(200, { venue: { id: "v" }, staff_on_shift: true });
      return json(200, { alert: { id: "a" }, guest_token: "guest" });
    });
    expect(await site.safetyPoster("abc")).toEqual({ venue: { id: "v" }, staff_on_shift: true });
    expect(stub.last.header("X-Safety-Token")).toBeUndefined();
    expect(await site.safetyPoster("gone")).toBeNull();
    await site.sendGuestSafetyAlert("abc", { place: "bar", concerns: ["following"], description: null });
    expect(stub.last.path).toBe("/v1/safety/posters/abc/alerts");
    expect(stub.last.json()).toEqual({ place: "bar", concerns: ["following"], description: null });
    expect(stub.last.url.searchParams.get("host")).toBe(HOST);
    await site.guestSafetyAlert("a", "guest");
    expect([stub.last.method, stub.last.path, stub.last.header("X-Safety-Token")]).toEqual(["GET", "/v1/safety/alerts/a", "guest"]);
    await site.updateGuestSafetyAlert("a", "guest", { place: "patio" });
    expect(stub.last.path).toBe("/v1/safety/alerts/a/details");
    await site.remindGuestSafetyAlert("a", "guest");
    expect([stub.last.method, stub.last.path, stub.last.body]).toEqual(["POST", "/v1/safety/alerts/a/remind", null]);
    await site.cancelGuestSafetyAlert("a", "guest");
    expect(stub.last.path).toBe("/v1/safety/alerts/a/cancel");
    await site.messageGuestSafetyAlert("a", "guest", "thanks");
    expect(stub.last.json()).toEqual({ body: "thanks" });
  });

  it("passes on other failures", async () => {
    const { site } = website(() => json(500, {}));
    expect((await rejects(site.safetyPoster("abc"))).status).toBe(500);
    expect((await rejects(site.coverPoster("abc"))).status).toBe(500);
    const gateway = website(() => json(502, "<html>Bad gateway</html>"));
    const error = await rejects(gateway.site.rateCard());
    expect([error.code, error.status, error.apiCode, error.message]).toEqual(["HTTP", 502, undefined, "The server responded with status 502."]);
  });
});

describe("signInWithGoogleAccessToken", () => {
  it("exchanges a Google access token for a session", async () => {
    const stub = new StubTransport(() => json(200, { token: "jwt", userId: "u", audienceId: AUDIENCE_ID, role: "member" }));
    const client = new AudienceKitClient({ configuration: { baseUrl: BASE_URL, host: HOST }, transport: stub });
    await client.signInWithGoogleAccessToken("ya29", { identifier: "browser", type: "web" });
    expect(stub.last.path).toBe("/v1/token/google");
    expect(stub.last.json()).toEqual({ access_token: "ya29", host: HOST, device: { type: "web", identifier: "browser" } });
    expect(await client.sessionToken()).toBe("jwt");
  });
});
