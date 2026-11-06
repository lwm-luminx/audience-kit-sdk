<?php

declare(strict_types=1);

namespace AudienceKit;

use Http\Discovery\Psr17FactoryDiscovery;
use Http\Discovery\Psr18ClientDiscovery;
use InvalidArgumentException;
use JsonException;
use Psr\Http\Client\ClientExceptionInterface;
use Psr\Http\Client\ClientInterface;
use Psr\Http\Message\RequestFactoryInterface;
use Psr\Http\Message\ResponseInterface;
use Psr\Http\Message\StreamFactoryInterface;
use Throwable;

/**
 * Talks to the AudienceKit API on behalf of one audience and one signed-in person.
 *
 * Sign in with a Facebook or Apple token the app obtained, or {@see adopt()} a credential minted elsewhere (a venue
 * device's, one the platform console handed over). After that, every call carries the session token as
 * `Authorization: Bearer <token>` and the API contract version as `X-AudienceKit-API-Version`. When the API rejects
 * the token, the call throws {@see AudienceKitException::unauthorized()} and the credential is forgotten.
 *
 * HTTP goes through any PSR-18 client with PSR-17 factories; when none is given, php-http/discovery finds the ones
 * installed (Guzzle, Symfony's HTTP client, ...).
 */
class AudienceSession
{
    use Operations;

    private readonly ClientInterface $http;
    private readonly RequestFactoryInterface $requests;
    private readonly StreamFactoryInterface $streams;
    private ?string $resolvedAudienceId = null;
    /** @var array<string, list<string>> The fields each type has, by "audience|endpoint|type" ({@see schemaFields()}). */
    private array $schemaFieldCache = [];

    public function __construct(
        public readonly Configuration $configuration = new Configuration(),
        private readonly CredentialStore $credentialStore = new InMemoryCredentialStore(),
        ?ClientInterface $http = null,
        ?RequestFactoryInterface $requests = null,
        ?StreamFactoryInterface $streams = null,
    ) {
        $this->http = $http ?? Psr18ClientDiscovery::find();
        $this->requests = $requests ?? Psr17FactoryDiscovery::findRequestFactory();
        $this->streams = $streams ?? Psr17FactoryDiscovery::findStreamFactory();
    }

    // Session

    /** Whether a credential is stored. It may still be rejected by the API. */
    public function isSignedIn(): bool
    {
        return $this->loadCredential() !== null;
    }

    /** The stored credential: who is signed in, to which audience, and the token. Never log the token. */
    public function credential(): ?Credential
    {
        return $this->loadCredential();
    }

    /** The stored session token, for the rare connection the SDK doesn't make itself. */
    public function sessionToken(): ?string
    {
        return $this->loadCredential()?->token;
    }

    /**
     * Exchanges a Facebook user access token for an AudienceKit session and stores it. Sends the configured host and
     * Facebook app ID so the API checks the token against the right Facebook app and binds the session to the
     * audience.
     */
    public function signInWithFacebookToken(string $accessToken, DeviceDescription $device): Credential
    {
        return $this->signIn('/v1/token', $this->facebookBody(['facebook_token' => $accessToken], $device), false);
    }

    /**
     * Exchanges the code from Facebook's OAuth dialog for an AudienceKit session and stores it. The API trades the
     * code for a token with the app secret, so `$redirectUri` must be exactly the one the dialog was opened with.
     */
    public function signInWithFacebookCode(string $code, string $redirectUri, DeviceDescription $device): Credential
    {
        $body = $this->facebookBody(['code' => $code, 'redirect_uri' => $redirectUri], $device);

        return $this->signIn('/v1/token', $body, false);
    }

    /**
     * Exchanges a Sign in with Apple identity token for an AudienceKit session and stores it. Apple gives the
     * person's name only the first time they sign in; pass it then so the account has one.
     */
    public function signInWithAppleIdentityToken(
        string $identityToken,
        DeviceDescription $device,
        ?string $firstName = null,
        ?string $lastName = null,
    ): Credential {
        $body = array_filter([
            'identity_token' => $identityToken,
            'first_name' => $firstName,
            'last_name' => $lastName,
            'host' => $this->configuration->host,
            'device' => $device->toArray(),
        ], static fn ($value) => $value !== null);

        return $this->signIn('/v1/token/apple', $body, false);
    }

    /**
     * Connects Facebook to the signed-in account (one that signed in with Apple), with the code from Facebook's
     * OAuth dialog, and stores the new session the API returns.
     */
    public function connectFacebook(string $code, string $redirectUri, DeviceDescription $device): Credential
    {
        $body = $this->facebookBody(['code' => $code, 'redirect_uri' => $redirectUri, 'connect' => true], $device);

        return $this->signIn('/v1/token', $body, true);
    }

    /**
     * Makes `$credential` the session: one minted outside the SDK (a service token, a venue device's) or one the
     * app stored itself. From now on GraphQL goes to the API instance the credential's `endpoint` names, for its
     * `audienceId`.
     */
    public function adopt(Credential $credential): void
    {
        $this->store($credential);
    }

    /**
     * Moves the session to another audience and returns its credential, which is stored and in use when this
     * returns (`POST /v1/admin/choices`). The API allows it for platform-console sessions; anyone else gets
     * {@see AudienceKitException::CODE_FORBIDDEN}.
     */
    public function switchAudience(string $audienceId): Credential
    {
        $data = $this->request(new ApiRequest('/v1/admin/choices', 'POST', body: ['audience_id' => $audienceId]));
        $credential = $this->decodeCredential($data);
        $this->store($credential);

        return $credential;
    }

    /**
     * Ends the session: forgets the credential, then revokes the token with `DELETE /v1/token` so it stops working
     * everywhere. The credential is forgotten even when that call fails; a 401 or 404 (the session was already
     * gone) is not an error.
     */
    public function signOut(): void
    {
        $credential = $this->loadCredential();
        try {
            $this->credentialStore->delete();
        } catch (Throwable) {
            // The token is revoked below either way.
        }
        $this->resolvedAudienceId = null;
        $this->schemaFieldCache = [];
        if ($credential === null) {
            return;
        }

        $response = $this->perform(new ApiRequest('/v1/token', 'DELETE'), $credential->token);
        $status = $response->getStatusCode();
        if (($status >= 200 && $status < 300) || $status === 401 || $status === 404) {
            return;
        }
        throw $this->errorForStatus($status, (string) $response->getBody());
    }

    /**
     * Ends the session because the API refused `$token` on a connection the SDK didn't make itself. Forgets the
     * credential, once: when the store no longer holds `$token` it does nothing and returns false.
     */
    public function sessionRejected(?string $token): bool
    {
        $stored = $this->loadCredential();
        if ($token === null || $stored === null || $stored->token !== $token) {
            return false;
        }
        try {
            $this->credentialStore->delete();
        } catch (Throwable) {
            // Nothing more to do: the next load fails the same way.
        }
        $this->resolvedAudienceId = null;
        $this->schemaFieldCache = [];

        return true;
    }

    // Branding

    /**
     * The audience's public branding for the configured host (or `$host`). No sign-in needed. Pass `$app` (a bundle
     * ID) to have it carry that app's release config too.
     *
     * @return array<string, mixed>
     */
    public function branding(?string $host = null, ?string $app = null): array
    {
        $host ??= $this->configuration->host;
        if ($host === null) {
            throw AudienceKitException::missingConfiguration('branding needs a host');
        }
        $query = ['host' => $host];
        if ($app !== null && $app !== '') {
            $query['app'] = $app;
        }

        return $this->decodeObject($this->request(new ApiRequest('/v1/branding', query: $query, authenticated: false)));
    }

    // Audience

    /**
     * The audience this client queries: the stored credential's `audienceId`, else the configured ID, else the
     * audience that owns the configured host.
     */
    public function audienceId(): string
    {
        $id = $this->loadCredential()?->audienceId ?? $this->configuration->audienceId ?? $this->resolvedAudienceId;
        if ($id !== null) {
            return $id;
        }
        if ($this->configuration->host === null) {
            throw AudienceKitException::missingConfiguration('set an audienceId or a host');
        }
        $id = $this->branding()['audience']['id'] ?? null;
        if (!is_string($id)) {
            throw AudienceKitException::decoding('The branding had no audience id.');
        }
        $this->resolvedAudienceId = $id;

        return $id;
    }

    // GraphQL

    /**
     * Runs a GraphQL operation against the audience's endpoint and returns its `data`, decoded to arrays.
     *
     * The request goes to the API instance the stored credential's `endpoint` names (the configured base URL before
     * sign-in), at the audience's endpoint path. Throws {@see AudienceKitException::graphQL()} when the response
     * carries errors, even alongside data.
     *
     * @param array<string, mixed>|null $variables
     * @return array<string, mixed>
     */
    public function graphQL(
        string $query,
        ?array $variables = null,
        ?string $operationName = null,
        string $endpoint = GraphQLEndpoint::CONSUMER,
    ): array {
        $credential = $this->loadCredential();
        $audienceId = $this->audienceId();
        $body = ['query' => $query];
        if ($variables !== null) {
            $body['variables'] = $variables;
        }
        if ($operationName !== null) {
            $body['operationName'] = $operationName;
        }
        [$type, $name] = self::describe($query, $operationName);
        // Apollo's operation headers, which New Relic's agents record with each request.
        $headers = ['X-APOLLO-OPERATION-TYPE' => $type];
        if ($name !== null) {
            $headers['X-APOLLO-OPERATION-NAME'] = $name;
        }
        $request = new ApiRequest(GraphQLEndpoint::path($audienceId, $endpoint), 'POST', body: $body, headers: $headers);

        $json = $this->decodeObject($this->request($request, $this->configuration->apiBase($credential)));
        // Errors first: a refused mutation comes back as `{"errors":[…],"data":{"field":null}}`.
        if (isset($json['errors']) && is_array($json['errors']) && $json['errors'] !== []) {
            $errors = [];
            foreach ($json['errors'] as $error) {
                $errors[] = GraphQLError::fromArray(is_array($error) ? $error : []);
            }
            throw AudienceKitException::graphQL($errors);
        }
        if (!isset($json['data']) || !is_array($json['data'])) {
            throw AudienceKitException::decoding('The response had no data.');
        }

        return $json['data'];
    }

    /**
     * Runs the operation `$document` builds, first for an audience with every module; when the API refuses a field
     * (`undefinedField`), it asks the schema which fields `$types` have and runs it again with only those. The
     * answer is cached for the session, so later operations go straight to the right document.
     *
     * @param list<string>                     $types
     * @param callable(SchemaShape): string    $document
     * @param array<string, mixed>|null        $variables
     * @return array<string, mixed>
     */
    public function shapedGraphQL(array $types, callable $document, ?array $variables, string $operationName): array
    {
        $known = $this->cachedSchemaFields($types);
        if ($known !== null) {
            return $this->graphQL($document(new SchemaShape($known)), $variables, $operationName);
        }
        try {
            return $this->graphQL($document(SchemaShape::everything()), $variables, $operationName);
        } catch (AudienceKitException $error) {
            if (!$error->isUndefinedField()) {
                throw $error;
            }
            $shape = new SchemaShape($this->schemaFields($types));

            return $this->graphQL($document($shape), $variables, $operationName);
        }
    }

    /**
     * The fields each of `$types` has in the audience's schema (introspection), by type name; a type the schema
     * doesn't have is left out. Cached for the session (until sign-in or sign-out).
     *
     * @param list<string> $types
     * @return array<string, list<string>>
     */
    public function schemaFields(array $types, string $endpoint = GraphQLEndpoint::CONSUMER): array
    {
        $prefix = $this->audienceId() . '|' . $endpoint . '|';
        $missing = array_values(array_unique(array_filter(
            $types,
            fn (string $type) => !array_key_exists($prefix . $type, $this->schemaFieldCache),
        )));
        sort($missing);
        if ($missing !== []) {
            $selections = [];
            foreach ($missing as $index => $name) {
                $selections[] = "t$index: __type(name: \"$name\") { fields(includeDeprecated: true) { name } }";
            }
            $result = $this->graphQL(
                'query SchemaFields { ' . implode(' ', $selections) . ' }',
                null,
                'SchemaFields',
                $endpoint,
            );
            foreach ($missing as $index => $name) {
                $fields = [];
                foreach ($result["t$index"]['fields'] ?? [] as $field) {
                    if (isset($field['name']) && is_string($field['name'])) {
                        $fields[] = $field['name'];
                    }
                }
                $this->schemaFieldCache[$prefix . $name] = $fields;
            }
        }

        return $this->shapeFromCache($prefix, $types);
    }

    /**
     * {@see schemaFields()}'s answer when the session already has it for every one of `$types`, without asking the
     * API; null otherwise.
     *
     * @param list<string> $types
     * @return array<string, list<string>>|null
     */
    public function cachedSchemaFields(array $types, string $endpoint = GraphQLEndpoint::CONSUMER): ?array
    {
        try {
            $prefix = $this->audienceId() . '|' . $endpoint . '|';
        } catch (AudienceKitException) {
            return null;
        }
        foreach ($types as $type) {
            if (!array_key_exists($prefix . $type, $this->schemaFieldCache)) {
                return null;
            }
        }

        return $this->shapeFromCache($prefix, $types);
    }

    // REST

    /** Sends a request to a REST endpoint and returns the body of a successful response. */
    public function request(ApiRequest $request, ?string $baseUrl = null): string
    {
        $token = null;
        if ($request->authenticated) {
            $stored = $this->loadCredential();
            if ($stored === null) {
                throw AudienceKitException::notSignedIn();
            }
            $token = $stored->token;
        }

        $response = $this->perform($request, $token, $baseUrl);
        $status = $response->getStatusCode();
        $body = (string) $response->getBody();
        if ($status >= 200 && $status < 300) {
            return $body;
        }
        if ($status === 401 && $token !== null) {
            $this->sessionRejected($token);
            throw AudienceKitException::unauthorized();
        }
        throw $this->errorForStatus($status, $body);
    }

    /** Resolves a URL the API sent (absolute, or a path relative to the base URL). */
    public function url(?string $string): ?string
    {
        if ($string === null || $string === '') {
            return null;
        }
        if (parse_url($string, PHP_URL_SCHEME) !== null) {
            return $string;
        }

        return rtrim($this->configuration->baseUrl, '/') . '/' . ltrim($string, '/');
    }

    // Private

    /** @param array<string, mixed> $body */
    private function signIn(string $path, array $body, bool $authenticated): Credential
    {
        $request = new ApiRequest($path, 'POST', body: $body, authenticated: $authenticated);
        $token = $authenticated ? $this->loadCredential()?->token : null;
        if ($authenticated && $token === null) {
            throw AudienceKitException::notSignedIn();
        }
        $response = $this->perform($request, $token);
        $status = $response->getStatusCode();
        $data = (string) $response->getBody();

        if ($status === 401) {
            throw AudienceKitException::signInRejected();
        }
        if ($status === 400) {
            $fault = self::restErrorBody($data);
            if (($fault['error'] ?? null) !== AudienceKitException::UNSUPPORTED_API_VERSION_ERROR) {
                throw AudienceKitException::signInFailed($fault['message'] ?? $fault['fault']['message'] ?? null);
            }
        }
        if ($status < 200 || $status >= 300) {
            throw $this->errorForStatus($status, $data);
        }

        $credential = $this->decodeCredential($data);
        $this->store($credential);

        return $credential;
    }

    /**
     * @param array<string, mixed> $fields
     * @return array<string, mixed>
     */
    private function facebookBody(array $fields, DeviceDescription $device): array
    {
        return array_filter($fields + [
            'host' => $this->configuration->host,
            'facebook_app_id' => $this->configuration->facebookAppId,
            'device' => $device->toArray(),
        ], static fn ($value) => $value !== null);
    }

    private function store(Credential $credential): void
    {
        try {
            $this->credentialStore->save($credential);
        } catch (Throwable $error) {
            throw AudienceKitException::storage($error->getMessage(), $error);
        }
        $this->resolvedAudienceId = null;
        $this->schemaFieldCache = [];
    }

    private function loadCredential(): ?Credential
    {
        try {
            return $this->credentialStore->load();
        } catch (Throwable) {
            return null;
        }
    }

    /**
     * @param list<string> $types
     * @return array<string, list<string>>
     */
    private function shapeFromCache(string $prefix, array $types): array
    {
        $shape = [];
        foreach ($types as $type) {
            $fields = $this->schemaFieldCache[$prefix . $type] ?? [];
            if ($fields !== []) {
                $shape[$type] = $fields;
            }
        }

        return $shape;
    }

    /** Sends `$request` to `$baseUrl` (the configured one by default), with `$token` when it's authenticated. */
    private function perform(ApiRequest $request, ?string $token = null, ?string $baseUrl = null): ResponseInterface
    {
        $url = rtrim($baseUrl ?? $this->configuration->baseUrl, '/') . '/' . ltrim($request->path, '/');
        if ($request->query !== []) {
            $url .= '?' . http_build_query($request->query, '', '&', PHP_QUERY_RFC3986);
        }

        $http = $this->requests->createRequest($request->method, $url)
            ->withHeader('Accept', 'application/json')
            ->withHeader(AudienceKit::CLIENT_HEADER, AudienceKit::clientHeader())
            ->withHeader(AudienceKit::API_VERSION_HEADER, AudienceKit::API_VERSION);
        if ($this->configuration->environment !== Environment::PRODUCTION) {
            $http = $http->withHeader(Environment::HEADER, $this->configuration->environment);
        }
        $bearer = $request->authenticated ? ($token ?? $this->loadCredential()?->token) : null;
        if ($bearer !== null) {
            $http = $http->withHeader('Authorization', 'Bearer ' . $bearer);
        }
        foreach ($request->headers as $name => $value) {
            $http = $http->withHeader($name, $value);
        }
        if ($request->body !== null) {
            try {
                $json = json_encode($request->body, JSON_THROW_ON_ERROR | JSON_UNESCAPED_SLASHES | JSON_UNESCAPED_UNICODE);
            } catch (JsonException $error) {
                throw new AudienceKitException(
                    AudienceKitException::CODE_INVALID,
                    'The request body is not JSON: ' . $error->getMessage(),
                    previous: $error,
                );
            }
            $http = $http->withHeader('Content-Type', 'application/json')
                ->withBody($this->streams->createStream($json));
        }

        try {
            return $this->http->sendRequest($http);
        } catch (ClientExceptionInterface $error) {
            throw AudienceKitException::network($error);
        }
    }

    /**
     * The error for an unsuccessful REST status, reading the API's `{ "error": "<code>", "message": "…" }` body
     * when it sent one.
     */
    private function errorForStatus(int $status, string $data): AudienceKitException
    {
        $body = self::restErrorBody($data);
        $message = $body['message'] ?? $body['fault']['message'] ?? null;
        $message = is_string($message) ? $message : null;
        $error = $body['error'] ?? null;
        $error = is_string($error) ? $error : null;

        switch (true) {
            case $status === 401:
                return AudienceKitException::unauthorized();
            case $status === 403:
                return AudienceKitException::forbidden($message);
            case $status === 404:
                return AudienceKitException::notFound($message);
            case $status === 400 && $error === AudienceKitException::UNSUPPORTED_API_VERSION_ERROR:
                $text = $message ?? 'This version of the app is out of date. Update it to keep going.';
                $supported = $body['supported'] ?? null;
                if (is_array($supported) && $supported !== []) {
                    $text .= ' (API versions served: ' . implode(', ', $supported) . '.)';
                }

                return new AudienceKitException(AudienceKitException::CODE_UNSUPPORTED_API_VERSION, $text, 400);
            case $status === 426:
                $minimum = $body['minimum_sdk_version'] ?? '';

                return AudienceKitException::updateRequired(is_string($minimum) ? $minimum : '', $message);
            default:
                $codes = [
                    400 => AudienceKitException::CODE_INVALID,
                    409 => AudienceKitException::CODE_CONFLICT,
                    422 => AudienceKitException::CODE_INVALID,
                    429 => AudienceKitException::CODE_RATE_LIMITED,
                ];
                $code = $error !== null ? strtoupper($error) : ($codes[$status] ?? null);
                if ($code === null && $status >= 500) {
                    $code = AudienceKitException::CODE_INTERNAL;
                }

                return AudienceKitException::http($status, $code, $message);
        }
    }

    /** @return array<string, mixed> */
    private static function restErrorBody(string $data): array
    {
        $decoded = json_decode($data, true);

        return is_array($decoded) ? $decoded : [];
    }

    /** @return array<string, mixed> */
    private function decodeObject(string $data): array
    {
        try {
            $decoded = json_decode($data, true, 512, JSON_THROW_ON_ERROR);
        } catch (JsonException $error) {
            throw AudienceKitException::decoding($error->getMessage());
        }
        if (!is_array($decoded)) {
            throw AudienceKitException::decoding('The response was not a JSON object.');
        }

        return $decoded;
    }

    private function decodeCredential(string $data): Credential
    {
        try {
            return Credential::fromArray($this->decodeObject($data));
        } catch (InvalidArgumentException $error) {
            throw AudienceKitException::decoding($error->getMessage());
        }
    }

    /**
     * An operation's type and name, from its document (or `$operationName`), for the monitoring headers.
     *
     * @return array{string, string|null}
     */
    public static function describe(string $query, ?string $operationName): array
    {
        $type = 'query';
        $name = $operationName;
        if (preg_match('/^\s*(query|mutation|subscription)\b\s*([A-Za-z_][A-Za-z0-9_]*)?/', $query, $match) === 1) {
            $type = $match[1];
            $name ??= $match[2] ?? null;
            if ($name === '') {
                $name = null;
            }
        }

        return [$type, $name];
    }
}
