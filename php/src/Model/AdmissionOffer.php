<?php

declare(strict_types=1);

namespace AudienceKit\Model;

/** One way into a venue or event: a price, where to buy, and who sells it. */
final class AdmissionOffer extends Model
{
    public readonly ?Money $price;
    public readonly ?string $url;
    /** The seller's key, e.g. "eventbrite" or "cover". */
    public readonly ?string $sellerKey;
    public readonly ?string $sellerName;

    protected function hydrate(array $raw): void
    {
        $this->price = Money::from($raw['price'] ?? null);
        $this->url = self::string($raw, 'url');
        $seller = is_array($raw['seller'] ?? null) ? $raw['seller'] : [];
        $this->sellerKey = self::string($seller, 'key');
        $this->sellerName = self::string($seller, 'name');
    }
}
