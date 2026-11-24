<?php

declare(strict_types=1);

namespace AudienceKit\Model;

/** A message in a venue's or locale's chat. */
final class ChatMessage extends Model
{
    public readonly string $id;
    /** The text as sent. */
    public readonly ?string $body;
    /** The sender's name, as the room shows it. */
    public readonly ?string $name;
    public readonly ?string $userId;
    public readonly ?string $avatarUrl;
    public readonly ?string $photoUrl;
    public readonly ?\DateTimeImmutable $sentAt;
    /** The sender's role in the room, e.g. "member" or "staff". */
    public readonly ?string $role;
    /** "MESSAGE", "ANNOUNCEMENT", "PROMPT"… */
    public readonly ?string $kind;
    public readonly ?string $title;
    public readonly bool $pinned;

    protected function hydrate(array $raw): void
    {
        $this->id = self::id($raw);
        $this->body = self::string($raw, "body") ?? self::string($raw, "message");
        $this->name = self::string($raw, "name");
        $this->userId = self::string($raw, "userId");
        $this->avatarUrl = self::string($raw, "avatarUrl");
        $this->photoUrl = self::string($raw, "photoUrl");
        $this->sentAt = self::date($raw, "sentAt");
        $this->role = self::string($raw, "role");
        $this->kind = self::string($raw, "kind");
        $this->title = self::string($raw, "title");
        $this->pinned = self::bool($raw, "pinned") ?? false;
    }
}
