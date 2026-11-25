// The board Velvet's TV screens show, as the Velvet cast receiver (hotmess.social /cast/velvet) draws it: the port of
// Android's VelvetBoardData.kt (`tvBoard`, `TVRoom`), for screens that run JavaScript (Samsung TVs on Tizen). The
// message it builds is the one Google TV and Velvet Display send the cast receiver, so one renderer draws them all.

import { clock, parseInstant, tonightWindow, zoneOrDefault } from "./time.js";

/** A JSON object as the API sends it. */
export type Json = Record<string, unknown>;

const obj = (value: unknown): Json => (value && typeof value === "object" && !Array.isArray(value) ? (value as Json) : {});
const str = (value: unknown): string => (typeof value === "string" ? value : value == null ? "" : String(value));
const rows = (value: unknown): Json[] => (Array.isArray(value) ? value.map(obj) : []);
const at = (value: unknown, ...path: string[]): unknown => path.reduce<unknown>((node, key) => obj(node)[key], value);

/** Only https and http links with a host are shown. */
export function safeWebUrl(value: unknown): string | null {
  const text = str(value).trim();
  try {
    const url = new URL(text);
    return (url.protocol === "https:" || url.protocol === "http:") && url.hostname ? text : null;
  } catch {
    return null;
  }
}

/** The room's chat as the TV shows it: the pinned announcement and the latest messages, oldest first. */
export interface TVRoom {
  pinned: Json | null;
  messages: Json[];
  /** When the room stops showing messages to guests; staff are sent older ones, which the TV leaves out. */
  expiresBefore: Date | null;
}

/** How many messages fit a TV. */
export const TV_ROOM_KEEP = 12;

export const emptyRoom: TVRoom = { pinned: null, messages: [], expiresBefore: null };

/** What the wall shows: what people and the venue say, not the room's own automatic notices. */
export function onWall(message: Json): boolean {
  return str(message.id) !== "" && message.automatic !== true && (str(message.message).trim() !== "" || message.kind === "PHOTO");
}

const sentAt = (message: Json) => parseInstant(message.sentAt)?.getTime() ?? 0;
const keep = (messages: Json[]) => messages.slice(-TV_ROOM_KEEP);

/** The room after one `venueChat` event; null once the room turns the device away. */
export function applyChatEvent(room: TVRoom, payload: Json): TVRoom | null {
  switch (payload.__typename) {
    case "ChatJoined": {
      const cutoff = parseInstant(payload.expiresBefore);
      const pinned = obj(at(payload, "pinnedPost", "message"));
      const history = rows(payload.history)
        .map((entry) => obj(entry.message))
        .filter(onWall)
        .filter((message) => !(cutoff && parseInstant(message.sentAt) && sentAt(message) < cutoff.getTime()))
        .sort((a, b) => str(a.sentAt).localeCompare(str(b.sentAt)));
      return { pinned: str(pinned.id) ? pinned : null, messages: keep(history), expiresBefore: cutoff };
    }
    case "ChatMessagePosted": {
      const message = obj(payload.message);
      if (!onWall(message)) return room;
      return { ...room, messages: keep([...room.messages.filter((m) => m.id !== message.id), message]) };
    }
    case "ChatMessageUpdated": {
      // An edited announcement changes on the TV too, pinned or not.
      const message = obj(payload.message);
      return {
        ...room,
        pinned: room.pinned && room.pinned.id === message.id ? message : room.pinned,
        messages: room.messages.map((m) => (m.id === message.id ? message : m)),
      };
    }
    case "ChatMessageRemoved": {
      const id = str(payload.messageId);
      return {
        ...room,
        pinned: room.pinned && room.pinned.id !== id ? room.pinned : null,
        messages: room.messages.filter((m) => m.id !== id),
      };
    }
    case "ChatPinChanged": {
      const announcement = obj(payload.announcement);
      return { ...room, pinned: payload.isPinned === true && str(announcement.id) ? announcement : null };
    }
    case "ChatRoomCleared": {
      // An admin clearing takes the pin too; messages expiring leave it, as in Hot Mess.
      const clearedAt = parseInstant(payload.clearedAt);
      return {
        ...room,
        pinned: payload.expired === true ? room.pinned : null,
        messages: room.messages.filter((m) => !!clearedAt && sentAt(m) > clearedAt.getTime()),
      };
    }
    case "ChatLeft":
      return null;
    default:
      return room;
  }
}

/** What the TV shows at `now`: a special leaves the wall at its end time, as it leaves the room in Hot Mess. */
export function roomShowing(room: TVRoom, now: Date = new Date()): TVRoom {
  const ended = (message: Json) =>
    message.kind === "SPECIAL" && (parseInstant(message.endsAt)?.getTime() ?? Infinity) <= now.getTime();
  return { ...room, pinned: room.pinned && !ended(room.pinned) ? room.pinned : null, messages: room.messages.filter((m) => !ended(m)) };
}

const BASE62 = "0123456789abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ";

/**
 * The venue's short link, hotmess.social/v/<code>, a QR code that scans from across the room: the top 47 bits of the
 * venue's UUID in base62 (the API's VenueShortLink); the full chat link if the ID isn't a UUID.
 */
export function venueJoinLink(venueId: string): string {
  const hex = venueId.replace(/-/g, "");
  if (!/^[0-9a-fA-F]{32}$/.test(hex)) return `https://hotmess.social/venues/${venueId}/chat`;
  // 48 bits fit a double exactly.
  let value = Math.floor(parseInt(hex.slice(0, 12), 16) / 2);
  let code = "";
  for (let i = 0; i < 8; i += 1) {
    code = BASE62[value % 62] + code;
    value = Math.floor(value / 62);
  }
  return `https://hotmess.social/v/${code}`;
}

/** What's on and what's next, then a few finished sets only while there's room, as the web sign shows. */
export function tvLineup(runningOrder: Json[], max = 8): Json[] {
  const done = runningOrder.filter((entry) => entry.state === "DONE");
  const live = runningOrder.filter((entry) => entry.state !== "DONE");
  const room = Math.max(max - live.length, 0);
  return [...(room > 0 ? done.slice(-room) : []), ...live].slice(0, max);
}

/** The name an entry goes by: its title, else its people's names. */
export function lineupName(entry: Json): string {
  const title = str(entry.title).trim();
  if (title) return title;
  if (entry.kind === "INTERMISSION") return "Intermission";
  let names = rows(at(entry, "people", "nodes")).map((person) => str(person.name)).filter(Boolean);
  if (names.length === 0) names = [str(at(entry, "person", "name"))].filter(Boolean);
  return names.join(" & ") || "Someone";
}

const ROLES: Record<string, string> = { HOST: "Host", DJ: "DJ", MC: "MC", PERFORMER: "Performer", SINGER: "Singer" };

function tvEntry(entry: Json, zone: string): Json {
  const start = parseInstant(entry.startsAt);
  const timing = str(entry.startTiming) || "HARD";
  const song = str(at(entry, "songRequest", "title"));
  let people = rows(at(entry, "people", "nodes"));
  if (people.length === 0 && entry.person && typeof entry.person === "object") people = [obj(entry.person)];
  const kind = str(entry.kind) || "ACT";
  const state = str(entry.state).toLowerCase();
  return {
    id: str(entry.id),
    name: lineupName(entry),
    role: kind !== "ACT" ? "" : song ? `Singing “${song}”` : (ROLES[str(entry.role)] ?? ""),
    time: timing === "NONE" || !start ? "" : (timing === "SOFT" ? "~" : "") + clock(start, zone),
    state: state === "on" || state === "done" ? state : "upcoming",
    images: people.map((person) => safeWebUrl(person.avatarUrl)).filter((url): url is string => !!url).slice(0, 2),
  };
}

const HOST_SUFFIX = " (AI host)";

/** The host's name ("Glam") for an AI host's post, which it says as the venue; null for any other message. */
export function tvHostName(message: Json): string | null {
  const title = str(message.title);
  const hosted = message.kind === "ANNOUNCEMENT" && message.postedAsVenue === true && title.endsWith(HOST_SUFFIX);
  return hosted ? title.slice(0, -HOST_SUFFIX.length) : null;
}

/** What a message says on the wall: a titled post that isn't the host's leads with its title unless the words do. */
export function tvMessageText(message: Json): string {
  const text = str(message.body).trim() || str(message.message).trim();
  if (message.kind === "PHOTO") return text ? `📷 ${text}` : "📷 Photo";
  if (tvHostName(message) !== null) return text;
  const title = str(message.title).trim();
  return !title || text.startsWith(title) ? text : `${title}: ${text}`;
}

/** Whether an event isn't canceled and overlaps tonight's 6 AM to 6 AM window in `zone`. */
export function isTonightEvent(event: Json, zone: string, now: Date = new Date()): boolean {
  if (event.isCanceled === true) return false;
  const start = parseInstant(event.startAt);
  if (!start) return false;
  const end = parseInstant(event.endAt) ?? new Date(start.getTime() + 4 * 3600_000);
  const [from, until] = tonightWindow(zone, now);
  return start < until && end > from;
}

/** The venue's time zone, from its cover settings. */
export function venueZone(venue: Json): string {
  return zoneOrDefault(str(at(venue, "tickets", "cover", "timeZone")) || null);
}

/**
 * The board message the cast receiver shows: the venue, tonight's events and who's on when (times already in the
 * venue's zone), the venue's TV slogans when they're on, and the room's chat when `room` is given.
 */
export function tvBoard(venue: Json, night: Json | null, room: TVRoom | null, now: Date = new Date(), slogans: Json | null = null): Json {
  const zone = venueZone(venue);
  const events = rows(at(venue, "upcomingEvents", "upcoming", "nodes"))
    .filter((event) => isTonightEvent(event, zone, now))
    .map((event) => str(event.name))
    .filter(Boolean);
  const lineup = tvLineup(rows(at(night, "people", "runningOrder", "nodes")));
  const venueName = str(venue.name);
  const photo = safeWebUrl(venue.bannerUrl) ?? safeWebUrl(venue.photoUrl);
  const board: Json = {
    type: "tonight",
    venue: { id: str(venue.id), name: venueName || "Tonight", timeZone: zone, ...(photo ? { photo } : {}) },
    join: venueJoinLink(str(venue.id)),
    events,
    lineup: lineup.map((entry) => tvEntry(entry, zone)),
  };
  if (slogans && slogans.marqueeSlogans === true) {
    const adult = slogans.adultVenue === true;
    const hidden = new Set((Array.isArray(slogans.marqueeHiddenSlogans) ? slogans.marqueeHiddenSlogans : []).map(str));
    board.slogans = {
      adult,
      slides: rows(slogans.marqueePosters)
        .filter((poster) => (adult || poster.adult !== true) && !hidden.has(str(poster.id)))
        .reduce<Json[]>((slides, poster) => {
          // A reduce, not flatMap, which 2019 Samsung TVs (Chromium 63) lack.
          const image = safeWebUrl(poster.image);
          if (image) slides.push({ id: str(poster.id), image, adult: poster.adult === true });
          return slides;
        }, []),
    };
  }
  if (room) {
    const chat = roomShowing(room, now);
    const pinned = chat.pinned ? str(chat.pinned.title).trim() || tvMessageText(chat.pinned) : "";
    board.chat = {
      pinned: pinned || null,
      messages: chat.messages.map((message) => {
        const asVenue = message.postedAsVenue === true;
        const avatar = safeWebUrl(message.avatarUrl);
        const photo = message.kind === "PHOTO" ? safeWebUrl(message.photoUrl) : null;
        return {
          sender: tvHostName(message) ?? (asVenue ? venueName || "The venue" : str(message.name) || "Guest"),
          text: tvMessageText(message),
          venue: asVenue,
          ...(avatar ? { avatar } : {}),
          ...(photo ? { photo } : {}),
        };
      }),
    };
  }
  return board;
}
