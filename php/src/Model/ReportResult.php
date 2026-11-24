<?php

declare(strict_types=1);

namespace AudienceKit\Model;

/** What happened to a report: whether it was filed, and whether the person behind it is now blocked. */
final class ReportResult
{
    public function __construct(public readonly bool $reported = false, public readonly bool $blocked = false)
    {
    }
}
