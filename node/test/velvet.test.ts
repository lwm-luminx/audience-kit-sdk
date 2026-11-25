import { readFileSync } from "node:fs";
import { buildSchema, parse, validate } from "graphql";
import { afterEach, describe, expect, it, vi } from "vitest";
import { Velvet } from "../src/index.js";

const {
  applyChatEvent,
  clock,
  emptyRoom,
  GraphQLCable,
  isTonightEvent,
  lineupName,
  realtimeUrl,
  safeWebUrl,
  serviceNight,
  tvBoard,
  tvLineup,
  venueJoinLink,
  VenueDeviceClient,
  VelvetHttpError,
  zoneOrDefault,
  zonedInstant,
} = Velvet;
type Json = Velvet.Json;

// The cases are the Google TV's (staff-kit VelvetCastTest.kt), so the Samsung TV draws the same board.
const venue: Json = {
  id: "v-1",
  name: "The Lookout",
  tickets: { cover: { timeZone: "America/Los_Angeles" } },
  upcomingEvents: {
    upcoming: {
      nodes: [
        { id: "e-1", name: "Drag Bingo", startAt: "2026-10-24T03:00:00Z", endAt: "2026-10-24T06:00:00Z" },
        { id: "e-2", name: "Canceled", isCanceled: true, startAt: "2026-10-24T03:00:00Z" },
        { id: "e-3", name: "Next week", startAt: "2026-10-31T03:00:00Z" },
      ],
    },
  },
};
const night: Json = {
  people: {
    runningOrder: {
      nodes: [
        { id: "a-1", kind: "ACT", role: "HOST", state: "DONE", startTiming: "HARD", startsAt: "2026-10-24T04:00:00Z",
          people: { nodes: [{ name: "Ada", avatarUrl: "https://img.example/ada.jpg" }] } },
        { id: "a-2", kind: "ACT", role: "SINGER", state: "ON", startTiming: "SOFT", startsAt: "2026-10-24T04:30:00Z",
          people: { nodes: [{ name: "Bo" }] }, songRequest: { title: "Dancing Queen" } },
        { id: "a-3", kind: "INTERMISSION", state: "UPCOMING", startTiming: "NONE" },
      ],
    },
  },
};
const now = new Date("2026-10-24T04:45:00Z");
const rows = (value: unknown) => value as Json[];

describe("Velvet board", () => {
  it("carries tonight with times in the venue's zone", () => {
    const board = tvBoard(venue, night, null, now);
    expect(board.type).toBe("tonight");
    expect(board.venue).toEqual({ id: "v-1", name: "The Lookout", timeZone: "America/Los_Angeles" });
    expect(board.events).toEqual(["Drag Bingo"]);
    const lineup = rows(board.lineup);
    expect(lineup.map((e) => e.name)).toEqual(["Ada", "Bo", "Intermission"]);
    expect(lineup.map((e) => e.time)).toEqual(["9 PM", "~9:30 PM", ""]);
    expect(lineup.map((e) => e.state)).toEqual(["done", "on", "upcoming"]);
    expect(lineup.map((e) => e.role)).toEqual(["Host", "Singing “Dancing Queen”", ""]);
    expect(lineup[0]!.images).toEqual(["https://img.example/ada.jpg"]);
    expect(board.chat).toBeUndefined();
    expect(board.join).toBe("https://hotmess.social/venues/v-1/chat");
  });

  it("shows the venue's photo, banner first", () => {
    const board = tvBoard({ ...venue, photoUrl: "https://img.example/p.jpg", bannerUrl: "javascript:alert(1)" }, null, null, now);
    expect((board.venue as Json).photo).toBe("https://img.example/p.jpg");
    expect(board.lineup).toEqual([]);
    expect((tvBoard({ id: "v-2" }, null, null, now).venue as Json).name).toBe("Tonight");
  });

  it("asks for slogan slides only when the venue has them on", () => {
    const settings = (on: boolean, adult: boolean): Json => ({ marqueeSlogans: on, adultVenue: adult });
    expect(tvBoard(venue, night, null, now).slogans).toBeUndefined();
    expect(tvBoard(venue, night, null, now, settings(false, true)).slogans).toBeUndefined();
    expect(tvBoard(venue, night, null, now, settings(true, false)).slogans).toEqual({ adult: false, slides: [] });
    expect((tvBoard(venue, night, null, now, settings(true, true)).slogans as Json).adult).toBe(true);
  });

  it("sends the venue's audience's posters less the ones it turned off", () => {
    const slogans: Json = {
      marqueeSlogans: true,
      adultVenue: false,
      marqueeHiddenSlogans: ["daddy-issues"],
      marqueePosters: [
        { id: "swipe-less", image: "https://hotmess.social/m/a.jpg", adult: false },
        { id: "daddy-issues", image: "https://hotmess.social/m/b.jpg", adult: false },
        { id: "cheeky", image: "https://hotmess.social/m/c.jpg", adult: true },
        { id: "broken", image: "not a link" },
      ],
    };
    expect((tvBoard(venue, night, null, now, slogans).slogans as Json).slides).toEqual([
      { id: "swipe-less", image: "https://hotmess.social/m/a.jpg", adult: false },
    ]);
  });

  it("keeps what's on and next before finished sets", () => {
    const order = [
      ...Array.from({ length: 10 }, (_, i) => ({ id: `d${i + 1}`, state: "DONE" })),
      ...Array.from({ length: 6 }, (_, i) => ({ id: `u${i + 1}`, state: "UPCOMING" })),
    ];
    expect(tvLineup(order).map((e) => e.id)).toEqual(["d9", "d10", "u1", "u2", "u3", "u4", "u5", "u6"]);
    expect(tvLineup(Array.from({ length: 9 }, (_, i) => ({ id: `u${i}` }))).length).toBe(8);
  });

  it("names lineup entries", () => {
    expect(lineupName({ title: " Drag Race " })).toBe("Drag Race");
    expect(lineupName({ people: { nodes: [{ name: "Ada" }, { name: "Bo" }] } })).toBe("Ada & Bo");
    expect(lineupName({ person: { name: "Cy" } })).toBe("Cy");
    expect(lineupName({})).toBe("Someone");
  });

  it("follows the chat feed", () => {
    const joined = applyChatEvent(emptyRoom, {
      __typename: "ChatJoined",
      history: [
        { message: { id: "m2", message: "Hi", name: "Sam", sentAt: "2026-10-24T04:02:00Z" } },
        { message: { id: "m1", message: "Welcome", postedAsVenue: true, sentAt: "2026-10-24T04:01:00Z" } },
        { message: { id: "m0", message: "Sam joined", automatic: true, sentAt: "2026-10-24T04:00:00Z" } },
      ],
      pinnedPost: { message: { id: "p1", title: "Two for one", message: "until 10" } },
    })!;
    expect(joined.messages.map((m) => m.id)).toEqual(["m1", "m2"]);
    let room = applyChatEvent(joined, { __typename: "ChatMessagePosted", message: { id: "m3", kind: "PHOTO", message: "" } })!;
    room = applyChatEvent(room, { __typename: "ChatMessagePosted", message: { id: "m4", automatic: true, message: "x" } })!;
    room = applyChatEvent(room, { __typename: "ChatMessageRemoved", messageId: "m2" })!;
    expect(room.messages.map((m) => m.id)).toEqual(["m1", "m3"]);

    const board = tvBoard(venue, night, room, now);
    const chat = board.chat as Json;
    expect(chat.pinned).toBe("Two for one");
    expect(rows(chat.messages).map((m) => m.sender)).toEqual(["The Lookout", "Guest"]);
    expect(rows(chat.messages).map((m) => m.text)).toEqual(["Welcome", "📷 Photo"]);
    expect(rows(chat.messages)[0]!.venue).toBe(true);

    room = applyChatEvent(room, { __typename: "ChatMessageUpdated", message: { id: "p1", title: "Three for one", message: "until 11" } })!;
    expect((tvBoard(venue, night, room, now).chat as Json).pinned).toBe("Three for one");
    room = applyChatEvent(room, { __typename: "ChatPinChanged", messageId: "p1", isPinned: false })!;
    expect(room.pinned).toBeNull();
    room = applyChatEvent(room, { __typename: "ChatPinChanged", isPinned: true, announcement: { id: "p2", message: "Hey" } })!;
    expect(room.pinned?.id).toBe("p2");
    expect(applyChatEvent(room, { __typename: "ChatRangeChanged" })).toBe(room);
    expect(applyChatEvent(room, { __typename: "ChatLeft", reason: "BANNED" })).toBeNull();
  });

  it("shows what guests see", () => {
    const joined = applyChatEvent(emptyRoom, {
      __typename: "ChatJoined",
      expiresBefore: "2026-10-24T03:00:00Z",
      history: [
        { message: { id: "old", message: "Last night", sentAt: "2026-10-23T22:00:00Z" } },
        { message: { id: "special", kind: "SPECIAL", title: "Happy hour", message: "Happy hour",
          endsAt: "2026-10-24T04:30:00.000Z", sentAt: "2026-10-24T03:30:00Z" } },
        { message: { id: "hi", message: "Hi", sentAt: "2026-10-24T04:10:00Z" } },
      ],
      pinnedPost: { message: { id: "p1", title: "Doors at 9", message: "Doors at 9", sentAt: "2026-10-20T01:00:00Z" } },
    })!;
    expect(joined.messages.map((m) => m.id)).toEqual(["special", "hi"]);
    expect(rows((tvBoard(venue, night, joined, now).chat as Json).messages).map((m) => m.text)).toEqual(["Hi"]);
    const expired = applyChatEvent(joined, { __typename: "ChatRoomCleared", clearedAt: "2026-10-24T03:30:00Z", expired: true })!;
    expect(expired.messages.map((m) => m.id)).toEqual(["hi"]);
    expect(expired.pinned?.id).toBe("p1");
    const cleared = applyChatEvent(expired, { __typename: "ChatRoomCleared", clearedAt: "2026-10-24T04:20:00Z", expired: false })!;
    expect(cleared.messages).toEqual([]);
    expect(cleared.pinned).toBeNull();
  });

  it("names the AI host and titles posts", () => {
    const room = applyChatEvent(emptyRoom, {
      __typename: "ChatJoined",
      history: [
        { message: { id: "g", kind: "ANNOUNCEMENT", postedAsVenue: true, title: "Glam (AI host)", body: "Welcome in", message: "Welcome in", sentAt: "1" } },
        { message: { id: "t", kind: "ANNOUNCEMENT", title: "Tonight", message: "Bingo at 9", name: "Kim", avatarUrl: "https://a.example/k.png", sentAt: "2" } },
        { message: { id: "p", kind: "PHOTO", message: "Look", photoUrl: "https://a.example/p.jpg", sentAt: "3" } },
      ],
    })!;
    const messages = rows((tvBoard({ id: "v" }, null, room, now).chat as Json).messages);
    expect(messages.map((m) => [m.sender, m.text])).toEqual([
      ["Glam", "Welcome in"],
      ["Kim", "Tonight: Bingo at 9"],
      ["Guest", "📷 Look"],
    ]);
    expect(messages[1]!.avatar).toBe("https://a.example/k.png");
    expect(messages[2]!.photo).toBe("https://a.example/p.jpg");
  });

  it("makes the venue's short link", () => {
    expect(venueJoinLink("3f2a9c1e-7b4d-4e8a-9c3b-1d2e3f4a5b6c")).toBe("https://hotmess.social/v/9Rn77sFM");
    expect(venueJoinLink("00000000-0000-0000-0000-000000000000")).toBe("https://hotmess.social/v/00000000");
    expect(venueJoinLink("ffffffff-ffff-ffff-ffff-ffffffffffff").replace("https://hotmess.social/v/", "")).toHaveLength(8);
  });
});

describe("Velvet time", () => {
  it("reads the venue's service night and clock", () => {
    expect(serviceNight("America/Denver", new Date("2026-11-25T10:00:00Z"))).toBe("2026-11-24");
    expect(serviceNight("America/Denver", new Date("2026-11-25T14:00:00Z"))).toBe("2026-11-25");
    expect(clock(new Date("2026-11-25T03:05:00Z"), "America/Denver")).toBe("8:05 PM");
    expect(clock(new Date("2026-11-25T07:00:00Z"), "America/Denver")).toBe("12 AM");
    expect(clock(new Date("2026-11-25T19:00:00Z"), "America/Denver")).toBe("12 PM");
    expect(zonedInstant(2026, 3, 8, 6, "America/Denver").toISOString()).toBe("2026-03-08T12:00:00.000Z");
    expect(zoneOrDefault("Not/AZone")).toBe(Intl.DateTimeFormat().resolvedOptions().timeZone);
    expect(zoneOrDefault("America/Denver")).toBe("America/Denver");
  });

  it("knows tonight's events", () => {
    const at = new Date("2026-10-24T04:45:00Z");
    expect(isTonightEvent({ startAt: "2026-10-24T03:00:00Z" }, "America/Los_Angeles", at)).toBe(true);
    expect(isTonightEvent({ startAt: "2026-10-23T03:00:00Z" }, "America/Los_Angeles", at)).toBe(false);
    expect(isTonightEvent({}, "America/Los_Angeles", at)).toBe(false);
    expect(safeWebUrl("ftp://x")).toBeNull();
  });
});

describe("Velvet GraphQL", () => {
  // A venue device signs in on the staff endpoint (/v1/audience/:id/staffql), so the staff view checks them.
  const schema = buildSchema(readFileSync(new URL("../../graphql/staff_schema.graphql", import.meta.url), "utf8"));
  for (const [name, document] of Object.entries(Velvet.Queries)) {
    it(`${name} is valid`, () => {
      expect(validate(schema, parse(document)).map((error) => error.message)).toEqual([]);
    });
  }
  it("knows the Samsung TV kind", () => {
    expect(schema.getType("VenueDisplayKind")?.toString()).toBe("VenueDisplayKind");
    expect(readFileSync(new URL("../../graphql/staff_schema.graphql", import.meta.url), "utf8")).toContain(Velvet.SAMSUNG_TV_KIND);
  });
});

class FakeSocket {
  static last: FakeSocket | null = null;
  readyState = 1;
  sent: Record<string, unknown>[] = [];
  onopen: ((event: unknown) => void) | null = null;
  onmessage: ((event: { data: unknown }) => void) | null = null;
  onclose: ((event: unknown) => void) | null = null;
  onerror: ((event: unknown) => void) | null = null;
  closed = false;
  constructor(readonly url: string, readonly protocols: string[]) {
    FakeSocket.last = this;
  }
  send(data: string) {
    this.sent.push(JSON.parse(data) as Record<string, unknown>);
  }
  close() {
    this.closed = true;
    this.onclose?.({});
  }
  receive(frame: unknown) {
    this.onmessage?.({ data: typeof frame === "string" ? frame : JSON.stringify(frame) });
  }
}

const factory = (url: string, protocols: string[]) => new FakeSocket(url, protocols);

describe("Velvet cable", () => {
  afterEach(() => vi.useRealTimers());

  it("subscribes after the welcome and delivers results", () => {
    vi.useFakeTimers();
    const cable = new GraphQLCable("wss://api.example/connection", () => "tok", "aud-1", factory);
    const results: unknown[] = [];
    const stop = cable.subscribe("subscription { x }", { id: "1" }, { onResult: (r) => results.push(r.event) });
    const socket = FakeSocket.last!;
    expect(socket.protocols).toEqual(["actioncable-v1-json", "jwt.tok"]);
    socket.receive({ type: "welcome" });
    const subscribe = socket.sent[0]!;
    expect(subscribe.command).toBe("subscribe");
    const identifier = JSON.parse(String(subscribe.identifier)) as Json;
    expect(identifier).toMatchObject({ channel: "GraphQLChannel", audience_id: "aud-1", endpoint: "staffql" });
    socket.receive({ type: "confirm_subscription", identifier: subscribe.identifier });
    expect(JSON.parse(String(socket.sent[1]!.data))).toMatchObject({ action: "execute", variables: { id: "1" } });
    socket.receive({ type: "ping", message: 1 });
    socket.receive({ identifier: subscribe.identifier, message: 3 });
    socket.receive("not json");
    socket.receive({ identifier: subscribe.identifier, message: { result: { data: { x: { a: 1 } } }, more: true } });
    expect(results).toEqual([{ a: 1 }]);

    // A dropped socket reconnects and subscribes again.
    socket.close();
    vi.advanceTimersByTime(1_000);
    const again = FakeSocket.last!;
    expect(again).not.toBe(socket);
    again.receive({ type: "welcome" });
    expect(again.sent[0]!.command).toBe("subscribe");

    // Silence closes it.
    vi.advanceTimersByTime(12_000);
    expect(again.closed).toBe(true);
    vi.advanceTimersByTime(2_000);
    const third = FakeSocket.last!;
    third.receive({ type: "welcome" });
    stop();
    expect(third.sent.at(-1)!.command).toBe("unsubscribe");
    expect(third.closed).toBe(true);
    stop();
  });

  it("tells a rejected operation and honors disconnects", () => {
    const cable = new GraphQLCable("wss://api.example/connection", () => "tok", "aud-1", factory, "graphql");
    const rejected = vi.fn();
    cable.subscribe("subscription { x }", {}, { onResult: () => undefined, onRejected: rejected });
    const socket = FakeSocket.last!;
    socket.receive({ type: "welcome" });
    const identifier = socket.sent[0]!.identifier;
    expect(JSON.parse(String(identifier)).endpoint).toBeUndefined();
    socket.receive({ type: "reject_subscription", identifier });
    expect(rejected).toHaveBeenCalled();
    socket.receive({ type: "disconnect" });
    expect(socket.closed).toBe(true);
    cable.close();
  });

  it("waits for a token", () => {
    const cable = new GraphQLCable("wss://api.example/connection", () => null, "aud-1", factory);
    FakeSocket.last = null;
    cable.subscribe("subscription { x }", {}, { onResult: () => undefined });
    expect(FakeSocket.last).toBeNull();
    expect(realtimeUrl("http://localhost:3000/")).toBe("ws://localhost:3000/connection");
    expect(realtimeUrl("https://api.audiencekit.com")).toBe("wss://api.audiencekit.com/connection");
  });
});

function memoryStorage() {
  const items = new Map<string, string>();
  return {
    items,
    getItem: (key: string) => items.get(key) ?? null,
    setItem: (key: string, value: string) => void items.set(key, value),
    removeItem: (key: string) => void items.delete(key),
  };
}

type Call = { url: string; method: string; headers: Record<string, string>; body?: string };

function stubFetch(answers: { status: number; body: unknown }[]) {
  const calls: Call[] = [];
  const fetch = async (url: string, init: { method: string; headers: Record<string, string>; body?: string }) => {
    calls.push({ url, ...init });
    const answer = answers.shift() ?? { status: 500, body: {} };
    return { status: answer.status, ok: answer.status < 300, json: async () => answer.body };
  };
  return { calls, fetch };
}

const signedIn = {
  token: "jwt-1",
  audienceId: "aud-1",
  endpoint: "https://api.example/v1/audience/aud-1/staffql",
  venue_device: { id: "d-1", venue_id: "v-1", venue_name: "The Lookout", permissions: ["screen"], audience: { id: "aud-1" } },
};

describe("Velvet venue device", () => {
  it("pairs by QR code, then reads GraphQL as the device", async () => {
    const storage = memoryStorage();
    const { calls, fetch } = stubFetch([
      { status: 201, body: { code: "ABCD-EFGH", url: "https://audiencekit.com/pair/ABCD-EFGH", poll_token: "poll", expires_at: "2026-11-25T07:00:00Z", interval: 3 } },
      { status: 202, body: { status: "pending" } },
      { status: 200, body: signedIn },
      { status: 200, body: { data: { venues: { venue: { id: "v-1" } } } } },
    ]);
    const client = new VenueDeviceClient({ baseUrl: "https://api.example/", storage, fetch, socket: factory });
    const pairing = await client.startPairing("duid-1", Velvet.TIZEN_PLATFORM);
    expect(pairing).toMatchObject({ code: "ABCD-EFGH", pollToken: "poll", interval: 3 });
    expect(JSON.parse(calls[0]!.body!)).toEqual({ identifier: "duid-1", platform: "tizen" });
    expect(await client.claimPairing(pairing)).toBeNull();
    const device = await client.claimPairing(pairing);
    expect(device).toEqual({ id: "d-1", venueId: "v-1", venueName: "The Lookout", permissions: ["screen"], audienceId: "aud-1" });
    expect(await client.graph(Velvet.Queries.venue, { id: "v-1" })).toEqual({ venues: { venue: { id: "v-1" } } });
    expect(calls[3]!.url).toBe("https://api.example/v1/audience/aud-1/staffql");
    expect(calls[3]!.headers.Authorization).toBe("Bearer jwt-1");

    // A new launch picks the sign-in up.
    const relaunched = new VenueDeviceClient({ baseUrl: "https://api.example", storage, fetch, socket: factory });
    expect(relaunched.device?.venueId).toBe("v-1");
    const stop = relaunched.subscribe("subscription { x }", {}, { onResult: () => undefined });
    expect(FakeSocket.last!.url).toBe("wss://api.example/connection");
    stop();
  });

  it("redeems a typed code and forgets a sign-in the API ended", async () => {
    const storage = memoryStorage();
    const ended = vi.fn();
    const { calls, fetch } = stubFetch([
      { status: 200, body: { ...signedIn, endpoint: undefined } },
      { status: 200, body: { errors: [{ message: "Nope" }] } },
      { status: 401, body: { error: { message: "Sign in first" } } },
    ]);
    const client = new VenueDeviceClient({ storage, fetch, onEnded: ended });
    await client.redeem(" CODE ", "duid");
    expect(calls[0]!.url).toBe("https://api.audiencekit.com/v1/venue-devices/redeem");
    await expect(client.graph("{ x }")).rejects.toThrow("Nope");
    expect(calls[1]!.url).toBe("https://api.audiencekit.com/v1/audience/aud-1/staffql");
    await expect(client.graph("{ x }")).rejects.toBeInstanceOf(VelvetHttpError);
    expect(ended).toHaveBeenCalledOnce();
    expect(client.device).toBeNull();
    expect(storage.items.size).toBe(0);
    await expect(client.graph("{ x }")).rejects.toThrow("isn't signed in");
    expect(client.subscribe("s", {}, { onResult: () => undefined })).toBeTypeOf("function");
  });

  it("reads the server's clock, refuses bad answers and signs out", async () => {
    const storage = memoryStorage();
    const { calls, fetch } = stubFetch([
      { status: 200, body: { api: { time: "2026-11-25T06:00:00Z" } } },
      { status: 200, body: {} },
      { status: 410, body: { status: "expired" } },
      { status: 200, body: { token: "t" } },
      { status: 200, body: signedIn },
      { status: 204, body: {} },
    ]);
    const client = new VenueDeviceClient({ storage, fetch });
    expect((await client.serverTime())?.toISOString()).toBe("2026-11-25T06:00:00.000Z");
    expect(await client.serverTime()).toBeNull();
    const pairing = { code: "", url: "", pollToken: "p", expiresAt: new Date(), interval: 3 };
    await expect(client.claimPairing(pairing)).rejects.toMatchObject({ status: 410 });
    await expect(client.redeem("x", "y")).rejects.toThrow("venue device session");
    await client.redeem("x", "y");
    await client.signOut();
    expect(calls.at(-1)!.method).toBe("DELETE");
    expect(client.device).toBeNull();
    storage.setItem("velvet.device", "{bad");
    expect(new VenueDeviceClient({ storage, fetch }).device).toBeNull();
  });
});
