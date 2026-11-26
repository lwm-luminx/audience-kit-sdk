import { describe, expect, it } from "vitest";
import {
  AudienceKitClient,
  AudienceKitError,
  InMemoryTokenStore,
  REPORT_REASONS,
  isPublicListing,
} from "../src/index.js";
import { AUDIENCE_ID, BASE_URL, StubTransport, data, json, type RecordedRequest, type Reply } from "./stubTransport.js";

const inAnHour = () => new Date(Date.now() + 3_600_000).toISOString();
const serviceSession = (token: string, expiresAt: string | null = inAnHour()) => ({
  token,
  userId: null,
  audienceId: AUDIENCE_ID,
  role: "service",
  endpoint: `${BASE_URL}/v1/audience/${AUDIENCE_ID}/graphql`,
  expiresAt,
});

function signedIn(respond: (request: RecordedRequest) => Reply) {
  const stub = new StubTransport(respond);
  const client = new AudienceKitClient({
    configuration: { baseUrl: BASE_URL, audienceId: AUDIENCE_ID },
    tokenStore: new InMemoryTokenStore("session-token", AUDIENCE_ID),
    transport: stub,
  });
  return { client, stub };
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

describe("fromEnvironment", () => {
  it("trades a service token for a session before the first call", async () => {
    const stub = new StubTransport((request) =>
      request.path === "/v1/token/service" ? json(200, serviceSession("service-jwt")) : data({ id: AUDIENCE_ID, name: "Hot Mess", subdomain: "hotmess" }),
    );
    const client = AudienceKitClient.fromEnvironment(
      { AUDIENCEKIT_TOKEN: "akst_abc_secret", AUDIENCEKIT_BASE_URL: BASE_URL, AUDIENCEKIT_HOST: "hotmess.social", AUDIENCEKIT_ENVIRONMENT: "staging" },
      { transport: stub },
    );
    expect(client.configuration.host).toBe("hotmess.social");
    expect(client.configuration.environment).toBe("staging");
    await client.audience();
    expect(stub.requests[0]!.path).toBe("/v1/token/service");
    expect(stub.requests[0]!.json()).toEqual({ service_token: "akst_abc_secret" });
    expect(stub.requests[0]!.header("Authorization")).toBeUndefined();
    expect(stub.last.path).toBe(`/v1/audience/${AUDIENCE_ID}/graphql`);
    expect(stub.last.header("Authorization")).toBe("Bearer service-jwt");
  });

  it("sends another bearer value as is", async () => {
    const stub = new StubTransport(() => data({ id: AUDIENCE_ID, name: "Hot Mess", subdomain: "hotmess" }));
    const client = AudienceKitClient.fromEnvironment(
      { AUDIENCEKIT_TOKEN: "app-api-key", AUDIENCEKIT_BASE_URL: BASE_URL, AUDIENCEKIT_AUDIENCE_ID: AUDIENCE_ID, AUDIENCEKIT_HOST: "" },
      { transport: stub },
    );
    expect(client.configuration.host).toBeNull();
    expect(client.configuration.environment).toBe("production");
    await client.audience();
    expect(stub.requests).toHaveLength(1);
    expect(stub.last.header("Authorization")).toBe("Bearer app-api-key");
    expect(await client.isSignedIn()).toBe(true);
  });

  it("reads process.env by default and is signed out without a token", async () => {
    const saved = process.env.AUDIENCEKIT_TOKEN;
    delete process.env.AUDIENCEKIT_TOKEN;
    try {
      const client = AudienceKitClient.fromEnvironment();
      expect(await client.isSignedIn()).toBe(false);
    } finally {
      if (saved !== undefined) process.env.AUDIENCEKIT_TOKEN = saved;
    }
  });
});

describe("service tokens", () => {
  it("trades again a minute before the session runs out, and once more when the API refuses it", async () => {
    let trades = 0;
    let refuseNext = false;
    const stub = new StubTransport((request) => {
      if (request.path === "/v1/token/service") {
        trades += 1;
        // The first session is about to expire; later ones last an hour.
        return json(200, serviceSession(`jwt-${trades}`, trades === 1 ? new Date(Date.now() + 30_000).toISOString() : inAnHour()));
      }
      if (refuseNext) {
        refuseNext = false;
        return json(401, { error: "unauthorized" });
      }
      return data({ id: AUDIENCE_ID, name: "Hot Mess", subdomain: "hotmess" });
    });
    const client = new AudienceKitClient({ configuration: { baseUrl: BASE_URL, audienceId: AUDIENCE_ID }, transport: stub });
    const credential = await client.useServiceToken("akst_x_y");
    expect(credential.token).toBe("jwt-1");
    expect(credential.userId).toBe("");

    await client.audience();
    expect(trades).toBe(2);
    expect(stub.last.header("Authorization")).toBe("Bearer jwt-2");

    refuseNext = true;
    await client.audience();
    expect(trades).toBe(3);
    expect(stub.last.header("Authorization")).toBe("Bearer jwt-3");
  });

  it("trades once for calls made together", async () => {
    let trades = 0;
    const stub = new StubTransport((request) => {
      if (request.path === "/v1/token/service") {
        trades += 1;
        return json(200, serviceSession("jwt", null));
      }
      return data({ venues: { list: { nodes: [] } } });
    });
    const client = AudienceKitClient.fromEnvironment({ AUDIENCEKIT_TOKEN: "akst_a_b", AUDIENCEKIT_BASE_URL: BASE_URL, AUDIENCEKIT_AUDIENCE_ID: AUDIENCE_ID }, { transport: stub });
    await Promise.all([client.venues(), client.venues(), client.venues()]);
    expect(trades).toBe(1);
  });

  it("throws UNAUTHORIZED for a revoked token and forgets it", async () => {
    const stub = new StubTransport(() => json(401, { error: "unauthorized" }));
    const client = new AudienceKitClient({ configuration: { baseUrl: BASE_URL, audienceId: AUDIENCE_ID }, transport: stub });
    const error = await rejects(client.useServiceToken("akst_revoked"));
    expect(error.code).toBe("UNAUTHORIZED");
    expect(error.message).toContain("service token");
    expect((await rejects(client.audience())).code).toBe("NOT_SIGNED_IN");
  });

  it("reports other failures and bad answers", async () => {
    const failing = new AudienceKitClient({ configuration: { baseUrl: BASE_URL }, transport: new StubTransport(() => json(500, "")) });
    expect((await rejects(failing.useServiceToken("akst_a"))).code).toBe("HTTP");
    const garbled = new AudienceKitClient({ configuration: { baseUrl: BASE_URL }, transport: new StubTransport(() => json(200, { nope: true })) });
    expect((await rejects(garbled.useServiceToken("akst_a"))).code).toBe("DECODING");
  });

  it("forgets the service token on sign-out", async () => {
    const stub = new StubTransport(() => json(200, serviceSession("jwt")));
    const client = new AudienceKitClient({ configuration: { baseUrl: BASE_URL, audienceId: AUDIENCE_ID }, transport: stub });
    await client.useServiceToken("akst_a");
    await client.signOut();
    expect((await rejects(client.audience())).code).toBe("NOT_SIGNED_IN");
    expect(stub.requests).toHaveLength(1);
  });

  it("useBearerToken replaces a service token", async () => {
    const stub = new StubTransport((request) =>
      request.path === "/v1/token/service" ? json(200, serviceSession("jwt")) : data({ id: AUDIENCE_ID, name: "x", subdomain: "x" }),
    );
    const client = new AudienceKitClient({ configuration: { baseUrl: BASE_URL, audienceId: AUDIENCE_ID }, transport: stub });
    await client.useServiceToken("akst_a");
    await client.useBearerToken("api-key");
    await client.audience();
    expect(stub.last.header("Authorization")).toBe("Bearer api-key");
  });
});

describe("public listings", () => {
  const venue = { kind: "venue", id: "v1", title: "Club", visibility: "public" };
  const event = { kind: "event", id: "e1", title: "Drag Brunch", visibility: "community", start_at: "2026-12-01T03:00:00Z" };

  it("reads every page", async () => {
    const { client, stub } = signedIn((request) =>
      request.url.searchParams.get("page") === "1"
        ? json(200, { listings: [venue], page_count: "2", next_page: 2 })
        : json(200, { listings: [event], page_count: 2, next_page: null }),
    );
    const listings = await client.publicListings();
    expect(listings.map((listing) => listing.id)).toEqual(["v1", "e1"]);
    expect(listings.map(isPublicListing)).toEqual([true, false]);
    expect(isPublicListing({ kind: "post", id: "p" })).toBe(true);
    expect(stub.requests.map((request) => request.url.searchParams.get("page"))).toEqual(["1", "2"]);
    expect(stub.last.path).toBe("/v1/public/listings");
  });

  it("reads a page with defaults when the API leaves things out", async () => {
    const { client, stub } = signedIn(() => json(200, { page_count: "", next_page: "x" }));
    expect(await client.publicListingsPage(0)).toEqual({ listings: [], pageCount: 1, nextPage: null });
    expect(stub.last.url.searchParams.get("page")).toBe("1");
  });

  it("stops when a page points back", async () => {
    const { client } = signedIn(() => json(200, { listings: [venue], page_count: 1, next_page: 1 }));
    expect(await client.publicListings()).toHaveLength(1);
  });

  it("reads one listing, null when it's gone", async () => {
    const { client, stub } = signedIn((request) => (request.path.endsWith("/gone") ? json(404, "") : json(200, event)));
    expect((await client.publicListing("event", "e 1"))?.title).toBe("Drag Brunch");
    expect(stub.last.path).toBe("/v1/public/events/e%201");
    expect(await client.publicListing("post", "gone")).toBeNull();
    await expect(client.publicListing("place" as "venue", "x")).rejects.toThrow(TypeError);
  });

  it("passes other failures through", async () => {
    const { client } = signedIn(() => json(403, ""));
    expect((await rejects(client.publicListing("venue", "v1"))).code).toBe("FORBIDDEN");
  });

  it("reads tonight at a venue", async () => {
    const { client, stub } = signedIn(() => json(200, { event: { name: "Karaoke" } }));
    expect(await client.publicTonight<{ event: { name: string } }>("v1")).toEqual({ event: { name: "Karaoke" } });
    expect(stub.last.path).toBe("/v1/public/venues/v1/tonight");
  });
});

describe("community", () => {
  it("reads every part, leaving out the ones the audience's modules don't have", async () => {
    const { client } = signedIn((request) => {
      const name = request.json().operationName;
      if (name === "People") return json(200, { errors: [{ message: "no", extensions: { code: "undefinedField" } }] });
      if (name === "SchemaFields") return data({});
      if (name === "Audience") return data({ id: AUDIENCE_ID, name: "Hot Mess", subdomain: "hotmess" });
      if (name === "Venues") return data({ venues: { list: { nodes: [{ id: "v1" }] } } });
      if (name === "Locales") return data({ locales: [{ id: "l1" }] });
      if (name === "Events") return data({ events: { list: { nodes: [{ id: "e1" }] } } });
      return data({ events: { series: { nodes: [] } } });
    });
    const community = await client.community();
    expect(community.audience?.name).toBe("Hot Mess");
    expect(community.venues.map((v) => v.id)).toEqual(["v1"]);
    expect(community.locales).toHaveLength(1);
    expect(community.events).toHaveLength(1);
    expect(community.people).toEqual([]);
    expect(community.eventSeries).toEqual([]);
  });

  it("passes other errors through", async () => {
    const { client } = signedIn(() => json(500, ""));
    expect((await rejects(client.community())).code).toBe("HTTP");
  });
});

describe("Soapbox", () => {
  const article = { id: "a1", slug: "news", title: "News", byline: "Ed", kind: "NEWS", pinned: false, edited: false, teaser: false, publication: { id: "p1", name: "Paper", trusted: true, acceptsOpEds: true } };

  it("reads articles, pages and one article", async () => {
    const { client, stub } = signedIn((request) => {
      const name = request.json().operationName;
      if (name === "Article") return data({ soapbox: { article: { ...article, body: "# Hi" } } });
      if (name === "ArticlesPage") return data({ soapbox: { articles: { nodes: [article, null], pageInfo: { endCursor: "c2", hasNextPage: true } } } });
      return data({ soapbox: { articles: { nodes: [article] } } });
    });
    expect(await client.articles({ localeId: "l1", first: 5 })).toHaveLength(1);
    expect(stub.last.variables).toEqual({ localeId: "l1", first: 5 });
    expect(await client.nationalArticles()).toHaveLength(1);
    expect(stub.last.json().variables).toBeUndefined();
    expect(await client.articlesPage({ after: "c1" })).toEqual({ articles: [article], endCursor: "c2", hasNextPage: true });
    expect(stub.last.variables).toEqual({ first: 20, after: "c1" });
    expect((await client.article("a1"))?.body).toBe("# Hi");
  });

  it("returns nothing for an audience without Soapbox", async () => {
    const { client } = signedIn(() => data({ id: AUDIENCE_ID }));
    expect(await client.articles()).toEqual([]);
    expect(await client.articlesPage()).toEqual({ articles: [], endCursor: null, hasNextPage: false });
    expect(await client.nationalArticles()).toEqual([]);
    expect(await client.article("a")).toBeNull();
    expect(await client.publications()).toEqual([]);
    expect(await client.publication("p")).toBeNull();
    expect(await client.myOpEds()).toEqual([]);
    expect(await client.articlesAbout("locale", "l1")).toEqual([]);
  });

  it("reads articles about a listing", async () => {
    const { client, stub } = signedIn((request) =>
      request.query.includes("venues {")
        ? data({ venues: { venue: { articles: { list: { nodes: [article] } } } } })
        : data({ people: { person: { articles: { list: { nodes: [article, article] } } } } }),
    );
    expect(await client.articlesAbout("venue", "v1", 3)).toHaveLength(1);
    expect(stub.last.variables).toEqual({ id: "v1", first: 3 });
    expect(await client.articlesAbout("person", "p1")).toHaveLength(2);
  });

  it("reads publications and op-eds, and sends one", async () => {
    const paper = { id: "p1", name: "Paper", trusted: true, acceptsOpEds: true, locale: { id: "L1", name: "Denver" } };
    const { client, stub } = signedIn((request) => {
      const name = request.json().operationName;
      if (name === "Publications") return data({ soapbox: { publications: [paper, { ...paper, id: "p2", locale: null }] } });
      if (name === "Publication") return data({ soapbox: { publication: paper } });
      if (name === "MyOpEds") return data({ soapbox: { myOpEds: [{ ...article, status: "SUBMITTED" }] } });
      return data({ submitOpEd: { article: { ...article, status: "SUBMITTED" } } });
    });
    expect((await client.localPublications("l1")).map((p) => p.id)).toEqual(["p1"]);
    expect((await client.publication("p1"))?.name).toBe("Paper");
    expect((await client.myOpEds())[0]?.status).toBe("SUBMITTED");
    expect((await client.submitOpEd({ publicationId: "p1", title: "T", body: "B" })).status).toBe("SUBMITTED");
    expect(stub.last.variables).toEqual({ publicationId: "p1", title: "T", body: "B", summary: null, byline: null });
  });
});

describe("calendar, moderation and the account", () => {
  const feed = { url: "https://api/v1/calendar/s.ics", webcalUrl: "webcal://api/v1/calendar/s.ics", googleUrl: "https://calendar.google.com/x", venues: [] };

  it("manages the calendar subscription", async () => {
    const { client, stub } = signedIn((request) => {
      const name = request.json().operationName;
      if (name === "CalendarFeed") return data({ me: { calendarFeed: null } });
      if (name === "CreateCalendarFeed") return data({ createCalendarFeed: { calendarFeed: feed } });
      if (name === "SetCalendarFeedVenue") return data({ setCalendarFeedVenue: { calendarFeed: { ...feed, venues: [{ id: "v1" }] } } });
      return data({ deleteCalendarFeed: { deleted: true } });
    });
    expect(await client.calendarFeed()).toBeNull();
    expect((await client.createCalendarFeed(true)).webcalUrl).toMatch(/^webcal:/);
    expect(stub.last.variables).toEqual({ reset: true });
    expect((await client.followVenueInCalendar("v1")).venues).toEqual([{ id: "v1" }]);
    expect(stub.last.variables).toEqual({ venueId: "v1", following: true });
    expect(await client.deleteCalendarFeed()).toBe(true);
  });

  it("reports, blocks and unblocks", async () => {
    const { client, stub } = signedIn((request) =>
      request.json().operationName !== "ReportContent"
        ? data({ blockUser: { blockedUsers: [] } })
        : request.variables.targetType === "MESSAGE"
          ? data({ reportContent: { reported: true, blocked: true } })
          : data({ reportContent: null }),
    );
    expect(await client.reportContent("MESSAGE", "m1", { reason: REPORT_REASONS[0], block: true })).toEqual({ reported: true, blocked: true });
    expect(stub.last.variables).toEqual({ targetType: "MESSAGE", targetId: "m1", reason: "Spam", block: true });
    expect(await client.reportContent("PERSON", "u1")).toEqual({ reported: false, blocked: false });
    await client.blockUser("u1");
    expect(stub.last.variables).toEqual({ userId: "u1" });
    await client.unblockUser("u1");
    expect(stub.last.json().operationName).toBe("UnblockUser");
    expect(REPORT_REASONS).toContain("Intimate image shared without consent");
  });

  it("deletes the account and signs out, or stays signed in", async () => {
    let deleted = false;
    const { client } = signedIn(() => data({ deleteAccount: { deleted } }));
    expect(await client.deleteAccount()).toBe(false);
    expect(await client.isSignedIn()).toBe(true);
    deleted = true;
    expect(await client.deleteAccount()).toBe(true);
    expect(await client.isSignedIn()).toBe(false);
  });
});
