import { NextResponse, type NextRequest } from "next/server";
import { defaultLocale, hasLocale, locales, LOCALE_COOKIE, type Locale } from "@/i18n/config";

// Every page lives under /es/... or /en/...
// A request without a language (e.g. "/") is redirected to:
//   1. the language the user picked before (cookie), else
//   2. the first supported language in the browser's Accept-Language, else
//   3. Spanish.
function pickLocale(request: NextRequest): Locale {
  const saved = request.cookies.get(LOCALE_COOKIE)?.value;
  if (hasLocale(saved)) return saved;

  const header = request.headers.get("accept-language") ?? "";
  const preferred = header
    .split(",")
    .map((part) => {
      const [tag, q] = part.trim().split(";q=");
      return { lang: tag.toLowerCase().split("-")[0], q: q ? Number(q) : 1 };
    })
    .sort((a, b) => b.q - a.q);

  for (const { lang } of preferred) {
    if (hasLocale(lang)) return lang;
  }
  return defaultLocale;
}

export function proxy(request: NextRequest) {
  const { pathname } = request.nextUrl;
  const hasPrefix = locales.some(
    (locale) => pathname === `/${locale}` || pathname.startsWith(`/${locale}/`),
  );
  if (hasPrefix) return;

  const url = request.nextUrl.clone();
  url.pathname = `/${pickLocale(request)}${pathname === "/" ? "" : pathname}`;
  return NextResponse.redirect(url);
}

export const config = {
  // Skip Next.js internals, API routes and files with an extension (images, favicon...)
  matcher: ["/((?!_next|api|.*\\..*).*)"],
};
