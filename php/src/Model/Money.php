<?php

declare(strict_types=1);

namespace AudienceKit\Model;

/** An amount of money: whole cents (or the currency's smallest unit) and an ISO 4217 code, lower-case. */
final class Money extends Model
{
    public readonly int $cents;
    public readonly string $currency;

    protected function hydrate(array $raw): void
    {
        $this->cents = self::int($raw, "cents") ?? 0;
        $this->currency = strtolower(self::string($raw, "currency") ?? "usd");
    }

    /** The amount in the currency's main unit, e.g. 12.5 for 1250 cents. */
    public function amount(): float
    {
        return $this->cents / 100;
    }

    /** The amount for people, e.g. "$12.50", in the given locale when the intl extension is installed. */
    public function format(string $locale = "en_US"): string
    {
        if (class_exists(\NumberFormatter::class)) {
            $formatted = (new \NumberFormatter($locale, \NumberFormatter::CURRENCY))
                ->formatCurrency($this->amount(), strtoupper($this->currency));
            if ($formatted !== false) {
                return $formatted;
            }
        }
        $symbol = ["usd" => "$", "cad" => "CA$", "aud" => "A$", "gbp" => "£", "eur" => "€", "mxn" => "MX$"][$this->currency] ?? null;
        $number = number_format($this->amount(), 2);

        return $symbol !== null ? $symbol . $number : $number . " " . strtoupper($this->currency);
    }
}
