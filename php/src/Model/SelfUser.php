<?php

declare(strict_types=1);

namespace AudienceKit\Model;

/** The signed-in user's own profile (`me { self }`). */
final class SelfUser extends Model
{
    public readonly string $id;
    public readonly string $name;
    public readonly ?string $firstName;
    public readonly ?string $lastName;
    public readonly ?string $emailAddress;
    public readonly bool $isAdmin;
    /** "ONLINE", "PUSH" or "OFFLINE". */
    public readonly ?string $presence;

    protected function hydrate(array $raw): void
    {
        $this->id = self::id($raw);
        $this->name = self::string($raw, "name") ?? "";
        $this->firstName = self::string($raw, "firstName");
        $this->lastName = self::string($raw, "lastName");
        $this->emailAddress = self::string($raw, "emailAddress");
        $this->isAdmin = self::bool($raw, "isAdmin") ?? false;
        $this->presence = self::string($raw, "presence");
    }
}
