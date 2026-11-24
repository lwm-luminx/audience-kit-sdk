<?php

declare(strict_types=1);

namespace AudienceKit\Model;

/**
 * A purchase started with `buyCover` or `buyCoatCheck`: the pending admission and what the payment provider needs.
 * For Stripe, confirm `paymentIntentClientSecret` with Stripe.js, then call `confirmCover`; for Square, make a payment
 * token with the Web Payments SDK and call `payCover`.
 */
final class CoverPurchase extends Model
{
    public readonly ?Admission $admission;
    /** "STRIPE" or "SQUARE". */
    public readonly ?string $provider;
    public readonly ?string $paymentIntentClientSecret;
    public readonly ?string $publishableKey;
    public readonly ?string $stripeAccountId;
    public readonly ?string $squareApplicationId;
    public readonly ?string $squareLocationId;

    protected function hydrate(array $raw): void
    {
        $this->admission = Admission::from($raw['admission'] ?? null);
        $this->provider = self::string($raw, 'provider');
        $this->paymentIntentClientSecret = self::string($raw, 'paymentIntentClientSecret');
        $this->publishableKey = self::string($raw, 'publishableKey');
        $this->stripeAccountId = self::string($raw, 'stripeAccountId');
        $this->squareApplicationId = self::string($raw, 'squareApplicationId');
        $this->squareLocationId = self::string($raw, 'squareLocationId');
    }
}
