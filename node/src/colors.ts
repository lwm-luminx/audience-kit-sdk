import type { BrandingTheme } from "./models.js";

/** A color parsed from a `#rgb`, `#rrggbb` or `#rrggbbaa` hex string, with components from 0 to 1. */
export interface RGBAColor {
  red: number;
  green: number;
  blue: number;
  alpha: number;
}

export function colorFromHex(hex: string): RGBAColor | null {
  let digits = hex.trim().replace(/^#/, "");
  if (digits.length === 3) digits = [...digits].map((d) => d + d).join("");
  if (digits.length !== 6 && digits.length !== 8) return null;
  if (!/^[0-9a-fA-F]+$/.test(digits)) return null;
  const value = parseInt(digits, 16);
  const rgba = digits.length === 6 ? value * 0x100 + 0xff : value;
  return {
    red: Math.floor(rgba / 0x1000000) / 255,
    green: (Math.floor(rgba / 0x10000) & 0xff) / 255,
    blue: (Math.floor(rgba / 0x100) & 0xff) / 255,
    alpha: (rgba & 0xff) / 255,
  };
}

/** A color as CSS `rgba(r, g, b, a)`. */
export function colorToCss(color: RGBAColor): string {
  const channel = (value: number) => Math.round(Math.min(1, Math.max(0, value)) * 255);
  return `rgba(${channel(color.red)}, ${channel(color.green)}, ${channel(color.blue)}, ${Math.min(1, Math.max(0, color.alpha))})`;
}

/** The value of a branding theme token, preferring the dark override in dark mode. */
export function themeColor(theme: BrandingTheme | undefined, token: string, dark = false): RGBAColor | null {
  const hex = dark ? (theme?.dark?.[token] ?? theme?.light?.[token]) : theme?.light?.[token];
  return hex ? colorFromHex(hex) : null;
}
