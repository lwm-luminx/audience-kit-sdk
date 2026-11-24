<?php

declare(strict_types=1);

namespace AudienceKit\Model;

/**
 * A Soapbox article: news a publication ran, or an op-ed a reader sent one. In a list it has its summary and teaser;
 * read on its own ({@see \AudienceKit\AudienceSession::article()}) also its body and what it's about.
 */
final class Article extends Model
{
    public readonly string $id;
    public readonly ?string $slug;
    public readonly string $title;
    public readonly ?string $summary;
    public readonly ?string $byline;
    /** "ARTICLE" or "OP_ED". */
    public readonly ?string $kind;
    public readonly ?\DateTimeImmutable $publishedAt;
    /** Whether it changed after it ran ("Updated"). */
    public readonly bool $edited;
    public readonly bool $pinned;
    /** Whether only a teaser runs here and the rest is on the publication's site ({@see $canonicalUrl}). */
    public readonly bool $teaser;
    public readonly ?string $canonicalUrl;
    /** A disclosure to show with it, e.g. a paid placement. */
    public readonly ?string $disclosure;
    public readonly ?string $heroPhotoUrl;
    public readonly ?string $heroAltText;
    public readonly ?Publication $publication;
    /** Read on its own: the body, as Markdown. */
    public readonly ?string $body;
    /** Read on its own: the venues, events, people and locales it is about, each `id name`. @var array<string, list<array<string, mixed>>> */
    public readonly array $subjects;
    /** Whether the signed-in reader tipped to read its publication without ads. */
    public readonly bool $viewerAdFree;
    /** In national news: whether the audience's admins featured it nationally. */
    public readonly bool $featuredNationally;
    /** An op-ed's review: "SUBMITTED", "DRAFT", "IN_REVIEW", "PUBLISHED", "UNPUBLISHED" or "DECLINED", with the publication's note. */
    public readonly ?string $status;
    public readonly ?string $reviewNote;
    public readonly ?\DateTimeImmutable $submittedAt;

    protected function hydrate(array $raw): void
    {
        $this->id = self::id($raw);
        $this->slug = self::string($raw, 'slug');
        $this->title = self::string($raw, 'title') ?? '';
        $this->summary = self::string($raw, 'summary');
        $this->byline = self::string($raw, 'byline');
        $this->kind = self::string($raw, 'kind');
        $this->publishedAt = self::date($raw, 'publishedAt');
        $this->edited = self::bool($raw, 'edited') ?? false;
        $this->pinned = self::bool($raw, 'pinned') ?? false;
        $this->teaser = self::bool($raw, 'teaser') ?? false;
        $this->canonicalUrl = self::string($raw, 'canonicalUrl');
        $this->disclosure = self::string($raw, 'disclosure');
        $this->heroPhotoUrl = self::string($raw, 'heroPhotoUrl');
        $this->heroAltText = self::string($raw, 'heroAltText');
        $this->publication = Publication::from($raw['publication'] ?? null);
        $this->body = self::string($raw, 'body');
        $subjects = [];
        foreach (['venues', 'events', 'people', 'locales'] as $key) {
            if (is_array($raw[$key] ?? null)) {
                $subjects[$key] = array_values(array_filter($raw[$key], 'is_array'));
            }
        }
        $this->subjects = $subjects;
        $this->viewerAdFree = self::bool($raw, 'viewerAdFree') ?? false;
        $this->featuredNationally = self::bool($raw, 'featuredNationally') ?? false;
        $this->status = self::string($raw, 'status');
        $this->reviewNote = self::string($raw, 'reviewNote');
        $this->submittedAt = self::date($raw, 'submittedAt');
    }
}
