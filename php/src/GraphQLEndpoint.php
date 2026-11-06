<?php

declare(strict_types=1);

namespace AudienceKit;

/**
 * Which of an audience's GraphQL endpoints a request goes to: its path segment under `/v1/audience/<id>/`. This SDK
 * speaks to the consumer view ({@see CONSUMER}), which grants a signed-in member their own records and nothing more.
 */
final class GraphQLEndpoint
{
    /** `/v1/audience/<id>/graphql`, for the apps people use. */
    public const CONSUMER = 'graphql';

    /** The endpoint's path for an audience. */
    public static function path(string $audienceId, string $endpoint = self::CONSUMER): string
    {
        return '/v1/audience/' . rawurlencode($audienceId) . '/' . $endpoint;
    }

    private function __construct()
    {
    }
}
