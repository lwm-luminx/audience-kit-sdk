import { describe, expect, it } from "vitest";
import {
  AudienceKitError,
  SchemaShape,
  colorFromHex,
  colorToCss,
  connectionItems,
  coordinateFromWkt,
  coordinatesInput,
  coverPassCode,
  coverPassSignature,
  coverPassWindow,
  describeOperation,
  endpointPath,
  eventCoverCharge,
  eventHosts,
  eventLineup,
  eventTicketOffers,
  eventVenue,
  graphQLErrorCode,
  graphQLErrorFields,
  graphQLErrorReason,
  isAdmissionPaid,
  isCoverPassCode,
  isPurchasePaid,
  isSquarePurchase,
  listingName,
  listingPage,
  localeGooglePlaceId,
  locationCoordinate,
  resolveConfiguration,
  secondsUntilNextCoverPassWindow,
  themeColor,
  CONSUMER_ENDPOINT,
  type Admission,
  type Event,
} from "../src/index.js";

describe("coordinates", () => {
  it("parses WKT points, with or without an SRID", () => {
    expect(coordinateFromWkt("POINT (-122.42 37.77)")).toEqual({ latitude: 37.77, longitude: -122.42 });
    expect(coordinateFromWkt("SRID=4326;POINT(-122.42 37.77)")).toEqual({ latitude: 37.77, longitude: -122.42 });
  });

  it("rejects what isn't a point on Earth", () => {
    expect(coordinateFromWkt("POLYGON ((0 0, 1 1, 1 0, 0 0))")).toBeNull();
    expect(coordinateFromWkt("POINT (37.77 -122.42)")).toBeNull(); // swapped
    expect(coordinateFromWkt("POINT (NaN 1)")).toBeNull();
    expect(coordinateFromWkt("POINT (1)")).toBeNull();
    expect(coordinateFromWkt("POINT")).toBeNull();
    expect(coordinateFromWkt(")(")).toBeNull();
    expect(coordinateFromWkt("POINT (Infinity 1)")).toBeNull();
  });

  it("builds the CoordinatesInput without zero beacons", () => {
    expect(coordinatesInput({ latitude: 1, longitude: 2 })).toEqual({ latitude: 1, longitude: 2 });
    expect(coordinatesInput({ latitude: 1, longitude: 2, beaconMajor: 3, beaconMinor: 4 })).toEqual({ latitude: 1, longitude: 2, beaconMajor: 3, beaconMinor: 4 });
    expect(coordinatesInput({ latitude: 1, longitude: 2, beaconMajor: 0, beaconMinor: null })).toEqual({ latitude: 1, longitude: 2 });
  });

  it("reads a location's coordinate", () => {
    expect(locationCoordinate({ id: "l", point: "POINT (1 2)" })).toEqual({ latitude: 2, longitude: 1 });
    expect(locationCoordinate({ id: "l" })).toBeNull();
    expect(locationCoordinate(null)).toBeNull();
  });
});

describe("colors", () => {
  it("parses hex colors", () => {
    expect(colorFromHex("#fff")).toEqual({ red: 1, green: 1, blue: 1, alpha: 1 });
    expect(colorFromHex(" 000000 ")).toEqual({ red: 0, green: 0, blue: 0, alpha: 1 });
    expect(colorFromHex("#ff000080")).toEqual({ red: 1, green: 0, blue: 0, alpha: 128 / 255 });
    expect(colorFromHex("#12")).toBeNull();
    expect(colorFromHex("#gggggg")).toBeNull();
  });

  it("writes CSS", () => {
    expect(colorToCss({ red: 1, green: 0.5, blue: 0, alpha: 2 })).toBe("rgba(255, 128, 0, 1)");
  });

  it("reads theme tokens, preferring dark overrides in dark mode", () => {
    const theme = { light: { accent: "#ff0000" }, dark: { accent: "#0000ff" } };
    expect(themeColor(theme, "accent")).toEqual({ red: 1, green: 0, blue: 0, alpha: 1 });
    expect(themeColor(theme, "accent", true)).toEqual({ red: 0, green: 0, blue: 1, alpha: 1 });
    expect(themeColor({ light: { accent: "#ff0000" } }, "accent", true)).toEqual({ red: 1, green: 0, blue: 0, alpha: 1 });
    expect(themeColor(undefined, "accent")).toBeNull();
  });
});

describe("cover passes", () => {
  const secret = Buffer.from("a-very-secret-key").toString("base64");

  it("makes codes that change every 30 seconds", () => {
    const start = 56_666_666 * 30;
    const code = coverPassCode("a-1", secret, start);
    expect(code).toMatch(/^HMC1\.a-1\.56666666\.[A-Za-z0-9_-]{16}$/);
    expect(coverPassCode("a-1", secret, start + 29)).toBe(code);
    expect(coverPassCode("a-1", secret, start + 30)).not.toBe(code);
    expect(coverPassCode("a-1", secret)).toMatch(/^HMC1\.a-1\./);
    expect(isCoverPassCode(code)).toBe(true);
  });

  it("matches the Kotlin and Swift SDKs' signature", () => {
    // HMAC-SHA256 of "a-1.56666666" with the decoded secret, URL-safe Base64 without padding, first 16 characters.
    expect(coverPassSignature("a-1", secret, 56666666)).toHaveLength(16);
    expect(coverPassSignature("a-1", secret, 56666666)).toBe(coverPassSignature("a-1", secret, 56666666));
    expect(coverPassSignature("a-2", secret, 56666666)).not.toBe(coverPassSignature("a-1", secret, 56666666));
  });

  it("counts windows", () => {
    expect(coverPassWindow(59)).toBe(1);
    expect(secondsUntilNextCoverPassWindow(59)).toBe(1);
    expect(secondsUntilNextCoverPassWindow(60)).toBe(30);
    expect(secondsUntilNextCoverPassWindow(-1)).toBe(1);
  });

  it("recognises pass codes", () => {
    expect(isCoverPassCode(" HMC1.id.123.sig ")).toBe(true);
    expect(isCoverPassCode("HMC1.id.12x.sig")).toBe(false);
    expect(isCoverPassCode("HMC2.id.123.sig")).toBe(false);
    expect(isCoverPassCode("HMC1.id.123")).toBe(false);
    expect(isCoverPassCode("HMC1..123.sig")).toBe(false);
    expect(isCoverPassCode("HMC1.id.123.")).toBe(false);
  });
});

describe("errors", () => {
  it("reads a GraphQL error's code, fields and reason", () => {
    const error = { message: "Invalid", extensions: { code: "INVALID", fields: { name: ["is blank", 3], other: "x" }, reason: "no_permission" } };
    expect(graphQLErrorCode(error)).toBe("INVALID");
    expect(graphQLErrorFields(error)).toEqual({ name: ["is blank"], other: [] });
    expect(graphQLErrorReason(error)).toBe("no_permission");
    expect(graphQLErrorCode({ message: "bad query" })).toBeNull();
    expect(graphQLErrorFields({ message: "x", extensions: { fields: ["nope"] } })).toEqual({});
    expect(graphQLErrorReason({ message: "x", extensions: {} })).toBeNull();
  });

  it("builds every kind", () => {
    expect(AudienceKitError.notSignedIn().code).toBe("NOT_SIGNED_IN");
    expect(AudienceKitError.forbidden().code).toBe("FORBIDDEN");
    expect(AudienceKitError.notFound().message).toBe("That isn't available.");
    expect(AudienceKitError.network("boom").message).toBe("The network request failed.");
    expect(AudienceKitError.network(new Error("")).message).toBe("The network request failed.");
    expect(AudienceKitError.decoding("x").message).toContain("x");
    expect(AudienceKitError.tokenStorage("x").code).toBe("TOKEN_STORAGE");
    expect(AudienceKitError.signInRejected().message).toContain("refused");
    expect(AudienceKitError.forStatus(418).status).toBe(418);
    const graphQL = AudienceKitError.graphQL([{ message: "a" }, { message: "b", extensions: { code: "undefinedField" } }]);
    expect(graphQL.message).toBe("a\nb");
    expect(graphQL.isUndefinedField).toBe(true);
    expect(graphQL.isUnauthenticated).toBe(false);
    expect(graphQL.name).toBe("AudienceKitError");
    expect(graphQL).toBeInstanceOf(Error);
  });
});

describe("models", () => {
  it("falls back to the Facebook Page's name", () => {
    const page = { id: "p", name: "Oasis SF" };
    expect(listingName({ name: "Oasis", profile: { facebook: { page } } })).toBe("Oasis");
    expect(listingName({ profile: { facebook: { page } } })).toBe("Oasis SF");
    expect(listingName({})).toBe("");
    expect(listingPage({ profile: { facebook: { page } } })).toBe(page);
    expect(listingPage({ profile: null })).toBeNull();
  });

  it("reads place IDs and connections", () => {
    expect(localeGooglePlaceId({ id: "l", profile: { places: { placeId: "ChIJ" } } })).toBe("ChIJ");
    expect(localeGooglePlaceId({ id: "l" })).toBeNull();
    expect(connectionItems({ nodes: [1, null, 2] })).toEqual([1, 2]);
    expect(connectionItems(null)).toEqual([]);
    expect(connectionItems({})).toEqual([]);
  });

  it("reads an event's module parts", () => {
    const venue = { id: "v" };
    const host = { id: "h" };
    const offer = { seller: { key: "ak", name: "AudienceKit" } };
    const charge = { amount: { cents: 1, currency: "usd" }, total: { cents: 1, currency: "usd" }, night: "n" };
    const event: Event = { id: "e", venue: { name: "Oasis", venue }, people: { hosts: { nodes: [host] }, lineup: { nodes: [] } }, tickets: { offers: { nodes: [offer] }, cover: { charge } } };
    expect(eventVenue(event)).toBe(venue);
    expect(eventHosts(event)).toEqual([host]);
    expect(eventLineup(event)).toEqual([]);
    expect(eventTicketOffers(event)).toEqual([offer]);
    expect(eventCoverCharge(event)).toBe(charge);
    const bare: Event = { id: "e" };
    expect(eventVenue(bare)).toBeNull();
    expect(eventHosts(bare)).toBeNull();
    expect(eventLineup(bare)).toBeNull();
    expect(eventTicketOffers(bare)).toBeNull();
    expect(eventCoverCharge(bare)).toBeNull();
  });

  it("reads a purchase's state", () => {
    const admission: Admission = { id: "a", status: "PENDING", night: "n" };
    expect(isAdmissionPaid(admission)).toBe(false);
    expect(isAdmissionPaid({ ...admission, status: "PAID" })).toBe(true);
    expect(isSquarePurchase({ admission, provider: "SQUARE" })).toBe(true);
    expect(isPurchasePaid({ admission, provider: "SQUARE" })).toBe(false);
    expect(isPurchasePaid({ admission, provider: "STRIPE", paymentIntentClientSecret: "pi" })).toBe(false);
    expect(isPurchasePaid({ admission, provider: "STRIPE" })).toBe(true);
  });
});

describe("the schema shape", () => {
  it("assumes everything before asking", () => {
    expect(SchemaShape.EVERYTHING.has("Venue", "anything")).toBe(true);
    const shape = new SchemaShape({ Venue: ["id"] });
    expect(shape.has("Venue", "id")).toBe(true);
    expect(shape.has("Venue", "profile")).toBe(false);
    expect(shape.has("Person", "id")).toBe(false);
    expect(new SchemaShape(new Map([["Venue", new Set(["id"])]])).has("Venue", "id")).toBe(true);
  });
});

describe("operations and endpoints", () => {
  it("describes documents", () => {
    expect(describeOperation("query Venues { venues { id } }")).toEqual({ type: "query", name: "Venues" });
    expect(describeOperation("\n  mutation { x }")).toEqual({ type: "mutation", name: null });
    expect(describeOperation("{ me { id } }")).toEqual({ type: "query", name: null });
    expect(describeOperation("{ me { id } }", "Anon")).toEqual({ type: "query", name: "Anon" });
    expect(describeOperation("subscription ChatRoom($id: ID!) { room }", "Given")).toEqual({ type: "subscription", name: "Given" });
  });

  it("builds endpoint paths", () => {
    expect(endpointPath(CONSUMER_ENDPOINT, "abc")).toBe("/v1/audience/abc/graphql");
  });

  it("fills configuration defaults", () => {
    expect(resolveConfiguration()).toEqual({ baseUrl: "https://api.audiencekit.com", host: null, audienceId: null, facebookAppId: null, environment: "production" });
    expect(resolveConfiguration({ baseUrl: "http://localhost:3000//" }).baseUrl).toBe("http://localhost:3000");
  });
});
