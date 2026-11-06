<?php

declare(strict_types=1);

namespace AudienceKit;

/** One entry of a GraphQL response's `errors` array. */
final class GraphQLError
{
    /**
     * @param string                    $message
     * @param list<string|int>|null     $path       The response path of the field that failed, e.g. ["venues", 0].
     * @param array<string, mixed>|null $extensions Extra detail: `code` ({@see AudienceKitException}'s codes) and,
     *                                              for INVALID, `fields` mapping each field to its messages.
     */
    public function __construct(
        public readonly string $message,
        public readonly ?array $path = null,
        public readonly ?array $extensions = null,
    ) {
    }

    /** @param array<string, mixed> $data */
    public static function fromArray(array $data): self
    {
        $message = $data['message'] ?? null;
        $path = $data['path'] ?? null;
        $extensions = $data['extensions'] ?? null;

        return new self(
            is_string($message) ? $message : 'The request failed.',
            is_array($path) ? array_values($path) : null,
            is_array($extensions) ? $extensions : null,
        );
    }

    /** `extensions.code`, when the API sent one. */
    public function code(): ?string
    {
        $code = $this->extensions['code'] ?? null;

        return is_string($code) ? $code : null;
    }
}
