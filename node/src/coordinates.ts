/** A latitude and longitude in degrees. */
export interface Coordinate {
  latitude: number;
  longitude: number;
}

/** Parses a WKT point, `POINT (<longitude> <latitude>)`, optionally with an SRID prefix. */
export function coordinateFromWkt(wkt: string): Coordinate | null {
  const open = wkt.indexOf("(");
  const close = wkt.lastIndexOf(")");
  if (open < 0 || close < 0 || open >= close) return null;
  if (!wkt.slice(0, open).toUpperCase().includes("POINT")) return null;

  const numbers = wkt
    .slice(open + 1, close)
    .trim()
    .split(/\s+/)
    .map(Number)
    .filter((n) => !Number.isNaN(n));
  if (numbers.length < 2) return null;
  const [longitude, latitude] = numbers as [number, number];
  // Not a place on Earth: NaN, infinity, or out of range (often the two swapped).
  if (!(latitude >= -90 && latitude <= 90) || !(longitude >= -180 && longitude <= 180)) return null;
  return { latitude, longitude };
}

/** A device's position, for the GraphQL `CoordinatesInput`. A beacon's major value names a locale. */
export interface Coordinates {
  latitude: number;
  longitude: number;
  beaconMajor?: number | null;
  beaconMinor?: number | null;
}

/** The value to pass as a `CoordinatesInput` variable. Zero beacon values mean no beacon. */
export function coordinatesInput(coordinates: Coordinates): Record<string, number> {
  const input: Record<string, number> = { latitude: coordinates.latitude, longitude: coordinates.longitude };
  if (coordinates.beaconMajor) input.beaconMajor = coordinates.beaconMajor;
  if (coordinates.beaconMinor) input.beaconMinor = coordinates.beaconMinor;
  return input;
}
