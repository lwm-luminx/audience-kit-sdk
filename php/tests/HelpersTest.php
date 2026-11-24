<?php

declare(strict_types=1);

namespace AudienceKit\Tests;

use AudienceKit\Color;
use AudienceKit\Coordinate;
use AudienceKit\CoverPass;
use PHPUnit\Framework\TestCase as BaseTestCase;

final class HelpersTest extends BaseTestCase
{
    public function testCoordinateFromWkt(): void
    {
        $point = Coordinate::fromWkt('SRID=4326;POINT (-111.891 40.7608)');
        self::assertNotNull($point);
        self::assertSame(40.7608, $point->latitude);
        self::assertSame(-111.891, $point->longitude);
        self::assertSame('POINT (-111.891 40.7608)', $point->toWkt());
        self::assertNull(Coordinate::fromWkt('LINESTRING (1 2, 3 4)'));
        self::assertNull(Coordinate::fromWkt('POINT (1)'));
        self::assertNull(Coordinate::fromWkt('POINT 1 2'));
        self::assertNull(Coordinate::fromWkt('POINT (40.7 -111.9)'), 'swapped');
        self::assertSame('POINT (0 0)', (new Coordinate(-0.0, 0.0))->toWkt());
    }

    public function testCoordinateInputAndDistance(): void
    {
        self::assertSame(['latitude' => 1.5, 'longitude' => 2.5], (new Coordinate(1.5, 2.5, 0, 0))->toInput());
        self::assertSame(
            ['latitude' => 1.5, 'longitude' => 2.5, 'beaconMajor' => 7, 'beaconMinor' => 9],
            (new Coordinate(1.5, 2.5, 7, 9))->toInput(),
        );
        $slc = new Coordinate(40.7608, -111.8910);
        $ogden = new Coordinate(41.2230, -111.9738);
        self::assertEqualsWithDelta(51_800, $slc->distanceTo($ogden), 1_000);
        self::assertSame(0.0, $slc->distanceTo($slc));
    }

    public function testColor(): void
    {
        $color = Color::fromHex('#f36');
        self::assertNotNull($color);
        self::assertSame('rgba(255, 51, 102, 1)', $color->toCss());
        self::assertSame('#ff3366', $color->toHex());
        self::assertSame('#ff336680', Color::fromHex('ff336680')?->toHex());
        self::assertSame('rgba(255, 51, 102, 0.502)', Color::fromHex('ff336680')?->toCss());
        self::assertNull(Color::fromHex('#ff33'));
        self::assertNull(Color::fromHex('#gggggg'));
    }

    public function testThemeColors(): void
    {
        $graphQL = ['light' => [['name' => 'accent', 'value' => '#000000']], 'dark' => [['name' => 'accent', 'value' => '#ffffff']]];
        self::assertSame('#000000', Color::fromTheme($graphQL, 'accent')?->toHex());
        self::assertSame('#ffffff', Color::fromTheme($graphQL, 'accent', true)?->toHex());
        $rest = ['light' => ['accent' => '#112233'], 'dark' => []];
        self::assertSame('#112233', Color::fromTheme($rest, 'accent', true)?->toHex(), 'falls back to light');
        self::assertNull(Color::fromTheme($rest, 'missing'));
        self::assertNull(Color::fromTheme(null, 'accent'));
        self::assertNull(Color::fromTheme(['light' => 'nope'], 'accent'));
    }

    public function testCoverPassMatchesTheOtherSdks(): void
    {
        // Checked against Node's crypto.createHmac(...).digest("base64url"), as the Node SDK makes it.
        $secret = base64_encode('secret');
        self::assertSame(56_666_666, CoverPass::window(1_700_000_000));
        $code = CoverPass::code('adm-1', $secret, 1_700_000_000);
        self::assertSame('HMC1.adm-1.56666666.bmA9NusAR0IH-aMT', $code);
        self::assertSame($code, CoverPass::code('adm-1', $secret, 1_700_000_009));
        self::assertNotSame($code, CoverPass::code('adm-1', $secret, 1_700_000_010));
        self::assertSame(16, strlen(explode('.', $code)[3]));
        self::assertTrue(CoverPass::isCode($code));
        self::assertTrue(CoverPass::isCode(CoverPass::code('adm-1', $secret)));
        self::assertFalse(CoverPass::isCode('HMC1.adm-1.x.sig'));
        self::assertFalse(CoverPass::isCode('XYZ1.adm-1.1.sig'));
        self::assertFalse(CoverPass::isCode('HMC1..1.sig'));
        self::assertSame(-1, CoverPass::window(-1));
        self::assertSame(10, CoverPass::secondsUntilNextWindow(1_700_000_000));
        self::assertSame(30, CoverPass::secondsUntilNextWindow(30));
    }
}
