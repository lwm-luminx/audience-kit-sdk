<?php

declare(strict_types=1);

namespace AudienceKit\Model;

/**
 * A venue's cover on a night: the amount, the fee and the total the buyer pays, whether it can be paid in the app,
 * its coat check, and on a sliding scale the range the buyer picks from.
 */
final class CoverCharge extends Model
{
    public readonly ?Money $amount;
    public readonly ?Money $fee;
    public readonly ?Money $total;
    /** The night it is for, `YYYY-MM-DD`. */
    public readonly ?string $night;
    /** When it starts being charged. */
    public readonly ?\DateTimeImmutable $from;
    /** Whether it can be paid in the app. */
    public readonly bool $payable;
    /** The event it is for, `id name`. @var array<string, mixed>|null */
    public readonly ?array $event;
    /** Coat check that night: `amount fee total night payable`. @var array<string, mixed>|null */
    public readonly ?array $coatCheck;
    /** On a sliding scale: the least, most and suggested amounts. */
    public readonly ?Money $scaleMin;
    public readonly ?Money $scaleMax;
    public readonly ?Money $scaleSuggested;

    protected function hydrate(array $raw): void
    {
        $this->amount = Money::from($raw['amount'] ?? null);
        $this->fee = Money::from($raw['fee'] ?? null);
        $this->total = Money::from($raw['total'] ?? null);
        $this->night = self::string($raw, 'night');
        $this->from = self::date($raw, 'from');
        $this->payable = self::bool($raw, 'payable') ?? false;
        $this->event = is_array($raw['event'] ?? null) ? $raw['event'] : null;
        $this->coatCheck = is_array($raw['coatCheck'] ?? null) ? $raw['coatCheck'] : null;
        $this->scaleMin = Money::from(self::at($raw, 'scale', 'min'));
        $this->scaleMax = Money::from(self::at($raw, 'scale', 'max'));
        $this->scaleSuggested = Money::from(self::at($raw, 'scale', 'suggested'));
    }

    /** Whether the buyer picks what to pay. */
    public function isSlidingScale(): bool
    {
        return $this->scaleMin !== null && $this->scaleMax !== null;
    }

    /** Whether the venue checks coats that night and takes payment for it in the app. */
    public function hasCoatCheck(): bool
    {
        return ($this->coatCheck['payable'] ?? false) === true;
    }
}
