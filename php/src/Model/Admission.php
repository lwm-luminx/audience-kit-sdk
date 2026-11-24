<?php

declare(strict_types=1);

namespace AudienceKit\Model;

use AudienceKit\CoverPass;

/**
 * A cover pass or coat check ticket the signed-in user bought, with the secret its QR code is made from
 * ({@see passCode()}).
 */
final class Admission extends Model
{
    public readonly string $id;
    /** "PENDING", "PAID", "FAILED", "CANCELED", "REFUNDED" or "DISPUTED". */
    public readonly string $status;
    /** "COVER" or "COAT_CHECK". */
    public readonly string $kind;
    /** The night it is for, `YYYY-MM-DD`. */
    public readonly ?string $night;
    /** How many: coats, for coat check. */
    public readonly int $quantity;
    public readonly ?string $tier;
    /** The coat check number to show at the counter. */
    public readonly ?string $claimCheckNumber;
    public readonly ?Money $amount;
    public readonly ?Money $fee;
    public readonly ?Money $total;
    public readonly bool $isRefundable;
    /** Base64; never log it. Null once it can't get anyone in. */
    public readonly ?string $passSecret;
    public readonly int $scanCount;
    public readonly ?\DateTimeImmutable $checkedInAt;
    public readonly ?\DateTimeImmutable $createdAt;
    /** The buyer, for the door. */
    public readonly ?Profile $profile;
    /** `id name photoUrl`. @var array<string, mixed>|null */
    public readonly ?array $venue;
    /** `id name`. @var array<string, mixed>|null */
    public readonly ?array $event;

    protected function hydrate(array $raw): void
    {
        $this->id = self::id($raw);
        $this->status = self::string($raw, 'status') ?? 'PENDING';
        $this->kind = self::string($raw, 'kind') ?? 'COVER';
        $this->night = self::string($raw, 'night');
        $this->quantity = self::int($raw, 'quantity') ?? 1;
        $this->tier = self::string($raw, 'tier');
        $this->claimCheckNumber = self::string($raw, 'claimCheckNumber');
        $this->amount = Money::from($raw['amount'] ?? null);
        $this->fee = Money::from($raw['fee'] ?? null);
        $this->total = Money::from($raw['total'] ?? null);
        $this->isRefundable = self::bool($raw, 'isRefundable') ?? false;
        $this->passSecret = self::string($raw, 'passSecret');
        $this->scanCount = self::int($raw, 'scanCount') ?? 0;
        $this->checkedInAt = self::date($raw, 'checkedInAt');
        $this->createdAt = self::date($raw, 'createdAt');
        $this->profile = Profile::from($raw['profile'] ?? null);
        $this->venue = is_array($raw['venue'] ?? null) ? $raw['venue'] : null;
        $this->event = is_array($raw['event'] ?? null) ? $raw['event'] : null;
    }

    /** Whether it's paid for and gets its holder in. */
    public function isPaid(): bool
    {
        return $this->status === 'PAID';
    }

    /** The QR code to show at the door at `$epochSeconds` (now by default); null without a pass secret. */
    public function passCode(?int $epochSeconds = null): ?string
    {
        return $this->passSecret === null ? null : CoverPass::code($this->id, $this->passSecret, $epochSeconds);
    }
}
