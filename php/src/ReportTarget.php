<?php

declare(strict_types=1);

namespace AudienceKit;

/**
 * What {@see AudienceSession::reportContent()} reports: the API's `ReportTarget`, and the words around reporting that
 * the Swift and Kotlin apps use, so every app says the same thing.
 */
final class ReportTarget
{
    /** A chat message (its frame ID). */
    public const MESSAGE = 'MESSAGE';
    /** A member (their user ID, as chat gives it). */
    public const PERSON = 'PERSON';
    public const PHOTO = 'PHOTO';
    public const PING = 'PING';
    /** A line in a Ping or Quickie chat; it and the lines before it are kept with the report. */
    public const PRIVATE_MESSAGE = 'PRIVATE_MESSAGE';
    public const POST = 'POST';
    public const POST_COMMENT = 'POST_COMMENT';
    public const VENUE = 'VENUE';

    /**
     * The reason for an intimate image shared without the consent of the person in it. The API gives a report with
     * this reason a 48-hour deadline (the US Take It Down Act), so keep the wording.
     */
    public const INTIMATE_IMAGE = 'Intimate image shared without consent';

    /** The reasons to offer. */
    public const REASONS = ['Spam', 'Harassment or hate', 'Sexual content', self::INTIMATE_IMAGE, 'Scam or fraud', 'Other'];

    private function __construct()
    {
    }
}
