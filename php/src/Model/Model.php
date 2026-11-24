<?php

declare(strict_types=1);

namespace AudienceKit\Model;

use ArrayAccess;
use AudienceKit\Coordinate;
use DateTimeImmutable;
use Exception;
use JsonSerializable;
use LogicException;

/**
 * A result from the API: typed properties for what apps read most, over the API's JSON exactly as it came back.
 *
 * Every model is also readable as the array it was made from (`$venue['locale']['name']`), so code written against
 * the 0.1 releases, which returned arrays, keeps working, and fields the model has no property for are still there.
 * {@see raw()} returns that array; `json_encode()` writes it back out. Models are read-only.
 *
 * @implements ArrayAccess<string, mixed>
 */
abstract class Model implements ArrayAccess, JsonSerializable
{
    /** @param array<string, mixed> $raw The API's JSON for this object, decoded to an array. */
    final public function __construct(private readonly array $raw)
    {
        $this->hydrate($raw);
    }

    /**
     * The model for `$data`, or null when it isn't an object (the field was null, or its module isn't installed).
     */
    public static function from(mixed $data): ?static
    {
        return is_array($data) ? new static($data) : null;
    }

    /**
     * The models for a JSON list, skipping nulls: a connection's `nodes` or a plain list.
     *
     * @return list<static>
     */
    public static function list(mixed $data): array
    {
        if (!is_array($data)) {
            return [];
        }
        if (array_key_exists('nodes', $data)) {
            $data = is_array($data['nodes']) ? $data['nodes'] : [];
        }
        $models = [];
        foreach ($data as $item) {
            if (is_array($item)) {
                $models[] = new static($item);
            }
        }

        return $models;
    }

    /** @param array<string, mixed> $raw */
    abstract protected function hydrate(array $raw): void;

    /** The API's JSON for this object, as it came back. @return array<string, mixed> */
    public function raw(): array
    {
        return $this->raw;
    }

    /** @return array<string, mixed> */
    public function jsonSerialize(): array
    {
        return $this->raw;
    }

    public function offsetExists(mixed $offset): bool
    {
        return isset($this->raw[$offset]);
    }

    public function offsetGet(mixed $offset): mixed
    {
        return $this->raw[$offset] ?? null;
    }

    public function offsetSet(mixed $offset, mixed $value): never
    {
        throw new LogicException(static::class . ' is read-only.');
    }

    public function offsetUnset(mixed $offset): never
    {
        throw new LogicException(static::class . ' is read-only.');
    }

    // Decoding helpers for hydrate().

    /** @param array<string, mixed> $raw */
    protected static function string(array $raw, string $key): ?string
    {
        $value = $raw[$key] ?? null;
        if (is_string($value)) {
            return $value;
        }

        return is_int($value) || is_float($value) ? (string) $value : null;
    }

    /** @param array<string, mixed> $raw */
    protected static function id(array $raw, string $key = 'id'): string
    {
        return self::string($raw, $key) ?? '';
    }

    /** @param array<string, mixed> $raw */
    protected static function int(array $raw, string $key): ?int
    {
        $value = $raw[$key] ?? null;
        if (is_int($value)) {
            return $value;
        }

        return is_float($value) || (is_string($value) && is_numeric($value)) ? (int) $value : null;
    }

    /** @param array<string, mixed> $raw */
    protected static function bool(array $raw, string $key): ?bool
    {
        $value = $raw[$key] ?? null;

        return is_bool($value) ? $value : null;
    }

    /** @param array<string, mixed> $raw */
    protected static function date(array $raw, string $key): ?DateTimeImmutable
    {
        $value = $raw[$key] ?? null;
        if (!is_string($value) || $value === '') {
            return null;
        }
        try {
            return new DateTimeImmutable($value);
        } catch (Exception) {
            return null;
        }
    }

    /**
     * @param array<string, mixed> $raw
     * @return list<string>
     */
    protected static function strings(array $raw, string $key): array
    {
        $value = $raw[$key] ?? null;

        return is_array($value) ? array_values(array_filter($value, 'is_string')) : [];
    }

    /**
     * The object at a path of keys, or null where any of it is missing.
     *
     * @param array<string, mixed> $raw
     */
    protected static function at(array $raw, string ...$path): mixed
    {
        $value = $raw;
        foreach ($path as $key) {
            if (!is_array($value) || !array_key_exists($key, $value)) {
                return null;
            }
            $value = $value[$key];
        }

        return $value;
    }

    /** A WKT point (`POINT (<longitude> <latitude>)`) as a coordinate. */
    protected static function point(mixed $wkt): ?Coordinate
    {
        return is_string($wkt) ? Coordinate::fromWkt($wkt) : null;
    }
}
