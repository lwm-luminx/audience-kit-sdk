<?php

declare(strict_types=1);

namespace AudienceKit\Tests;

use AudienceKit\AudienceKitException;
use AudienceKit\GraphQLError;
use RuntimeException;

final class ExceptionTest extends TestCase
{
    public function testGraphQLErrorsBecomeTheFirstOnesCodeAndFields(): void
    {
        $errors = [
            GraphQLError::fromArray([
                'message' => 'Name is too short',
                'path' => ['rsvpEvent'],
                'extensions' => ['code' => 'INVALID', 'fields' => ['name' => ['too short', 7], 'state' => 'bad']],
            ]),
            GraphQLError::fromArray(['message' => 'Second']),
        ];
        $error = AudienceKitException::graphQL($errors);
        self::assertSame(AudienceKitException::CODE_INVALID, $error->errorCode);
        self::assertSame('Name is too short', $error->getMessage());
        self::assertSame(['name' => ['too short'], 'state' => ['bad']], $error->fields);
        self::assertSame($errors, $error->errors);
        self::assertSame(['rsvpEvent'], $errors[0]->path);
        self::assertNull($errors[1]->code());
        self::assertNull($errors[1]->extensions);
        self::assertFalse($error->isUndefinedField());
        self::assertFalse($error->isUnauthenticated());
    }

    public function testGraphQLErrorWithoutACode(): void
    {
        $error = AudienceKitException::graphQL([GraphQLError::fromArray([])]);
        self::assertSame(AudienceKitException::CODE_GRAPHQL, $error->errorCode);
        self::assertSame('The request failed.', $error->getMessage());
        self::assertSame(AudienceKitException::CODE_GRAPHQL, AudienceKitException::graphQL([])->errorCode);
    }

    public function testUndefinedField(): void
    {
        $error = AudienceKitException::graphQL([
            GraphQLError::fromArray(['message' => "Field 'x' doesn't exist", 'extensions' => ['code' => 'undefinedField']]),
        ]);
        self::assertTrue($error->isUndefinedField());
        self::assertSame('undefinedField', $error->errorCode);
    }

    public function testFactories(): void
    {
        self::assertSame(401, AudienceKitException::unauthorized()->status);
        self::assertTrue(AudienceKitException::unauthorized()->isUnauthenticated());
        self::assertSame(AudienceKitException::CODE_NOT_SIGNED_IN, AudienceKitException::notSignedIn()->errorCode);
        self::assertSame(401, AudienceKitException::signInRejected()->status);
        self::assertSame('Sign-in failed.', AudienceKitException::signInFailed(null)->getMessage());
        self::assertSame('Nope', AudienceKitException::signInFailed('Nope')->getMessage());
        self::assertSame('Custom', AudienceKitException::forbidden('Custom')->getMessage());
        self::assertSame(404, AudienceKitException::notFound()->status);
        self::assertSame('The server responded with status 418.', AudienceKitException::http(418)->getMessage());
        self::assertSame('TEAPOT', AudienceKitException::http(418, 'TEAPOT', 'short')->errorCode);
        $network = AudienceKitException::network(new RuntimeException('offline'));
        self::assertSame(AudienceKitException::CODE_NETWORK, $network->errorCode);
        self::assertSame('offline', $network->getPrevious()?->getMessage());
        self::assertStringContainsString('bad json', AudienceKitException::decoding('bad json')->getMessage());
        self::assertStringContainsString('needs a host', AudienceKitException::missingConfiguration('needs a host')->getMessage());
        self::assertSame(AudienceKitException::CODE_STORAGE, AudienceKitException::storage('disk')->errorCode);
        $update = AudienceKitException::updateRequired('0.50.0', null);
        self::assertSame('0.50.0', $update->minimumSdkVersion);
        self::assertSame(426, $update->status);
        self::assertSame(0, $update->getCode());
    }
}
