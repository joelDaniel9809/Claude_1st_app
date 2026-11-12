// Languages the app supports. Safe to import from client and server code.

export const locales = ["es", "en"] as const;
export type Locale = (typeof locales)[number];

// Spanish first: the pilot clinics are Hispanic.
export const defaultLocale: Locale = "es";

// Cookie that remembers the language a visitor picked.
export const LOCALE_COOKIE = "locale";

export function hasLocale(value: string | undefined | null): value is Locale {
  return !!value && (locales as readonly string[]).includes(value);
}

// Formatting locales for dates, numbers and money (US clinics, USD).
export const intlLocale: Record<Locale, string> = {
  es: "es-US",
  en: "en-US",
};
