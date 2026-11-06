import { readFileSync } from "node:fs";
import { describe, expect, it } from "vitest";
import { AudienceKitSDK } from "../src/index.js";

describe("the package version", () => {
  it("matches the constant the SDK sends", () => {
    const pkg = JSON.parse(readFileSync(new URL("../package.json", import.meta.url), "utf8")) as { version: string };
    expect(AudienceKitSDK.VERSION).toBe(pkg.version);
  });
});
