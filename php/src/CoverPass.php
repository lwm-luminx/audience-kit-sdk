<?php

declare(strict_types=1);

namespace AudienceKit;

/**
 * The QR code on a cover pass, made from the admission's `passSecret` every {@see WINDOW_SECONDS} so it works with no
 * signal and a screenshot stops scanning within a minute:
 *
 *     HMC1.<admission id>.<window>.<signature>
 *
 * where window is the Unix time divided by the window length and signature is the first 16 characters of the
 * unpadded URL-safe Base64 HMAC-SHA256 of `<admission id>.<window>`, keyed with the Base64-decoded secret. The door
 * accepts a couple of windows either side, for clock drift. The same codes the Swift, Kotlin and Node SDKs make.
 */
final class CoverPass
{
    public const PREFIX = 'HMC1';
    public const WINDOW_SECONDS = 30;

    /** The window `$epochSeconds` falls in. */
    public static function window(int $epochSeconds): int
    {
        return intdiv($epochSeconds - (($epochSeconds % self::WINDOW_SECONDS) + self::WINDOW_SECONDS) % self::WINDOW_SECONDS, self::WINDOW_SECONDS);
    }

    /** Seconds from `$epochSeconds` until the code changes. */
    public static function secondsUntilNextWindow(int $epochSeconds): int
    {
        return self::WINDOW_SECONDS - ((($epochSeconds % self::WINDOW_SECONDS) + self::WINDOW_SECONDS) % self::WINDOW_SECONDS);
    }

    public static function signature(string $admissionId, string $passSecret, int $window): string
    {
        $key = base64_decode($passSecret, false);
        $mac = hash_hmac('sha256', "$admissionId.$window", $key === false ? '' : $key, true);

        return substr(rtrim(strtr(base64_encode($mac), '+/', '-_'), '='), 0, 16);
    }

    /** The pass's code at `$epochSeconds` (now by default). */
    public static function code(string $admissionId, string $passSecret, ?int $epochSeconds = null): string
    {
        $window = self::window($epochSeconds ?? time());

        return implode('.', [self::PREFIX, $admissionId, (string) $window, self::signature($admissionId, $passSecret, $window)]);
    }

    /** Whether `$code` looks like a cover pass, before asking the API. */
    public static function isCode(string $code): bool
    {
        $parts = explode('.', trim($code));

        return count($parts) === 4 && $parts[0] === self::PREFIX && $parts[1] !== ''
            && ctype_digit($parts[2]) && $parts[3] !== '';
    }

    private function __construct()
    {
    }
}
