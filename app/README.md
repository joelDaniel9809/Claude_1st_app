# Clinic Finance: web app

Next.js 16 app for the Clinic Finance project. The full plan is in [`../docs/APP_PLAN.md`](../docs/APP_PLAN.md).

## First-time setup

1. Install **Node.js** (v22 or newer) and **PostgreSQL** (v16 or newer).
2. In this `app/` folder:
   ```bash
   npm install
   ```
3. Copy `.env.example` to `.env` and put your PostgreSQL password in `DATABASE_URL`.
4. Create the database and apply all migrations:
   ```bash
   npm run db:migrate
   ```
5. Start the app:
   ```bash
   npm run dev
   ```
   Open http://localhost:3000. It redirects to `/es` or `/en`.

## Everyday commands

| Command | What it does |
|---|---|
| `npm run dev` | Start the app with hot reload |
| `npm run db:migrate` | Apply new migrations from `../sql/migrations` |
| `npm run db:status` | Which migrations are applied |
| `npm run db:new <name>` | New empty migration file |
| `npm run db:pull` | Refresh table types in `src/server/db/generated` after a migration |
| `npm run typecheck` | TypeScript check |
| `npm run lint` | ESLint |
| `npm run build` | Production build |

Database rule tests: open `../sql/tests/smoke_test.sql` in pgAdmin on `clinic_dev` and run it (or use `psql`). Everything is rolled back.

## Where things are

| Path | What |
|---|---|
| `src/proxy.ts` | Sends `/` to the visitor's language |
| `src/app/[lang]/` | Pages (every page lives under `/es/...` or `/en/...`) |
| `src/i18n/dictionaries/` | All screen text: `es.json` and `en.json` (same keys) |
| `src/components/ui/` | shadcn/ui components |
| `src/app/globals.css` | Colour tokens (`--primary`, `--background`…): the palette goes here |
| `src/server/db/index.ts` | Database connection and `withActor()` (use it for **every** write so the audit log knows who did it) |
| `src/server/db/generated/` | Table types pulled from the database. Don't edit by hand |

> This Next.js version has breaking changes from older versions. Its docs ship in `node_modules/next/dist/docs/` (see `AGENTS.md`).
