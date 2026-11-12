import { Suspense } from "react";
import { CircleCheck, CircleAlert, Wallet, Receipt, FileText, ChartColumn } from "lucide-react";
import { Card, CardContent, CardDescription, CardHeader, CardTitle } from "@/components/ui/card";
import { LanguageSwitcher } from "@/components/language-switcher";
import { getDictionary, getLocale, type Dictionary } from "@/i18n/get-dictionary";
import { getSystemStatus } from "@/server/system-status";

export default async function HomePage() {
  const [dict, locale] = await Promise.all([getDictionary(), getLocale()]);

  const features = [
    { icon: Wallet, text: dict.home.features.moneyIn },
    { icon: Receipt, text: dict.home.features.moneyOut },
    { icon: FileText, text: dict.home.features.bills },
    { icon: ChartColumn, text: dict.home.features.reports },
  ];

  return (
    <div className="flex flex-1 flex-col">
      <header className="border-b">
        <div className="mx-auto flex w-full max-w-5xl items-center justify-between gap-4 px-4 py-3">
          <span className="text-lg font-semibold">{dict.app.name}</span>
          <LanguageSwitcher
            current={locale}
            label={dict.language.label}
            names={{ es: dict.language.es, en: dict.language.en }}
          />
        </div>
      </header>

      <main className="mx-auto grid w-full max-w-5xl flex-1 content-start items-start gap-6 px-4 py-8 md:grid-cols-3">
        <Card className="md:col-span-2">
          <CardHeader>
            <CardTitle className="text-2xl">{dict.home.welcomeTitle}</CardTitle>
            <CardDescription className="text-base">{dict.app.tagline}</CardDescription>
          </CardHeader>
          <CardContent className="space-y-4">
            <p className="text-base leading-relaxed">{dict.home.welcomeText}</p>
            <h2 className="font-medium">{dict.home.whatNext}</h2>
            <ul className="grid gap-3 sm:grid-cols-2">
              {features.map(({ icon: Icon, text }) => (
                <li key={text} className="flex items-center gap-3 rounded-lg border p-3">
                  <Icon className="size-5 shrink-0 text-primary" aria-hidden />
                  <span>{text}</span>
                </li>
              ))}
            </ul>
          </CardContent>
        </Card>

        <Card>
          <CardHeader>
            <CardTitle>{dict.status.title}</CardTitle>
          </CardHeader>
          <CardContent>
            <Suspense fallback={<p className="text-muted-foreground">{dict.status.checking}</p>}>
              <SystemStatusPanel dict={dict} />
            </Suspense>
          </CardContent>
        </Card>
      </main>
    </div>
  );
}

// Reads the database at request time, so it streams in behind <Suspense>.
async function SystemStatusPanel({ dict }: { dict: Dictionary }) {
  const status = await getSystemStatus();

  if (!status.ok) {
    return (
      <div role="alert" className="space-y-2">
        <p className="flex items-center gap-2 font-medium text-destructive">
          <CircleAlert className="size-5" aria-hidden /> {dict.status.dbError}
        </p>
        <p className="text-sm text-muted-foreground">{dict.status.dbErrorHelp}</p>
      </div>
    );
  }

  const rows = [
    [dict.status.roles, status.roles],
    [dict.status.permissions, status.permissions],
    [dict.status.categories, status.categories],
    [dict.status.clinics, status.clinics],
  ] as const;

  return (
    <div className="space-y-3">
      <p className="flex items-center gap-2 font-medium">
        <CircleCheck className="size-5 text-green-600" aria-hidden /> {dict.status.dbOk}
      </p>
      <dl className="grid grid-cols-[1fr_auto] gap-x-4 gap-y-1 text-sm">
        {rows.map(([label, value]) => (
          <div key={label} className="contents">
            <dt className="text-muted-foreground">{label}</dt>
            <dd className="text-right font-medium tabular-nums">{value}</dd>
          </div>
        ))}
      </dl>
    </div>
  );
}
