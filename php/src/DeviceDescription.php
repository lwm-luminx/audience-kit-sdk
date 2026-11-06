<?php

declare(strict_types=1);

namespace AudienceKit;

/** The device a session is created on. The API records it alongside the session. */
final class DeviceDescription
{
    /**
     * @param string      $identifier A stable identifier for this install or server.
     * @param string      $type       `web` for a server or browser client.
     * @param string|null $model      The hardware model, when there is one.
     * @param string|null $version    The app's marketing version.
     * @param string|null $build      The app's build number.
     */
    public function __construct(
        public readonly string $identifier,
        public readonly string $type = 'web',
        public readonly ?string $model = null,
        public readonly ?string $version = null,
        public readonly ?string $build = null,
    ) {
    }

    /** @return array<string, string> */
    public function toArray(): array
    {
        return array_filter([
            'identifier' => $this->identifier,
            'type' => $this->type,
            'model' => $this->model,
            'version' => $this->version,
            'build' => $this->build,
        ], static fn ($value) => $value !== null);
    }
}
