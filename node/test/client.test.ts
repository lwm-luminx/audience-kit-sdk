import { describe, expect, it, vi } from "vitest";
import {
  AudienceKitClient,
  AudienceKitError,
  AudienceKitSDK,
  InMemoryTokenStore,
  type GraphQLOperationEvent,
  type SessionEvent,
  type TokenStore,
} from "../src/index.js";
import { AUDIENCE_ID, BASE_URL, StubTransport, data, failure, json, type RecordedRequest, type Reply } from "./stubTransport.js";

const device = { identifier: "device-1", model: "MacBookPro18,3", version: "2.0", build: "42" };
const credential = {
  token: "jwt-1",
  userId: "u-1",
  audienceId: AUDIENCE_ID,
  role: "member",
  endpoint: `${BASE_URL}/v1/audience/${AUDIENCE_ID}/graphql`,
  venueDeviceId: null,
  expiresAt: null,
};

function makeClient(
  respond: (request: RecordedRequest) => Reply,
  options: { host?: string | null; audienceId?: string | null; token?: string | null; storedAudienceId?: string | null; environment?: "production" | "staging"; monitor?: (event: GraphQLOperationEvent) => void; store?: TokenStore } = {},
) {
  const stub = new StubTransport(respond);
  const store = options.store ?? new InMemoryTokenStore(options.token === undefined ? "session-token" : options.token, options.storedAudienceId ?? null);
  const client = new AudienceKitClient({
    configuration: {
      baseUrl: `${BASE_URL}/`,
      host: options.host === undefined ? "hotmess.admin.audiencekit.com" : (options.host ?? undefined),
      audienceId: options.audienceId === undefined ? AUDIENCE_ID : (options.audienceId ?? undefined),
      facebookAppId: "842337999153841",
      environment: options.environment,
    },
    tokenStore: store,
    transport: stub,
    monitor: options.monitor,
  });
  return { client, stub, store };
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

describe("the SDK", () => {
  it("has a version", () => {
    expect(AudienceKitSDK.VERSION).toMatch(/^\d+\.\d+\.\d+$/);
  });
});

describe("sign-in", () => {
  it("exchanges the Facebook token and stores the session", async () => {
    const { client, stub, store } = makeClient(() => json(200, credential), { token: null });
    const events: SessionEvent[] = [];
    client.onSession((event) => events.push(event));

    const result = await client.signIn("fb-token", device);

    expect(result).toEqual(credential);
    expect(store.loadToken()).toBe("jwt-1");
    expect(store.loadAudienceId?.()).toBe(AUDIENCE_ID);
    expect(events).toEqual(["signedIn"]);
    expect(await client.isSignedIn()).toBe(true);
    const request = stub.last;
    expect(request.method).toBe("POST");
    expect(request.path).toBe("/v1/token");
    expect(request.header("Authorization")).toBeUndefined();
    expect(request.header("Content-Type")).toBe("application/json");
    expect(request.header("X-AudienceKit-Client")).toBe(`AudienceKit-Node/${AudienceKitSDK.VERSION}`);
    expect(request.header("X-AudienceKit-API-Version")).toBe(AudienceKitSDK.API_VERSION);
    expect(request.header("X-AudienceKit-Environment")).toBeUndefined();
    expect(request.json()).toEqual({
      facebook_token: "fb-token",
      host: "hotmess.admin.audiencekit.com",
      facebook_app_id: "842337999153841",
      device: { type: "node", ...device },
    });
  });

  it("sends the staging environment header", async () => {
    const { client, stub } = makeClient(() => json(200, credential), { token: null, environment: "staging" });
    await client.signIn("fb-token", device);
    expect(stub.last.header("X-AudienceKit-Environment")).toBe("staging");
  });

  it("exchanges a Facebook OAuth code", async () => {
    const { client, stub } = makeClient(() => json(200, credential), { token: null });
    await client.signInWithFacebookCode("code-1", "https://app.example/return", device, "123");
    expect(stub.last.json()).toMatchObject({ code: "code-1", redirect_uri: "https://app.example/return", facebook_app_id: "123" });
    expect(stub.last.json()).not.toHaveProperty("facebook_token");
  });

  it("signs in with Google, with the name and access token when given", async () => {
    const { client, stub } = makeClient(() => json(200, credential), { token: null });
    await client.signInWithGoogle("id-token", device, { name: "Aurora", accessToken: "access" });
    expect(stub.last.path).toBe("/v1/token/google");
    expect(stub.last.json()).toEqual({
      id_token: "id-token",
      access_token: "access",
      host: "hotmess.admin.audiencekit.com",
      device: { type: "node", ...device },
      name: "Aurora",
    });
  });

  it("connects Google to the signed-in account without ending the session on refusal", async () => {
    const { client, stub, store } = makeClient(() => json(400, { error: "google_taken", message: "That Google account signs in elsewhere." }));
    const error = await rejects(client.connectGoogle("id-token", device));
    expect(error.code).toBe("SIGN_IN_FAILED");
    expect(error.message).toBe("That Google account signs in elsewhere.");
    expect(stub.last.header("Authorization")).toBe("Bearer session-token");
    expect(stub.last.json()).toMatchObject({ connect: true });
    expect(store.loadToken()).toBe("session-token");
  });

  it("refuses to connect Google when signed out", async () => {
    const { client } = makeClient(() => json(200, credential), { token: null });
    expect((await rejects(client.connectGoogle("id-token", device))).code).toBe("NOT_SIGNED_IN");
  });

  it("signs in with Apple", async () => {
    const { client, stub } = makeClient(() => json(200, credential), { token: null });
    await client.signInWithApple({ identityToken: "apple-jwt", authorizationCode: "code", nonce: "n", firstName: "A", lastName: "B" }, device);
    expect(stub.last.path).toBe("/v1/token/apple");
    expect(stub.last.json()).toMatchObject({ identity_token: "apple-jwt", authorization_code: "code", nonce: "n", first_name: "A", last_name: "B" });
    expect(stub.last.json()).not.toHaveProperty("redirect_uri");
  });

  it("signs in with an App Review code, trimmed", async () => {
    const { client, stub } = makeClient(() => json(200, credential), { token: null });
    await client.signInWithReviewCode("  REVIEW-1 ", device);
    expect(stub.last.path).toBe("/v1/token/review");
    expect(stub.last.json()).toMatchObject({ code: "REVIEW-1" });
  });

  it("reports a refused sign-in with the API's reason", async () => {
    const { client } = makeClient(() => json(401, { error: "rejected", message: "Wrong app." }), { token: null });
    const error = await rejects(client.signIn("bad", device));
    expect(error.code).toBe("SIGN_IN_REJECTED");
    expect(error.message).toBe("Wrong app.");
    expect(await client.isSignedIn()).toBe(false);
  });

  it("reports a refused sign-in without a body", async () => {
    const { client } = makeClient(() => json(401, "not json"), { token: null });
    const error = await rejects(client.signIn("bad", device));
    expect(error.code).toBe("SIGN_IN_REJECTED");
    expect(error.faultMessage).toBeUndefined();
  });

  it("reports a failed sign-in", async () => {
    const { client } = makeClient(() => json(400, { error: "bad_request" }), { token: null });
    const error = await rejects(client.signIn("bad", device));
    expect(error.code).toBe("SIGN_IN_FAILED");
    expect(error.message).toBe("Sign-in failed.");
  });

  it("maps other statuses", async () => {
    const { client } = makeClient(() => json(503, ""), { token: null });
    const error = await rejects(client.signIn("fb", device));
    expect(error.code).toBe("HTTP");
    expect(error.status).toBe(503);
  });

  it("reports a sign-in response with no token as decoding", async () => {
    const { client } = makeClient(() => json(200, { userId: "u" }), { token: null });
    expect((await rejects(client.signIn("fb", device))).code).toBe("DECODING");
  });

  it("reports a store that can't save", async () => {
    const store: TokenStore = {
      loadToken: () => null,
      saveToken: () => {
        throw new Error("disk full");
      },
      deleteToken: () => {},
    };
    const { client } = makeClient(() => json(200, credential), { store });
    const error = await rejects(client.signIn("fb", device));
    expect(error.code).toBe("TOKEN_STORAGE");
    expect(error.message).toContain("disk full");
  });

  it("refreshes the session", async () => {
    const refreshed = { ...credential, token: "jwt-2" };
    const { client, stub, store } = makeClient(() => json(200, refreshed));
    expect(await client.refreshSession()).toEqual(refreshed);
    expect(stub.last.path).toBe("/v1/token/refresh");
    expect(stub.last.header("Authorization")).toBe("Bearer session-token");
    expect(store.loadToken()).toBe("jwt-2");
  });

  it("adopts a credential minted elsewhere", async () => {
    const { client, store } = makeClient(() => json(200, ""), { token: null, audienceId: null });
    const events: SessionEvent[] = [];
    client.onSession((event) => events.push(event));
    await client.adopt(credential);
    expect(store.loadToken()).toBe("jwt-1");
    expect(await client.audienceId()).toBe(AUDIENCE_ID);
    expect(events).toEqual(["signedIn"]);
  });

  it("signs out and stops listening", async () => {
    const { client, store } = makeClient(() => json(200, ""));
    const events: SessionEvent[] = [];
    const stop = client.onSession((event) => events.push(event));
    await client.signOut();
    expect(store.loadToken()).toBeNull();
    expect(events).toEqual(["signedOut"]);
    stop();
    await client.signOut();
    expect(events).toEqual(["signedOut"]);
    expect(await client.sessionToken()).toBeNull();
  });

  it("survives a store that can't delete", async () => {
    const store: TokenStore = {
      loadToken: () => "t",
      saveToken: () => {},
      deleteToken: () => {
        throw new Error("locked");
      },
    };
    const { client } = makeClient(() => json(401, ""), { store });
    await expect(client.signOut()).resolves.toBeUndefined();
    expect(await client.sessionRejected("t")).toBe(true);
  });
});

describe("the session", () => {
  it("ends once when the API refuses the token", async () => {
    const { client, store } = makeClient(() => json(401, ""));
    const events: SessionEvent[] = [];
    client.onSession((event) => events.push(event));

    const error = await rejects(client.me());
    expect(error.code).toBe("UNAUTHORIZED");
    expect(error.isUnauthenticated).toBe(true);
    expect(store.loadToken()).toBeNull();
    expect(events).toEqual(["sessionEnded"]);

    expect(await client.sessionRejected("session-token")).toBe(false);
    expect(events).toEqual(["sessionEnded"]);
  });

  it("doesn't end a newer sign-in for an older token", async () => {
    const { client } = makeClient(() => json(200, ""));
    expect(await client.sessionRejected("stale")).toBe(false);
  });

  it("needs a session for authenticated calls", async () => {
    const { client, stub } = makeClient(() => json(200, ""), { token: null });
    expect((await rejects(client.me())).code).toBe("NOT_SIGNED_IN");
    expect(stub.requests).toHaveLength(0);
  });

  it("reads the token lazily from a throwing store as signed out", async () => {
    const store: TokenStore = {
      loadToken: () => {
        throw new Error("keychain locked");
      },
      saveToken: () => {},
      deleteToken: () => {},
    };
    const { client } = makeClient(() => json(200, ""), { store });
    expect(await client.isSignedIn()).toBe(false);
  });
});

describe("branding and the audience", () => {
  const branding = { audience: { id: AUDIENCE_ID, name: "Hot Mess", subdomain: "hotmess" }, facebook_app_id: "1", theme: { preset: "hot_mess", light: { accent: "#b8236f" } } };

  it("fetches branding for the configured host without a token", async () => {
    const { client, stub } = makeClient(() => json(200, branding));
    expect(await client.branding()).toEqual(branding);
    expect(stub.last.path).toBe("/v1/branding");
    expect(stub.last.url.searchParams.get("host")).toBe("hotmess.admin.audiencekit.com");
    expect(stub.last.header("Authorization")).toBeUndefined();
  });

  it("fetches branding for another host", async () => {
    const { client, stub } = makeClient(() => json(200, branding));
    await client.branding("velvet.admin.audiencekit.com");
    expect(stub.last.url.searchParams.get("host")).toBe("velvet.admin.audiencekit.com");
  });

  it("needs a host for branding", async () => {
    const { client } = makeClient(() => json(200, branding), { host: null });
    expect((await rejects(client.branding())).code).toBe("MISSING_CONFIGURATION");
  });

  it("reports a missing host as not found", async () => {
    const { client } = makeClient(() => json(404, ""));
    expect((await rejects(client.branding())).code).toBe("NOT_FOUND");
  });

  it("reports branding without an audience as decoding", async () => {
    const { client } = makeClient(() => json(200, { theme: {} }));
    expect((await rejects(client.branding())).code).toBe("DECODING");
  });

  it("uses the configured audience id", async () => {
    const { client, stub } = makeClient(() => json(200, branding));
    expect(await client.audienceId()).toBe(AUDIENCE_ID);
    expect(stub.requests).toHaveLength(0);
  });

  it("takes the audience id from the token store", async () => {
    const { client, stub } = makeClient(() => json(200, branding), { audienceId: null, storedAudienceId: "stored" });
    expect(await client.audienceId()).toBe("stored");
    expect(stub.requests).toHaveLength(0);
  });

  it("looks the audience up from the host once", async () => {
    const { client, stub } = makeClient(() => json(200, branding), { audienceId: null });
    expect(await client.audienceId()).toBe(AUDIENCE_ID);
    expect(await client.audienceId()).toBe(AUDIENCE_ID);
    expect(stub.requests).toHaveLength(1);
  });

  it("skips a store whose audience id throws", async () => {
    const store: TokenStore = {
      loadToken: () => "t",
      saveToken: () => {},
      deleteToken: () => {},
      loadAudienceId: () => {
        throw new Error("nope");
      },
    };
    const { client } = makeClient(() => json(200, branding), { audienceId: null, store });
    expect(await client.audienceId()).toBe(AUDIENCE_ID);
  });

  it("needs an audience id or a host", async () => {
    const { client } = makeClient(() => json(200, branding), { audienceId: null, host: null });
    expect((await rejects(client.audienceId())).code).toBe("MISSING_CONFIGURATION");
  });

  it("resolves URLs the API sends", () => {
    const { client } = makeClient(() => json(200, ""));
    expect(client.url("/photos/1.jpg")).toBe(`${BASE_URL}/photos/1.jpg`);
    expect(client.url("https://cdn.example/a.png")).toBe("https://cdn.example/a.png");
    expect(client.url("")).toBeNull();
    expect(client.url(null)).toBeNull();
    expect(client.url("http://[bad")).toBeNull();
  });
});

describe("GraphQL", () => {
  it("posts to the audience's consumer endpoint with the operation headers", async () => {
    const { client, stub } = makeClient(() => data({ me: { self: { id: "u-1", name: "Aurora Borealis" } } }));
    expect(await client.me()).toEqual({ id: "u-1", name: "Aurora Borealis" });
    const request = stub.last;
    expect(request.path).toBe(`/v1/audience/${AUDIENCE_ID}/graphql`);
    expect(request.header("Authorization")).toBe("Bearer session-token");
    expect(request.header("X-APOLLO-OPERATION-TYPE")).toBe("query");
    expect(request.header("X-APOLLO-OPERATION-NAME")).toBe("Me");
    expect(request.json()).toEqual({ query: expect.stringContaining("query Me"), operationName: "Me" });
  });

  it("returns null for me when there's no current user", async () => {
    const { client } = makeClient(() => data({ me: null }));
    expect(await client.me()).toBeNull();
  });

  it("throws the errors even alongside data", async () => {
    const errors = [{ message: "Nope", path: ["rsvpEvent"], extensions: { code: "FORBIDDEN", reason: "banned" } }];
    const { client } = makeClient(() => json(200, { errors, data: { rsvpEvent: null } }));
    const error = await rejects(client.rsvp("e-1"));
    expect(error.code).toBe("GRAPHQL");
    expect(error.errors).toEqual(errors);
    expect(error.message).toBe("Nope");
    expect(error.isUndefinedField).toBe(false);
  });

  it("reports a response with no data", async () => {
    const { client } = makeClient(() => json(200, { data: null }));
    expect((await rejects(client.me())).code).toBe("DECODING");
  });

  it("reports a body that isn't JSON", async () => {
    const { client } = makeClient(() => json(200, "<html>"));
    expect((await rejects(client.me())).code).toBe("DECODING");
  });

  it("reports a body that isn't an envelope", async () => {
    const { client } = makeClient(() => json(200, "42"));
    expect((await rejects(client.me())).code).toBe("DECODING");
  });

  it("reports a network failure", async () => {
    const { client } = makeClient(() => failure(new TypeError("fetch failed")));
    const error = await rejects(client.me());
    expect(error.code).toBe("NETWORK");
    expect(error.message).toBe("fetch failed");
    expect(error.cause).toBeInstanceOf(TypeError);
  });

  it("maps 403 and 404", async () => {
    let status = 403;
    const { client } = makeClient(() => json(status, ""));
    expect((await rejects(client.me())).code).toBe("FORBIDDEN");
    status = 404;
    expect((await rejects(client.me())).code).toBe("NOT_FOUND");
  });

  it("runs an app's own operation and tells the monitor", async () => {
    const events: GraphQLOperationEvent[] = [];
    const { client } = makeClient(() => data({ custom: 1 }), { monitor: (event) => events.push(event) });
    expect(await client.graphQL<{ custom: number }>("mutation Custom($x: Int) { custom(x: $x) }", { variables: { x: 1 } })).toEqual({ custom: 1 });
    expect(events).toEqual([{ name: "Custom", type: "mutation", endpoint: { segment: "graphql" }, durationMillis: expect.any(Number) }]);
  });

  it("tells the monitor about failures, with the operation name passed", async () => {
    const events: GraphQLOperationEvent[] = [];
    const { client } = makeClient(() => json(500, ""), { monitor: (event) => events.push(event) });
    await rejects(client.graphQL("{ me { id } }", { operationName: "Anon" }));
    expect(events[0]).toMatchObject({ name: "Anon", type: "query", error: "The server responded with status 500." });
  });

  it("goes to another endpoint when asked", async () => {
    const { client, stub } = makeClient(() => data({ ok: true }));
    await client.graphQL("{ ok }", { endpoint: { segment: "staffql" } });
    expect(stub.last.path).toBe(`/v1/audience/${AUDIENCE_ID}/staffql`);
  });
});

describe("the audience's modules", () => {
  const venue = { id: "v-1", name: "Oasis", hidden: false, order: 1, locale: { id: "l-1", name: "SF" }, location: { id: "loc", point: "POINT (-122.4 37.8)" }, tags: [] };

  function moduleless(known: Record<string, string[]>) {
    return (request: RecordedRequest): Reply => {
      const query = request.query;
      if (query.includes("SchemaFields")) {
        const names = [...query.matchAll(/t(\d+): __type\(name: "(\w+)"\)/g)];
        const result: Record<string, unknown> = {};
        for (const [, index, name] of names) {
          result[`t${index}`] = name! in known ? { fields: known[name!]!.map((n) => ({ name: n })) } : null;
        }
        return data(result);
      }
      if (/profile|places/.test(query)) {
        return json(200, { errors: [{ message: "Field 'profile' doesn't exist on type 'Venue'", extensions: { code: "undefinedField", typeName: "Venue", fieldName: "profile" } }] });
      }
      return data({ venues: { list: { nodes: [venue] } }, people: { list: { nodes: [] } }, locales: [{ id: "l-1" }], closestLocale: null });
    };
  }

  const known = { Venue: ["id", "name", "locale", "location", "tags"], Locale: ["id", "name"], Location: ["id", "point"], Person: ["id"], Event: ["id"] };

  it("asks the schema which fields exist and retries without the rest", async () => {
    const { client, stub } = makeClient(moduleless(known));
    expect(await client.venues()).toEqual([venue]);
    expect(stub.requests.map((r) => r.header("X-APOLLO-OPERATION-NAME"))).toEqual(["Venues", "SchemaFields", "Venues"]);
    expect(stub.last.query).not.toContain("profile");
    expect(stub.last.query).not.toContain("placeId");

    // Later operations go straight to the right document.
    expect(await client.locales()).toEqual([{ id: "l-1" }]);
    expect(stub.requests).toHaveLength(4);
    expect(stub.last.query).not.toContain("profile");
    expect(await client.people()).toEqual([]);
    expect(await client.closestLocale({ latitude: 1, longitude: 2 })).toBeNull();
    expect(stub.requests).toHaveLength(6);
    expect(stub.last.variables).toEqual({ near: { latitude: 1, longitude: 2 } });
  });

  it("forgets the schema on sign-out", async () => {
    const { client, stub, store } = makeClient(moduleless(known));
    await client.venues();
    await client.signOut();
    store.saveToken("again");
    await client.venues();
    expect(stub.requests.map((r) => r.header("X-APOLLO-OPERATION-NAME"))).toEqual(["Venues", "SchemaFields", "Venues", "Venues", "SchemaFields", "Venues"]);
  });

  it("makes one call for an audience with every module", async () => {
    const { client, stub } = makeClient(() => data({ venues: { list: { nodes: [venue] } } }));
    await client.venues();
    expect(stub.requests).toHaveLength(1);
    expect(stub.last.query).toContain("facebook { page");
  });

  it("passes other GraphQL errors through", async () => {
    const { client, stub } = makeClient(() => json(200, { errors: [{ message: "Rate limited", extensions: { code: "RATE_LIMITED" } }] }));
    expect((await rejects(client.venues())).code).toBe("GRAPHQL");
    expect(stub.requests).toHaveLength(1);
  });

  it("exposes schemaFields, asking about each type once", async () => {
    const { client, stub } = makeClient(moduleless(known));
    const fields = await client.schemaFields(["Venue", "Missing", "Venue"]);
    expect(fields).toEqual({ Venue: new Set(known.Venue) });
    expect(stub.last.query).toBe('query SchemaFields { t0: __type(name: "Missing") { fields(includeDeprecated: true) { name } } t1: __type(name: "Venue") { fields(includeDeprecated: true) { name } } }');
    await client.schemaFields(["Venue"]);
    expect(stub.requests).toHaveLength(1);
  });
});

describe("the typed helpers", () => {
  it("reads the audience", async () => {
    const audience = { id: AUDIENCE_ID, name: "Hot Mess", subdomain: "hotmess", theme: { preset: "hot_mess", light: [], dark: [] } };
    const { client } = makeClient(() => data(audience));
    expect(await client.audience()).toEqual(audience);
  });

  it("reads venues, people and locales when the lists are missing", async () => {
    const { client } = makeClient(() => data({}));
    expect(await client.venues()).toEqual([]);
    expect(await client.people()).toEqual([]);
    expect(await client.locales()).toEqual([]);
  });

  it("looks a node up", async () => {
    const { client, stub } = makeClient(() => data({ node: { __typename: "Venue", id: "v-1" } }));
    expect(await client.node("v-1")).toEqual({ __typename: "Venue", id: "v-1" });
    expect(stub.last.variables).toEqual({ id: "v-1" });
    const { client: none } = makeClient(() => data({ node: null }));
    expect(await none.node("x")).toBeNull();
  });

  it("reports the location with beacon values", async () => {
    const { client, stub } = makeClient(() => data({ reportLocation: { venue: { id: "v-1" } } }));
    expect(await client.reportLocation({ latitude: 37.8, longitude: -122.4, beaconMajor: 7, beaconMinor: 0 }, "venue { id }")).toEqual({ venue: { id: "v-1" } });
    expect(stub.last.variables).toEqual({ position: { latitude: 37.8, longitude: -122.4, beaconMajor: 7 } });
    expect(stub.last.query).toContain("reportLocation(input: { position: $position }) { venue { id } }");
  });

  it("sets, cancels and reads RSVPs", async () => {
    const rsvp = { count: 3, mine: "ATTENDING", mineSource: "RSVP" };
    const { client, stub } = makeClient((request) => {
      if (request.query.includes("CancelRSVP")) return data({ cancelRsvp: { event: { id: "e", rsvp: { count: 2, mine: "UNSURE" } } } });
      if (request.query.includes("EventRSVP")) {
        return data({ events: { event: { id: "e", rsvp: { ...rsvp, counts: { going: 3, interested: 1, tickets: 0 }, attendees: { nodes: [{ profile: { id: "u", name: "A B." }, friend: false, source: "RSVP" }, null] } } } } });
      }
      return data({ rsvpEvent: { event: { id: "e", rsvp } } });
    });
    expect(await client.rsvp("e")).toEqual({ ...rsvp, counts: null, attendees: [] });
    expect(stub.last.variables).toEqual({ eventId: "e", state: "ATTENDING" });
    await client.rsvp("e", "MAYBE");
    expect(stub.last.variables).toEqual({ eventId: "e", state: "MAYBE" });
    expect(await client.cancelRSVP("e")).toEqual({ count: 2, mine: "UNSURE", mineSource: null, counts: null, attendees: [] });
    expect(await client.eventRSVP("e", 10)).toEqual({ ...rsvp, counts: { going: 3, interested: 1, tickets: 0 }, attendees: [{ profile: { id: "u", name: "A B." }, friend: false, source: "RSVP" }] });
    expect(stub.last.variables).toEqual({ id: "e", first: 10 });
  });

  it("returns null RSVPs for a missing event", async () => {
    const { client } = makeClient(() => data({ events: { event: null } }));
    expect(await client.eventRSVP("missing")).toBeNull();
  });

  it("reads and changes tribes", async () => {
    const tag = { id: "t", name: "Bears", color: null, tribe: true };
    const { client, stub } = makeClient((request) => {
      if (request.query.includes("IdentifyWithTribe")) return data({ identifyWithTribe: { tribes: [{ tag, isPrivate: false }] } });
      if (request.query.includes("LeaveTribe")) return data({ leaveTribe: { tribes: [] } });
      return data({ id: AUDIENCE_ID, tribes: [tag], me: { self: { id: "u", tribes: [{ tag, isPrivate: true }] } } });
    });
    expect(await client.tribes()).toEqual({ available: [tag], mine: [{ tag, isPrivate: true }] });
    expect(await client.identifyWithTribe("t", false)).toEqual([{ tag, isPrivate: false }]);
    expect(stub.last.variables).toEqual({ tagId: "t", isPrivate: false });
    expect(await client.leaveTribe("t")).toEqual([]);
  });

  it("reads tribes signed out", async () => {
    const { client } = makeClient(() => data({ id: AUDIENCE_ID, tribes: null, me: null }));
    expect(await client.tribes()).toEqual({ available: [], mine: [] });
  });

  it("registers a device", async () => {
    const { client, stub } = makeClient(() => data({ registerDevice: { registered: true } }));
    await client.registerDevice("fcm-1");
    expect(stub.last.variables).toEqual({ notificationToken: "fcm-1" });
  });
});

describe("cover", () => {
  const admission = { id: "a-1", status: "PENDING", night: "2026-11-06", passSecret: "c2VjcmV0" };
  const purchase = { admission, provider: "STRIPE", paymentIntentClientSecret: "pi_secret", publishableKey: "pk", stripeAccountId: "acct" };

  it("reads a venue's cover and the viewer's passes", async () => {
    const cover = { id: "v-1", name: "Oasis", tickets: { cover: { charge: { amount: { cents: 1000, currency: "usd" }, total: { cents: 1150, currency: "usd" }, night: "2026-11-06", payable: true }, viewerAdmission: null, viewerCoatCheck: null } } };
    const { client, stub } = makeClient(() => data({ venues: { venue: cover } }));
    expect(await client.venueCover("v-1")).toEqual(cover);
    expect(stub.last.variables).toEqual({ id: "v-1" });
    const { client: none } = makeClient(() => data({ venues: { venue: null } }));
    expect(await none.venueCover("x")).toBeNull();
  });

  it("buys, pays, confirms and refunds", async () => {
    const { client, stub } = makeClient((request) => {
      const name = request.header("X-APOLLO-OPERATION-NAME");
      if (name === "BuyCover") return data({ buyCover: purchase });
      if (name === "BuyCoatCheck") return data({ buyCoatCheck: { ...purchase, admission: { ...admission, kind: "COAT_CHECK", quantity: 2 } } });
      if (name === "PayCover") return data({ payCover: { admission: { ...admission, status: "PAID" } } });
      if (name === "ConfirmCover") return data({ confirmCover: { admission: { ...admission, status: "PAID" } } });
      if (name === "RefundAdmission") return data({ refundAdmission: { admission: { ...admission, status: "REFUNDED" } } });
      return data({ me: { cover: { admissions: { nodes: [admission] } } } });
    });
    expect(await client.buyCover("v-1")).toEqual(purchase);
    expect(stub.last.variables).toEqual({ venueId: "v-1" });
    expect((await client.buyCoatCheck("v-1", 2)).admission.quantity).toBe(2);
    expect(stub.last.variables).toEqual({ venueId: "v-1", quantity: 2 });
    expect((await client.payCover("a-1", "cnon:1")).status).toBe("PAID");
    expect(stub.last.variables).toEqual({ admissionId: "a-1", sourceId: "cnon:1", verificationToken: null });
    expect((await client.payCover("a-1", "cnon:1", "verf")).status).toBe("PAID");
    expect(stub.last.variables).toEqual({ admissionId: "a-1", sourceId: "cnon:1", verificationToken: "verf" });
    expect((await client.confirmCover("a-1")).status).toBe("PAID");
    expect((await client.refundAdmission("a-1")).status).toBe("REFUNDED");
    expect(await client.admissions()).toEqual([admission]);
  });

  it("reads no admissions signed out", async () => {
    const { client } = makeClient(() => data({ me: null }));
    expect(await client.admissions()).toEqual([]);
  });
});

describe("events", () => {
  const event = { id: "e-1", name: "Night", venue: { name: "Oasis", venue: { id: "v-1", location: { id: "l", point: "POINT (-122.4 37.8)" } } }, rsvp: { mine: "UNSURE", count: 0 }, tickets: { url: null, offers: { nodes: [] } } };

  it("lists events with the defaults", async () => {
    const { client, stub } = makeClient(() => data({ events: { list: { nodes: [event, null] } } }));
    expect(await client.events()).toEqual([event]);
    expect(stub.last.variables).toEqual({ window: "UPCOMING", localeId: null, venueId: null, first: 100 });
    expect(stub.last.query).toContain("rsvp { mine count }");
    expect(stub.last.query).toContain("cover { charge");
  });

  it("lists past events at a venue", async () => {
    const { client, stub } = makeClient(() => data({ events: { list: null } }));
    expect(await client.events({ window: "PAST", venueId: "v-1", localeId: "l-1", first: 5 })).toEqual([]);
    expect(stub.last.variables).toEqual({ window: "PAST", localeId: "l-1", venueId: "v-1", first: 5 });
  });

  it("reads one event", async () => {
    const { client, stub } = makeClient(() => data({ events: { event } }));
    expect(await client.event("e-1")).toEqual(event);
    expect(stub.last.variables).toEqual({ id: "e-1" });
    const { client: none } = makeClient(() => data({ events: null }));
    expect(await none.event("x")).toBeNull();
  });

  it("lists series", async () => {
    const series = { id: "s-1", name: "Tuesdays", startsOn: "2026-01-06", startTime: "21:00", timeZone: "America/Los_Angeles" };
    const { client, stub } = makeClient(() => data({ events: { series: { nodes: [series] } } }));
    expect(await client.eventSeries({ localeId: "l-1" })).toEqual([series]);
    expect(stub.last.variables).toEqual({ localeId: "l-1", venueId: null, first: 100 });
    const { client: none } = makeClient(() => data({ events: {} }));
    expect(await none.eventSeries()).toEqual([]);
  });

  it("lists a venue's offers tonight and on a night", async () => {
    const offer = { price: { cents: 2000, currency: "usd" }, url: "https://tickets.example", seller: { key: "eventbrite", name: "Eventbrite" } };
    const { client, stub } = makeClient(() => data({ venues: { venue: { id: "v-1", tickets: { offers: { nodes: [offer] } } } } }));
    expect(await client.venueOffers("v-1")).toEqual([offer]);
    expect(stub.last.variables).toEqual({ id: "v-1", night: null });
    expect(stub.last.query).toContain("$night: ISO8601Date");
    await client.venueOffers("v-1", "2026-12-31");
    expect(stub.last.variables).toEqual({ id: "v-1", night: "2026-12-31" });
    const { client: none } = makeClient(() => data({ venues: { venue: { id: "v-1" } } }));
    expect(await none.venueOffers("v-1")).toEqual([]);
  });

  it("leaves offers out without the Ticketing module", async () => {
    const { client, stub } = makeClient((request) => {
      if (request.query.includes("SchemaFields")) return data({ t0: { fields: [{ name: "id" }] }, t1: null });
      if (request.query.includes("offers")) return json(200, { errors: [{ message: "undefined", extensions: { code: "undefinedField" } }] });
      return data({ venues: { venue: { id: "v-1" } } });
    });
    expect(await client.venueOffers("v-1")).toEqual([]);
    expect(stub.last.query).not.toContain("$night");
  });
});

describe("venue pages and chat", () => {
  const message = { id: "m-1", body: "hi", message: "hi", name: "Aurora B.", kind: "TEXT", pinned: false };

  it("reads a venue's page", async () => {
    const raw = {
      id: "v-1", name: "Oasis", hidden: false, order: 1, locale: { id: "l-1" }, tags: [],
      profile: { facebook: { page: { id: "p", name: "Oasis SF" } }, address: "298 11th St", phone: "+1", website: "https://oasis.example", socialLinks: { nodes: [{ id: "s", handle: "oasis", provider: "INSTAGRAM", url: null }] } },
      description: "A bar.",
      chat: { open: true, recentMessages: { nodes: [message] } },
      events: { upcoming: { nodes: [{ id: "e-1" }] } },
    };
    const { client, stub } = makeClient(() => data({ venues: { venue: raw } }));
    const detail = await client.venueDetail("v-1", 5);
    expect(stub.last.variables).toEqual({ id: "v-1", recentMessages: 5 });
    expect(detail).toEqual({
      venue: { id: "v-1", name: "Oasis", hidden: false, order: 1, locale: { id: "l-1" }, tags: [], profile: raw.profile },
      description: "A bar.",
      address: "298 11th St",
      phone: "+1",
      website: "https://oasis.example",
      socialLinks: [{ id: "s", handle: "oasis", provider: "INSTAGRAM", url: null }],
      chatOpen: true,
      recentMessages: [message],
      upcomingEvents: [{ id: "e-1" }],
    });
  });

  it("leaves module parts null on a venue without them", async () => {
    const { client } = makeClient(() => data({ venues: { venue: { id: "v-1", hidden: false, order: 1, locale: { id: "l" } } } }));
    const detail = await client.venueDetail("v-1");
    expect(detail).toMatchObject({ description: null, address: null, socialLinks: null, chatOpen: null, recentMessages: null, upcomingEvents: null });
    expect(detail?.venue.profile).toBeNull();
  });

  it("returns null for a missing venue", async () => {
    const { client } = makeClient(() => data({ venues: { venue: null } }));
    expect(await client.venueDetail("x")).toBeNull();
  });

  it("sends and removes chat messages", async () => {
    const { client, stub } = makeClient((request) =>
      request.query.includes("Remove") ? data({ removeMyChatMessage: { deletedId: "m-1" } }) : data({ sendMyChatMessage: { message } }),
    );
    expect(await client.sendChatMessage("hi", { kind: "venue", id: "v-1" })).toEqual(message);
    expect(stub.last.variables).toEqual({ input: { venueId: "v-1", message: "hi" } });
    await client.sendChatMessage("hi", { kind: "locale", id: "l-1" }, "prompt-1");
    expect(stub.last.variables).toEqual({ input: { localeId: "l-1", message: "hi", promptId: "prompt-1" } });
    await client.removeChatMessage("m-1");
    expect(stub.last.variables).toEqual({ messageId: "m-1" });
  });
});

describe("REST", () => {
  it("builds query strings and passes extra headers", async () => {
    const { client, stub } = makeClient(() => json(200, "ok"));
    expect(await client.data({ path: "v1/things", query: { a: "x y", flag: null, skipped: undefined }, headers: { "X-Extra": "1" }, authenticated: false })).toBe("ok");
    expect(stub.last.url.toString()).toBe(`${BASE_URL}/v1/things?a=x%20y&flag`);
    expect(stub.last.header("X-Extra")).toBe("1");
    expect(stub.last.header("Authorization")).toBeUndefined();
    expect(stub.last.body).toBeNull();
  });

  it("doesn't end the session on a 401 without a token", async () => {
    const { client } = makeClient(() => json(401, ""));
    const events: SessionEvent[] = [];
    client.onSession((event) => events.push(event));
    expect((await rejects(client.data({ path: "/v1/x", authenticated: false }))).code).toBe("UNAUTHORIZED");
    expect(events).toEqual([]);
  });

  it("passes the abort signal to the transport", async () => {
    const controller = new AbortController();
    const transport = { execute: vi.fn(async (request: { signal?: AbortSignal }) => ({ status: 200, body: JSON.stringify({ data: { me: null } }) })) };
    const client = new AudienceKitClient({ configuration: { audienceId: AUDIENCE_ID }, tokenStore: new InMemoryTokenStore("t"), transport });
    await client.graphQL("{ me { id } }", { signal: controller.signal });
    expect(transport.execute.mock.calls[0]![0].signal).toBe(controller.signal);
  });
});
