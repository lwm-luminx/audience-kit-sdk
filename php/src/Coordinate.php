<?php

declare(strict_types=1);

namespace AudienceKit;

/**
 * A latitude and longitude in degrees, with the beacon a device heard when there was one: the GraphQL
 * `CoordinatesInput` ({@see toInput()}) and what the SDK reads from the API's WKT points ({@see fromWkt()}).
 */
final class Coordinate
{
    /**
     * @param float    $latitude    Degrees north, -90 to 90.
     * @param float    $longitude   Degrees east, -180 to 180.
     * @param int|null $beaconMajor An iBeacon's major value, which names a locale; null or 0 for none.
     * @param int|null $beaconMinor An iBeacon's minor value; null or 0 for none.
     */
    public function __construct(
        public readonly float $latitude,
        public readonly float $longitude,
        public readonly ?int $beaconMajor = null,
        public readonly ?int $beaconMinor = null,
    ) {
    }

    /**
     * Parses a WKT point, `POINT (<longitude> <latitude>)`, optionally with an SRID prefix (`SRID=4326;POINT (…)`).
     * Null when it isn't a point, or isn't a place on Earth (often the two numbers swapped).
     */
    public static function fromWkt(string $wkt): ?self
    {
        $open = strpos($wkt, '(');
        $close = strrpos($wkt, ')');
        if ($open === false || $close === false || $open >= $close) {
            return null;
        }
        if (!str_contains(strtoupper(substr($wkt, 0, $open)), 'POINT')) {
            return null;
        }
        $numbers = array_values(array_filter(
            preg_split('/\s+/', trim(substr($wkt, $open + 1, $close - $open - 1))) ?: [],
            'is_numeric',
        ));
        if (count($numbers) < 2) {
            return null;
        }
        $longitude = (float) $numbers[0];
        $latitude = (float) $numbers[1];
        if ($latitude < -90 || $latitude > 90 || $longitude < -180 || $longitude > 180) {
            return null;
        }

        return new self($latitude, $longitude);
    }

    /** The value to pass as a `CoordinatesInput` variable. Zero beacon values mean no beacon. @return array<string, float|int> */
    public function toInput(): array
    {
        $input = ['latitude' => $this->latitude, 'longitude' => $this->longitude];
        if ($this->beaconMajor) {
            $input['beaconMajor'] = $this->beaconMajor;
        }
        if ($this->beaconMinor) {
            $input['beaconMinor'] = $this->beaconMinor;
        }

        return $input;
    }

    /** The point as WKT, `POINT (<longitude> <latitude>)`. */
    public function toWkt(): string
    {
        return sprintf('POINT (%s %s)', self::number($this->longitude), self::number($this->latitude));
    }

    /** The great-circle distance to `$other`, in meters. */
    public function distanceTo(self $other): float
    {
        $radius = 6_371_000.0;
        $lat1 = deg2rad($this->latitude);
        $lat2 = deg2rad($other->latitude);
        $dLat = $lat2 - $lat1;
        $dLon = deg2rad($other->longitude - $this->longitude);
        $a = sin($dLat / 2) ** 2 + cos($lat1) * cos($lat2) * sin($dLon / 2) ** 2;

        return 2 * $radius * asin(min(1.0, sqrt($a)));
    }

    private static function number(float $value): string
    {
        $text = rtrim(rtrim(sprintf('%.7F', $value), '0'), '.');

        return $text === '-0' ? '0' : $text;
    }
}
