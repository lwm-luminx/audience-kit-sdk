<?php

declare(strict_types=1);

namespace AudienceKit;

use RuntimeException;
use Throwable;

/**
 * Everything an {@see AudienceSession} call can fail with: a `code` from the API's vocabulary (or the SDK's own, for
 * failures before a response), a message for the person, and what detail there is.
 *
 * Compare {@see errorCode} against the CODE_* constants: the API's UNAUTHENTICATED, FORBIDDEN, NOT_FOUND, INVALID (with
 * per-field messages in {@see fields}), RATE_LIMITED, CONFLICT and INTERNAL, which it sends as `extensions.code` on
 * GraphQL errors and as `error` on REST ones, plus the SDK's client-side codes. A code the SDK doesn't know is passed
 * through as the API sent it. {@see getCode()} is PHP's integer code and stays 0; read {@see errorCode} instead.
 */
class AudienceKitException extends RuntimeException
{
    // The API's vocabulary.

    /** The API rejected the session (HTTP 401). The session has already forgotten the credential; sign in again. */
    public const CODE_UNAUTHENTICATED = 'UNAUTHENTICATED';
    /** Signed in, but not allowed here (HTTP 403). */
    public const CODE_FORBIDDEN = 'FORBIDDEN';
    /** The audience, record or host doesn't exist (HTTP 404). */
    public const CODE_NOT_FOUND = 'NOT_FOUND';
    /** The input was refused; {@see fields} says which parts. */
    public const CODE_INVALID = 'INVALID';
    /** Too many requests (HTTP 429). */
    public const CODE_RATE_LIMITED = 'RATE_LIMITED';
    /** The change clashed with the record's state (HTTP 409). */
    public const CODE_CONFLICT = 'CONFLICT';
    /** The API failed (HTTP 5xx, or a GraphQL error it couldn't classify). */
    public const CODE_INTERNAL = 'INTERNAL';

    // Raised by the SDK.

    /** There is no stored credential; sign in first. */
    public const CODE_NOT_SIGNED_IN = 'NOT_SIGNED_IN';
    /** `POST /v1/token` refused the Facebook or Apple token (HTTP 401). */
    public const CODE_SIGN_IN_REJECTED = 'SIGN_IN_REJECTED';
    /** `POST /v1/token` failed (HTTP 400). The message is the API's when it sent one. */
    public const CODE_SIGN_IN_FAILED = 'SIGN_IN_FAILED';
    /** Any other unsuccessful HTTP status; see {@see status}. */
    public const CODE_HTTP = 'HTTP';
    /** The request never got a response: offline, timed out, TLS failure and so on. */
    public const CODE_NETWORK = 'NETWORK';
    /** The response wasn't the JSON the SDK expected. */
    public const CODE_DECODING = 'DECODING';
    /** A GraphQL error with no `extensions.code`, such as a validation failure of the document itself. */
    public const CODE_GRAPHQL = 'GRAPHQL';
    /** The configuration is missing something this call needs, e.g. a host. */
    public const CODE_MISSING_CONFIGURATION = 'MISSING_CONFIGURATION';
    /** The credential store couldn't save or delete the session. */
    public const CODE_STORAGE = 'STORAGE';
    /** The API no longer serves this SDK version (HTTP 426). */
    public const CODE_UPDATE_REQUIRED = 'UPDATE_REQUIRED';
    /** The API no longer serves the API version this SDK speaks (HTTP 400 `unsupported_api_version`). */
    public const CODE_UNSUPPORTED_API_VERSION = 'UNSUPPORTED_API_VERSION';

    /** The REST body's `error` for an API version the API no longer serves. */
    public const UNSUPPORTED_API_VERSION_ERROR = 'unsupported_api_version';

    /**
     * @param string                       $code              One of the CODE_* constants, or whatever the API sent.
     * @param string                       $message           A message for the person.
     * @param int|null                     $status            The HTTP status of the response, when there was one.
     * @param array<string, list<string>>  $fields            INVALID only: the API's messages per field.
     * @param list<GraphQLError>           $errors            The GraphQL response's `errors`, when it returned any.
     * @param string|null                  $minimumSdkVersion UPDATE_REQUIRED only: the oldest SDK version served.
     */
    public function __construct(
        public readonly string $errorCode,
        string $message,
        public readonly ?int $status = null,
        public readonly array $fields = [],
        public readonly array $errors = [],
        public readonly ?string $minimumSdkVersion = null,
        ?Throwable $previous = null,
    ) {
        parent::__construct($message, 0, $previous);
    }

    public static function notSignedIn(): self
    {
        return new self(self::CODE_NOT_SIGNED_IN, "You're not signed in.");
    }

    public static function unauthorized(): self
    {
        return new self(self::CODE_UNAUTHENTICATED, 'Your session has ended. Sign in again to continue.', 401);
    }

    public static function signInRejected(): self
    {
        return new self(self::CODE_SIGN_IN_REJECTED, "Sign-in was refused. The login isn't valid for this app.", 401);
    }

    public static function signInFailed(?string $message): self
    {
        return new self(self::CODE_SIGN_IN_FAILED, $message ?? 'Sign-in failed.', 400);
    }

    public static function forbidden(?string $message = null): self
    {
        return new self(self::CODE_FORBIDDEN, $message ?? "You don't have access to this.", 403);
    }

    public static function notFound(?string $message = null): self
    {
        return new self(self::CODE_NOT_FOUND, $message ?? "That isn't available.", 404);
    }

    public static function http(int $status, ?string $code = null, ?string $message = null): self
    {
        return new self($code ?? self::CODE_HTTP, $message ?? "The server responded with status $status.", $status);
    }

    public static function network(Throwable $error): self
    {
        return new self(self::CODE_NETWORK, $error->getMessage(), null, [], [], null, $error);
    }

    public static function decoding(string $detail): self
    {
        return new self(self::CODE_DECODING, "The server sent a response the app didn't understand. $detail");
    }

    public static function missingConfiguration(string $detail): self
    {
        return new self(self::CODE_MISSING_CONFIGURATION, "AudienceKit isn't configured: $detail");
    }

    public static function storage(string $detail, ?Throwable $previous = null): self
    {
        return new self(self::CODE_STORAGE, "The session couldn't be saved. $detail", null, [], [], null, $previous);
    }

    public static function updateRequired(string $minimumSdkVersion, ?string $message): self
    {
        return new self(
            self::CODE_UPDATE_REQUIRED,
            $message ?? 'This version of the app is out of date. Update it to keep going.',
            426,
            minimumSdkVersion: $minimumSdkVersion,
        );
    }

    /**
     * The GraphQL operation returned `errors`: the code and message are the first one's, and INVALID errors'
     * `extensions.fields` become {@see fields}.
     *
     * @param list<GraphQLError> $errors
     */
    public static function graphQL(array $errors): self
    {
        $first = $errors[0] ?? null;
        $fields = [];
        $sent = $first?->extensions['fields'] ?? null;
        if (is_array($sent)) {
            foreach ($sent as $field => $value) {
                if (is_array($value)) {
                    $fields[(string) $field] = array_values(array_filter($value, 'is_string'));
                } elseif (is_string($value)) {
                    $fields[(string) $field] = [$value];
                }
            }
        }

        return new self(
            $first?->code() ?? self::CODE_GRAPHQL,
            $first?->message ?? 'The request failed.',
            null,
            $fields,
            $errors,
        );
    }

    /** Whether the API refused the session: {@see CODE_UNAUTHENTICATED}. */
    public function isUnauthenticated(): bool
    {
        return $this->errorCode === self::CODE_UNAUTHENTICATED;
    }

    /**
     * Whether the API refused the query because it asks for a field this audience's schema doesn't have: one a
     * module adds that the audience hasn't installed (or one from a newer API).
     */
    public function isUndefinedField(): bool
    {
        foreach ($this->errors as $error) {
            if ($error->code() === 'undefinedField') {
                return true;
            }
        }

        return false;
    }
}
