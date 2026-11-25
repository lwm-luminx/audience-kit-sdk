// Venue-local time for Velvet's TV board without a time zone library: the board's times are shown in the venue's zone,
// and "tonight" runs from 6 AM to 6 AM there (venueServiceNight on Android, VenueNight on iOS).

/** A date and hour as they read on a clock in `zone`. */
export interface ZonedParts {
  year: number;
  month: number;
  day: number;
  hour: number;
  minute: number;
}

/** `zone` when the runtime knows it, else the device's own. */
export function zoneOrDefault(zone: string | null | undefined): string {
  if (zone) {
    try {
      new Intl.DateTimeFormat("en-US", { timeZone: zone });
      return zone;
    } catch {
      // An unknown zone: the device's.
    }
  }
  return Intl.DateTimeFormat().resolvedOptions().timeZone || "UTC";
}

/** What a clock in `zone` reads at `date`. */
export function zonedParts(date: Date, zone: string): ZonedParts {
  const parts = new Intl.DateTimeFormat("en-US", {
    timeZone: zone,
    hourCycle: "h23",
    year: "numeric",
    month: "numeric",
    day: "numeric",
    hour: "numeric",
    minute: "numeric",
  }).formatToParts(date);
  const value = (type: string) => Number(parts.find((part) => part.type === type)?.value ?? 0);
  return { year: value("year"), month: value("month"), day: value("day"), hour: value("hour") % 24, minute: value("minute") };
}

/** The instant a clock in `zone` reads `year-month-day hour:00` (the earlier one when the clock goes back). */
export function zonedInstant(year: number, month: number, day: number, hour: number, zone: string): Date {
  const wanted = Date.UTC(year, month - 1, day, hour);
  let guess = wanted;
  // Two passes settle the zone's offset, including across a change of offset.
  for (let pass = 0; pass < 2; pass += 1) {
    const read = zonedParts(new Date(guess), zone);
    const readAsUtc = Date.UTC(read.year, read.month - 1, read.day, read.hour, read.minute);
    guess += wanted - readAsUtc;
  }
  return new Date(guess);
}

/** The service night's date ("2026-11-24") in `zone`: before 6 AM it's still the night before. */
export function serviceNight(zone: string, now: Date = new Date()): string {
  const local = zonedParts(now, zone);
  const date = new Date(Date.UTC(local.year, local.month - 1, local.day - (local.hour < 6 ? 1 : 0)));
  return date.toISOString().slice(0, 10);
}

/** Tonight's window in `zone`: 6 AM on the service night until 6 AM the next day. */
export function tonightWindow(zone: string, now: Date = new Date()): [Date, Date] {
  const [year, month, day] = serviceNight(zone, now).split("-").map(Number) as [number, number, number];
  return [zonedInstant(year, month, day, 6, zone), zonedInstant(year, month, day + 1, 6, zone)];
}

/** "9 PM" or "9:30 PM" in `zone`. */
export function clock(date: Date, zone: string): string {
  const { hour, minute } = zonedParts(date, zone);
  const twelve = hour % 12 === 0 ? 12 : hour % 12;
  const suffix = hour < 12 ? "AM" : "PM";
  return minute === 0 ? `${twelve} ${suffix}` : `${twelve}:${String(minute).padStart(2, "0")} ${suffix}`;
}

/** The API's ISO 8601 timestamp, or null. */
export function parseInstant(value: unknown): Date | null {
  if (typeof value !== "string" || value.trim() === "") return null;
  const time = Date.parse(value);
  return Number.isNaN(time) ? null : new Date(time);
}
