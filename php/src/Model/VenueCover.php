<?php

declare(strict_types=1);

namespace AudienceKit\Model;

/** A venue's cover tonight, with the signed-in user's pass and coat check ticket for it. */
final class VenueCover extends Model
{
    public readonly string $id;
    public readonly string $name;
    /** Null where the venue charges no cover, or the audience has no Ticketing and Cover. */
    public readonly ?CoverCharge $charge;
    public readonly ?Admission $viewerAdmission;
    public readonly ?Admission $viewerCoatCheck;

    protected function hydrate(array $raw): void
    {
        $this->id = self::id($raw);
        $this->name = self::string($raw, 'name') ?? '';
        $this->charge = CoverCharge::from(self::at($raw, 'tickets', 'cover', 'charge'));
        $this->viewerAdmission = Admission::from(self::at($raw, 'tickets', 'cover', 'viewerAdmission'));
        $this->viewerCoatCheck = Admission::from(self::at($raw, 'tickets', 'cover', 'viewerCoatCheck'));
    }
}
