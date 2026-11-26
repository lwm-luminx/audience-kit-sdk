import type { IncomingMessage, ServerResponse } from "node:http";
import { describe, expect, it } from "vitest";
import { AudienceKitClient, InMemoryTokenStore, coverPassCode, isCoverPassCode } from "../src/index.js";
import { cached, renderListing, renderPage } from "../examples/listings-site.js";
import { digest } from "../examples/news-digest.js";
import { BrowserTokenStore, clientFor, facebookLoginUrl, finishFacebookLogin, sessionFor } from "../examples/facebook-sign-in.js";
import { calendarLinks, doorPass, goingTo, reportHarassment } from "../examples/member-actions.js";
import { exportCommunity } from "../examples/community-export.js";
import { AUDIENCE_ID, BASE_URL, StubTransport, data, json, type RecordedRequest, type Reply } from "./stubTransport.js";

// The examples on developer.audiencekit.com, run against a stub API so they keep working as the SDK changes.

function client(respond: (request: RecordedRequest) => Reply, token: string | null = "session-token") {
  const stub = new StubTransport(respond);
  return {
    stub,
    client: new AudienceKitClient({
      configuration: { baseUrl: BASE_URL, audienceId: AUDIENCE_ID, host: "hotmess.social", facebookAppId: "123" },
      tokenStore: new InMemoryTokenStore(token, AUDIENCE_ID),
      transport: stub,
    }),
  };
}

const article = (id: string, extra: Record<string, unknown> = {}) => ({
  id,
  slug: id,
  title: `Story ${id}`,
  byline: "Sam",
  kind: "NEWS",
  pinned: false,
  edited: false,
  teaser: false,
  publication: { id: "p", name: "The Paper", trusted: true, acceptsOpEds: false },
  ...extra,
});

describe("listings-site", () => {
  it("renders the public listings, leaving out community ones", async () => {
    const { client: c } = client(() =>
      json(200, {
        listings: [
          { kind: "venue", id: "v", title: "Club <One>", address: "1 Main St", visibility: "public" },
          { kind: "event", id: "e", title: "Drag Brunch", start_at: "2026-12-06T18:00:00Z", venue_name: "Club One", is_canceled: true },
          { kind: "post", id: "p", title: "Hello", description: "World" },
          { kind: "event", id: "m", title: "Members only", visibility: "community" },
          { kind: "unknown", id: "x" },
        ],
        next_page: null,
      }),
    );
    const html = await renderPage(c);
    expect(html).toContain("<h2>Club &lt;One&gt;</h2><p>1 Main St</p>");
    expect(html).toContain("<time>Sun, Dec 6, 11:00 AM</time> at Club One <strong>Canceled</strong>");
    expect(html).toContain("<article><h3>Hello</h3><p>World</p></article>");
    expect(html).not.toContain("Members only");
    expect(renderListing({ kind: "event", id: "e", title: "Soon" })).toBe("<h3>Soon</h3><p><time></time> at </p>");
  });

  it("caches the page", async () => {
    let renders = 0;
    let clock = 0;
    const page = cached(async () => `page ${++renders}`, 300, () => clock);
    expect(await page()).toBe("page 1");
    clock = 299_000;
    expect(await page()).toBe("page 1");
    clock = 300_000;
    expect(await page()).toBe("page 2");
  });
});

describe("news-digest", () => {
  it("writes the locale's news, then national news it didn't already have", async () => {
    const { client: c } = client((request) => {
      const name = request.json().operationName;
      if (name === "Locales") return data({ locales: [{ id: "l1", name: "Denver" }, { id: "l2", name: "Boise" }] });
      if (name === "NationalArticles") return data({ soapbox: { articles: { nodes: [article("a1"), article("n1", { teaser: true, canonicalUrl: "https://paper/n1", disclosure: "Sponsored" })] } } });
      return data({ soapbox: { articles: { nodes: [article("a1", { summary: "What happened" })] } } });
    });
    const text = await digest(c, "Boise");
    expect(text).toContain("# Boise this week");
    expect(text).toContain("- **Story a1**, Sam for The Paper\n  What happened");
    expect(text).toContain("## Around the country\n\n- **Story n1**, Sam for The Paper ([read on The Paper](https://paper/n1))\n  _Sponsored_");
    expect(text.match(/Story a1/g)).toHaveLength(1);
  });

  it("is empty without locales or news", async () => {
    expect(await digest(client(() => data({ locales: [] })).client)).toBe("");
    const quiet = client((request) => (request.json().operationName === "Locales" ? data({ locales: [{ id: "l", name: "X" }] }) : data({ id: AUDIENCE_ID })));
    expect(await digest(quiet.client)).toBe("");
  });
});

describe("facebook-sign-in", () => {
  const fakeResponse = () => {
    const headers: Record<string, string> = {};
    return { headers, response: { setHeader: (name: string, value: string) => (headers[name] = value) } as unknown as ServerResponse };
  };

  it("gives each browser its own session", () => {
    const first = fakeResponse();
    const session = sessionFor({ headers: {} } as IncomingMessage, first.response);
    const cookie = first.headers["Set-Cookie"]!;
    expect(cookie).toMatch(/^sid=[a-f0-9]{32}; HttpOnly; Secure/);
    const again = fakeResponse();
    expect(sessionFor({ headers: { cookie: cookie.split(";")[0] } } as IncomingMessage, again.response)).toBe(session);
    expect(again.headers["Set-Cookie"]).toBeUndefined();
    expect(clientFor(session)).toBeInstanceOf(AudienceKitClient);
  });

  it("opens Facebook's dialog and trades the code it sends back", async () => {
    const session = { token: null, audienceId: null, state: null };
    const stub = new StubTransport((request) =>
      request.path === "/v1/branding"
        ? json(200, { audience: { id: AUDIENCE_ID, name: "Hot Mess", subdomain: "hotmess" }, facebook_login_config_id: "cfg" })
        : json(200, { token: "jwt", userId: "u-1", audienceId: AUDIENCE_ID, role: "member" }),
    );
    const c = new AudienceKitClient({
      configuration: { baseUrl: BASE_URL, host: "hotmess.social", facebookAppId: "123" },
      tokenStore: new BrowserTokenStore(session),
      transport: stub,
    });
    const login = new URL(await facebookLoginUrl(c, session, "https://example.com/auth/facebook"));
    expect(login.searchParams.get("config_id")).toBe("cfg");
    expect(login.searchParams.get("client_id")).toBe("123");
    const state = login.searchParams.get("state")!;

    const callback = new URL(`https://example.com/auth/facebook?code=fb-code&state=${state}`);
    expect(await finishFacebookLogin(c, session, callback, "https://example.com/auth/facebook", "web-1")).toBe("u-1");
    expect(stub.last.json()).toMatchObject({ code: "fb-code", redirect_uri: "https://example.com/auth/facebook", device: { identifier: "web-1", type: "web" } });
    expect(session.token).toBe("jwt");
    expect(session.audienceId).toBe(AUDIENCE_ID);
    await c.signOut();
    expect(session.token).toBeNull();
  });

  it("refuses a callback it didn't start, or one without a code", async () => {
    const session = { token: null, audienceId: null, state: "abc" as string | null };
    const { client: c } = client(() => json(500, ""));
    await expect(finishFacebookLogin(c, session, new URL("https://x/?state=xyz&code=c"), "https://x/", "d")).rejects.toThrow("didn't start here");
    session.state = "abc";
    await expect(finishFacebookLogin(c, session, new URL("https://x/?state=abc&error_description=Denied"), "https://x/", "d")).rejects.toThrow("Denied");
    session.state = "abc";
    await expect(finishFacebookLogin(c, session, new URL("https://x/?state=abc"), "https://x/", "d")).rejects.toThrow("didn't sign you in");
  });
});

describe("member-actions", () => {
  it("RSVPs, links calendars, shows the door pass and reports", async () => {
    const feed = { url: "u", webcalUrl: "webcal://f", googleUrl: "https://g", venues: [] };
    const pass = { id: "adm-1", status: "PAID", passSecret: "c2VjcmV0" };
    const { client: c, stub } = client((request) => {
      switch (request.json().operationName) {
        case "RSVPEvent":
          return data({ rsvpEvent: { event: { rsvp: { count: 12, mine: "ATTENDING" } } } });
        case "CreateCalendarFeed":
          return data({ createCalendarFeed: { calendarFeed: feed } });
        case "SetCalendarFeedVenue":
          return data({ setCalendarFeedVenue: { calendarFeed: feed } });
        case "VenueCover":
          return data({ venues: { venue: { id: request.variables.id, tickets: { cover: { viewerAdmission: request.variables.id === "v1" ? pass : null } } } } });
        default:
          return data({ reportContent: { reported: true, blocked: true } });
      }
    });
    expect(await goingTo(c, { id: "e1" } as never)).toBe(12);
    expect(await calendarLinks(c)).toEqual({ appleOrOutlook: "webcal://f", google: "https://g" });
    expect(await calendarLinks(c, "v1")).toEqual({ appleOrOutlook: "webcal://f", google: "https://g" });
    const shown = await doorPass(c, "v1", 1_000_000);
    expect(shown?.code).toBe(coverPassCode("adm-1", "c2VjcmV0", 1_000_000));
    expect(isCoverPassCode(shown!.code)).toBe(true);
    expect(shown?.refreshInSeconds).toBe(20);
    expect(await doorPass(c, "v2")).toBeNull();
    expect(await reportHarassment(c, "m1")).toEqual({ reported: true, blocked: true });
    expect(stub.last.variables).toMatchObject({ reason: "Harassment or hate", block: true });
  });
});

describe("community-export", () => {
  it("flattens the community for a static site", () => {
    const out = exportCommunity({
      audience: { id: AUDIENCE_ID, name: "Hot Mess", subdomain: "hotmess", theme: { preset: "hot_mess", light: [{ name: "accent", value: "#ff3366" }] } },
      locales: [{ id: "l1", name: "Denver" } as never],
      venues: [
        { id: "v1", name: "Club", hidden: false, locale: { name: "Denver" }, location: { id: "loc", point: "POINT (-104.99 39.74)" }, tags: [{ id: "t", name: "Dance" }] } as never,
        { id: "v2", name: "Hidden", hidden: true } as never,
      ],
      people: [],
      events: [{ id: "e1", name: "Brunch", startAt: "2026-12-06T18:00:00Z", venues: { venue: { id: "v1", name: "Club" } } } as never],
      eventSeries: [],
    });
    expect(out.accent).toBe("rgba(255, 51, 102, 1)");
    expect(out.venues).toEqual([{ id: "v1", name: "Club", locale: "Denver", point: { latitude: 39.74, longitude: -104.99 }, tags: ["Dance"] }]);
    expect(out.events[0]).toMatchObject({ id: "e1", name: "Brunch" });
    expect(exportCommunity({ audience: null, locales: [], venues: [{ id: "v", name: "V", hidden: false } as never], people: [], events: [], eventSeries: [] })).toMatchObject({
      accent: null,
      venues: [{ locale: null, point: null, tags: [] }],
    });
  });
});
