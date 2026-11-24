<?php

declare(strict_types=1);

namespace AudienceKit\Tests;

use AudienceKit\Credential;
use AudienceKit\SessionCredentialStore;
use RuntimeException;

final class SessionStoreTest extends TestCase
{
    public function testKeepsTheCredentialInTheGivenStorage(): void
    {
        $storage = [];
        $store = new SessionCredentialStore('ak', $storage);
        self::assertNull($store->load());
        $store->save($this->credential());
        self::assertSame('secret-token', $storage['ak']['token']);
        self::assertSame('secret-token', $store->load()?->token);
        $storage['ak'] = ['token' => 'no endpoint'];
        self::assertNull($store->load(), 'a damaged entry is no session');
        $store->delete();
        self::assertArrayNotHasKey('ak', $storage);
    }

    public function testSignsInThroughTheStore(): void
    {
        $storage = [];
        $this->respond(['token' => 't2', 'userId' => 'u', 'role' => 'member', 'endpoint' => self::ENDPOINT]);
        $session = $this->session(null, new SessionCredentialStore(storage: $storage));
        $session->adopt(new Credential('t1', 'u', self::AUDIENCE_ID, 'member', self::ENDPOINT));
        self::assertSame('t1', $storage['audiencekit.credential']['token']);
        $session->refreshSession();
        self::assertSame('t2', $storage['audiencekit.credential']['token']);
    }

    public function testUsesPhpsSession(): void
    {
        $store = new SessionCredentialStore();
        try {
            $store->load();
            self::fail('Expected an exception.');
        } catch (RuntimeException $error) {
            self::assertStringContainsString('session_start()', $error->getMessage());
        }
        $_SESSION = [];
        session_id('audiencekit-test');
        @session_start(['use_cookies' => 0, 'cache_limiter' => '']);
        try {
            $store->save($this->credential());
            self::assertSame('secret-token', $_SESSION['audiencekit.credential']['token']);
            self::assertSame('secret-token', $store->load()?->token);
            $store->delete();
            self::assertNull($store->load());
        } finally {
            session_destroy();
        }
    }
}
