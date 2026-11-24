<?php

declare(strict_types=1);

namespace AudienceKit\Model;

/**
 * A venue: a bar, club or space. In a list it carries its locale, location, tags and Facebook Page; on its page
 * ({@see \AudienceKit\AudienceSession::venueDetail()}) also its description, profile, chat and upcoming events, as far
 * as the audience's modules go.
 */
final class Venue extends Model
{
    public readonly string $id;
    public readonly string $name;
    public readonly bool $hidden;
    public readonly ?int $order;
    public readonly ?string $photoUrl;
    public readonly ?string $bannerUrl;
    public readonly ?Locale $locale;
    public readonly ?Location $location;
    /** @var list<Tag> */
    public readonly array $tags;
    /** Its Facebook Page (Listings and Facebook). */
    public readonly ?Page $facebookPage;
    /** On its page: what it says about itself. */
    public readonly ?string $description;
    /** On its page: street address, phone and website from its listing profile. */
    public readonly ?string $address;
    public readonly ?string $phone;
    public readonly ?string $website;
    /** On its page: its links elsewhere, each `id handle provider url`. @var list<array<string, mixed>> */
    public readonly array $socialLinks;
    /** On its page: whether its chat is open (Chat). */
    public readonly ?bool $chatOpen;
    /** On its page: its chat's latest messages, oldest first. @var list<ChatMessage> */
    public readonly array $recentMessages;
    /** On its page: what's coming up there. @var list<Event> */
    public readonly array $upcomingEvents;

    protected function hydrate(array $raw): void
    {
        $this->id = self::id($raw);
        $this->name = self::string($raw, 'name') ?? '';
        $this->hidden = self::bool($raw, 'hidden') ?? false;
        $this->order = self::int($raw, 'order');
        $this->photoUrl = self::string($raw, 'photoUrl');
        $this->bannerUrl = self::string($raw, 'bannerUrl');
        $this->locale = Locale::from($raw['locale'] ?? null);
        $this->location = Location::from($raw['location'] ?? null);
        $this->tags = Tag::list($raw['tags'] ?? null);
        $this->facebookPage = Page::from(self::at($raw, 'profile', 'facebook', 'page'));
        $this->description = self::string($raw, 'description');
        $profile = is_array($raw['profile'] ?? null) ? $raw['profile'] : [];
        $this->address = self::string($profile, 'address');
        $this->phone = self::string($profile, 'phone');
        $this->website = self::string($profile, 'website');
        $links = self::at($profile, 'socialLinks', 'nodes');
        $this->socialLinks = is_array($links) ? array_values(array_filter($links, 'is_array')) : [];
        $chat = is_array($raw['chat'] ?? null) ? $raw['chat'] : null;
        $this->chatOpen = $chat === null ? null : (self::bool($chat, 'open') ?? false);
        $this->recentMessages = ChatMessage::list(self::at($raw, 'chat', 'recentMessages'));
        $this->upcomingEvents = Event::list(self::at($raw, 'events', 'upcoming'));
    }

    /** Where it is on the map, when its location has a point. */
    public function coordinate(): ?\AudienceKit\Coordinate
    {
        return $this->location?->coordinate;
    }
}
