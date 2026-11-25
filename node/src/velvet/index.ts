// Velvet on TVs that run JavaScript (Samsung TVs on Tizen): the venue device sign-in, its GraphQL and cable, and the
// board the Velvet cast receiver draws. `import { Velvet } from "audience-kit"`.
export * from "./time.js";
export * from "./board.js";
export * from "./cable.js";
export * from "./device.js";
export * as Queries from "./queries.js";

/** What a Samsung TV says it is when it pairs; the API makes it a SAMSUNG_TV display. */
export const TIZEN_PLATFORM = "tizen";
export const SAMSUNG_TV_KIND = "SAMSUNG_TV";
