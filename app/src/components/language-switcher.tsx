"use client";

import Link from "next/link";
import { usePathname } from "next/navigation";
import { locales, LOCALE_COOKIE, type Locale } from "@/i18n/config";
import { cn } from "@/lib/utils";

type Props = {
  current: Locale;
  label: string;
  names: Record<Locale, string>;
};

// Swaps the language prefix in the current URL (/es/... <-> /en/...)
// and remembers the choice in a cookie for the next visit.
export function LanguageSwitcher({ current, label, names }: Props) {
  const pathname = usePathname();
  const rest = pathname.replace(/^\/(es|en)(?=\/|$)/, "");

  return (
    <nav aria-label={label} className="flex items-center gap-1 text-sm">
      <span className="sr-only">{label}</span>
      {locales.map((locale) => (
        <Link
          key={locale}
          href={`/${locale}${rest}`}
          hrefLang={locale}
          aria-current={locale === current ? "true" : undefined}
          onClick={() => {
            document.cookie = `${LOCALE_COOKIE}=${locale}; path=/; max-age=31536000; samesite=lax`;
          }}
          className={cn(
            "rounded-md px-3 py-1.5 transition-colors",
            locale === current
              ? "bg-primary text-primary-foreground"
              : "text-muted-foreground hover:bg-muted hover:text-foreground",
          )}
        >
          {names[locale]}
        </Link>
      ))}
    </nav>
  );
}
