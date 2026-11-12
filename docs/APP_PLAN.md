# Clinic Finance App: Plan

> Living document. Edit it whenever a decision changes.
> Database: `sql/Versions/v3` (PostgreSQL 18). Tests: `sql/tests/smoke_test.sql`.

---

## 1. Goal

A simple, self-explaining web app that helps **clinic managers in the US (mostly Hispanic clinics)** keep track of their clinic's money:

- what came in, what went out
- who still owes the clinic, and what the clinic still owes
- which services and equipment earn or cost money

**First phase:** a small pilot with **5–10 clinics**, used mainly by clinic managers who currently have no tool at all. The aim is to prove the app is useful and easy enough before growing it.

### Decisions so far

| Topic | Decision |
|---|---|
| Languages | **Spanish and English** from day one. Spanish is the default for new users |
| Devices | **Desktop first.** Every screen is built responsive so tablet and phone polish can come later without a redesign |
| Hosting | **Online**, so all clinics use one system. Docker-based deployment |
| Scale | 5–10 clinics at the start |
| Look and feel | Colour palette to come from the owner's reference pictures (see §10) |
| Pilot data | **Use made-up or coded patients** ("Paciente 0012", initials) until hosting with a HIPAA BAA is in place (see §13) |

---

## 2. Who uses it

Roles come from `seed_v3.sql`. Each role sees only the menus and buttons its permissions allow.

| Role | Who | Sees | Home screen shows |
|---|---|---|---|
| **Clinic Manager** | Main pilot user | Everything for **their own clinic** | This month's money in/out, bills overdue, quick actions |
| **Clinic Staff** | Reception | Patients, record payments, create bills (own clinic) | Quick actions only |
| **HQ Finance** | Owner/accountant across clinics | All clinics, all money actions | Totals per clinic, overdue across clinics |
| **System Admin** | Whoever runs the system | Users, roles, clinics, settings, access grants, activity log. **No money or patient data** | Users and system status |
| **IT Maintenance** | Support | Nothing, until given **temporary access** to one clinic | "You have no active access" or the granted clinic |

---

## 3. Design principles: "explains itself"

1. **Their words, not accounting words.** See the glossary (§4). Accounting terms appear only as small secondary labels for HQ Finance.
2. **Tasks first.** The home screen asks *"What do you want to do?"* with large buttons, not a menu tree.
3. **Help text on every field**, short and in plain language, under the field (not hidden).
4. **Empty screens teach.** Explain what the screen is for and offer the first action.
5. **Step-by-step for anything multi-step.** Bill: *Who → What → Review → Save*, with the total always visible.
6. **Friendly errors.** Every database rule has a translated, human message that says what's wrong and what to do (see §8.3).
7. **Confirm before permanent actions** (cancel a bill, undo a match, revoke access), explain the consequence and ask for a reason.
8. **Status = colour + word + icon.** Never colour alone.
9. **Smart defaults.** Today's date, the user's clinic, the last payment method. Patient search as you type, with "+ Add new" right there.
10. **Suggest the next step.** After recording a payment: *"Patient A has 2 unpaid bills. Apply this payment to one?"*
11. **First-login tour** per role (3–5 steps, can be skipped and replayed) and a **Help** page with the glossary.
12. **Accessible.** Large click targets, readable contrast, fully usable with keyboard, works with browser zoom.

---

## 4. Glossary: screen wording (EN / ES)

Database names stay in English internally. Users only ever see these words.

| Database / accounting | English (screen) | Español (pantalla) |
|---|---|---|
| Accounts Receivable | Bills to collect | Facturas por cobrar |
| Accounts Payable | Bills to pay | Facturas por pagar |
| Invoice | Bill | Factura |
| Invoice line | Item | Concepto |
| Income transaction | Money in | Dinero recibido |
| Expense transaction | Money out | Dinero pagado |
| Reconciliation | Apply a payment to a bill | Aplicar un pago a una factura |
| Reverse reconciliation | Undo payment match | Deshacer aplicación del pago |
| Void | Cancel bill | Anular factura |
| Counterparty | Patient / Supplier / Insurer | Paciente / Proveedor / Aseguradora |
| Financial category | Category | Categoría |
| Payment method | Payment method | Forma de pago |
| Service line | Service | Servicio |
| Clinic asset | Equipment | Equipo |
| Operator allocation | Staff assignment | Asignación de personal |
| Due date | Due date | Fecha de vencimiento |
| Audit log | Activity history | Historial de actividad |
| User clinic access | Temporary access | Acceso temporal |
| Status: Pending / Partial / Reconciled / Void | Waiting / Partly paid / Paid / Cancelled | Pendiente / Pago parcial / Pagada / Anulada |
| Transaction: Completed / Pending / Cancelled | Done / Not yet received / Cancelled | Realizado / Por recibir / Cancelado |

Spanish wording should be reviewed by a native-speaking clinic manager during the pilot.

---

## 5. Screens

### 5.1 Everyone
- **Login.** Email and password, then a two-factor code (required for admins and HQ Finance, optional for others).
- **Home.** Role-based (see §2).
- **My profile.** Name, language (ES/EN), password, two-factor setup.
- **Help.** Glossary, short guides, replay the tour.

### 5.2 Money
- **Money in / Money out list.** Filter by date, category, patient/supplier, status. Totals at the top.
- **Record money in / out.** Amount, date, category, payment method, patient/supplier (optional), service, equipment (optional, plus "what for": purchase / maintenance / revenue / other), note.
  After saving money in, suggest applying it to the patient's unpaid bills.
- **Edit / cancel.** Blocked with a clear explanation if the payment is already applied to a bill ("undo the match first").

### 5.3 Bills
- **Bills to collect / Bills to pay.** Tabs with status chips, overdue highlighted, and a balance column.
- **Create bill (step-by-step).**
  1. Who: patient/supplier search and add.
  2. Items: description, category, service, quantity × price. The total updates live.
  3. Dates and number. The number is generated automatically for bills to collect, and typed in for supplier bills.
  4. Review and save.
- **Bill detail.** Items, payments applied, balance, history. Actions: apply payment, cancel bill (with a reason), print/PDF.

### 5.4 Apply payments
- From a bill ("which payment covers this?") or from a payment ("which bills does this pay?").
- Shows only valid matches (same clinic, same direction, same patient, completed, money left on both sides). This prevents most errors before they happen.
- **Undo match** with confirmation. History is kept.

### 5.5 Clinic setup (Clinic Manager)
- **Services**, **Equipment** (cost, purchase date, depreciation type; the status flow is active → sold / written off), **Staff assignments** (who works on which service or equipment and what %, with a visual 100% bar per person).

### 5.6 Reports
- **Monthly summary:** money in vs out, by category and by service.
- **Who owes us / what we owe:** grouped by how late (current, 1–30, 31–60, 60+ days).
- **Equipment value:** cost, depreciation, fully depreciated flag.
- **Service profitability** (later): revenue vs costs and assigned staff salary.
- Every report: choose the period and clinic, then export to PDF/CSV.

### 5.7 Administration
- **Users:** invite, set role and home clinic, deactivate (never delete).
- **Roles and permissions:** checkbox grid.
- **Clinics, categories, payment methods, depreciation types.**
- **Temporary access:** grant (user, clinic, reason, until), revoke, list active and past grants.
- **Activity history:** filter by user, clinic, date and record. Read-only.

### 5.8 First-run setup
On a brand-new system, a one-time wizard creates the first clinic and the first System Admin, then asks to invite the first Clinic Manager.

---

## 6. Technology

| Piece | Choice | Why |
|---|---|---|
| Framework | **Next.js (App Router) + TypeScript** | One codebase for screens and server; widely used |
| UI | **Tailwind CSS + shadcn/ui** | Accessible components; colours defined as tokens in one place |
| Forms | **React Hook Form + Zod** | Instant field-level validation in the user's language |
| Database access | **Drizzle ORM** (types pulled from the existing schema) | SQL files stay the source of truth |
| Migrations | **dbmate** (numbered `.sql` files) | Simple, SQL-only, has a Docker image |
| Auth | **Auth.js** (credentials) + **argon2** + TOTP two-factor | Standard, no third-party login provider needed |
| Translations | **Built-in Next.js approach**: JSON dictionaries + `next/root-params`, `/es/...` and `/en/...` URLs, `proxy.ts` picks the language | Native to Next.js 16, no extra library to keep compatible. Dates/money via the browser's `Intl` API |
| PDFs | Generated server-side (library to decide when building reports) | Bills and reports |
| Tests | **Playwright** (click-through) + **Vitest** (logic) + SQL smoke test | Screens, logic and database rules |
| Runtime | **Node.js 26** (installed) | Required by Next.js 16 |

---

## 7. Project structure

```
/
├─ docs/                          plans and decisions (this file)
├─ sql/
│  ├─ Versions/v2, v3/            design history (dbdiagram + full SQL)
│  ├─ migrations/                 dbmate migrations: the real source of truth
│  │   0100 v3 schema · 0200 reference data · 0300 app additions
│  └─ tests/smoke_test.sql        database rule tests (rolled back)
├─ app/                           Next.js app
│  ├─ .env / .env.example         settings (.env is never committed)
│  ├─ src/proxy.ts                sends "/" to /es or /en
│  ├─ src/app/[lang]/...          pages, per language
│  ├─ src/i18n/                   language config + dictionaries/es.json, en.json
│  ├─ src/components/             UI components (ui/ = shadcn)
│  ├─ src/server/db/              database connection, withActor() helper,
│  │   generated/                 table types pulled from the database
│  ├─ src/lib/errors.ts           (milestone 1+) database error → friendly message
│  └─ tests/                      (later) Playwright and Vitest
├─ docker/                        (milestone 9) Dockerfiles, Caddyfile
└─ docker-compose.yml             (milestone 9)
```

### Everyday commands (run inside `app/`)

| Command | What it does |
|---|---|
| `npm run dev` | Start the app at http://localhost:3000 |
| `npm run db:migrate` | Apply new migrations (creates the database if missing) |
| `npm run db:status` | Show which migrations are applied |
| `npm run db:new <name>` | Create a new, empty migration file |
| `npm run db:pull` | Refresh the TypeScript table types after a migration |
| `npm run typecheck` / `npm run lint` / `npm run build` | Checks before committing |

**Changing the database:** `db:new` → write the SQL (with a `-- migrate:down` part) → `db:migrate` → run the smoke test → `db:pull`. Never edit a migration that has already been applied; add a new one.

---

## 8. How the app talks to the database

### 8.1 Every request
1. Check the session, then the **permission** (`v_user_permissions`), then the **clinic access** (`v_user_clinics`).
2. Open a transaction and run `SET LOCAL app.user_id = '<id>'` and `SET LOCAL app.client_ip = '<ip>'`. The automatic audit log then records who did it.
3. Run the query or change, then commit.
4. **Every query is filtered by the clinics the user can access.** One shared helper does this, so no screen can forget.

### 8.2 Logging views
The database logs changes automatically. The app additionally writes `view` and `export` rows when someone opens patient details, bills or reports, plus `login`, `login_failed` and `logout`.

### 8.3 Friendly errors
The database rules raise precise messages. `src/lib/errors.ts` maps each one (by constraint or trigger message) to a translated, human message and a suggested fix. Examples:

| Database says | User sees (EN) | Usuario ve (ES) |
|---|---|---|
| `Applying X exceeds invoice N total…` | This bill only has $Y left to pay. | A esta factura solo le quedan $Y por pagar. |
| `…has active reconciliations; reverse them before voiding` | This bill has payments applied. Undo them first, then cancel it. | Esta factura tiene pagos aplicados. Deshágalos primero y luego anúlela. |
| `Invoice N total is X but its lines add up to Y` | The items add up to $Y, but the total says $X. | Los conceptos suman $Y, pero el total dice $X. |
| `User N would be allocated 110 percent…` | This person would be over 100% of their time on that date. | Esta persona superaría el 100% de su tiempo en esa fecha. |
| unique invoice number | That bill number already exists for this patient/supplier. | Ese número de factura ya existe para este paciente/proveedor. |

**Rule:** forms validate first (Zod), so most of these never reach the database. The database rules remain the safety net.

### 8.4 Database additions the app needs (migration 0003, ✅ done)
v3 covers the finance rules, but some features in this plan need extra columns. They're in `sql/migrations/20261111000300_app_additions.sql`, with tests in the smoke test. The DBML in dbdiagram still needs updating to match (v4).

| Table | Addition | Needed for |
|---|---|---|
| `users` | `preferred_language` (`es` / `en`, default `es`) | Language saved per user (§1) |
| `users` | `totp_secret` (encrypted), `totp_enabled` | Two-factor login (§9) |
| `users` | `failed_login_count`, `locked_until`, `last_login_at` | Lockout and rate limiting (§9) |
| `users` | `must_change_password` | Invited users set their own password |
| `counterparties` | `counterparty_type` (`Patient` / `Supplier` / `Insurer` / `Other`) | Tabs and filters "Patient / Supplier / Insurer" (§4, §5) |
| `counterparties` | `id_clinic` (nullable = shared, e.g. a supplier used by all clinics) | Patients belong to one clinic, so staff only see their clinic's patients |
| `clinics` | `clinic_code` (short, unique, e.g. `NOR`) | Bill numbers like `NOR-2026-0001` (§13) |
| new `invoice_number_sequences` + `next_invoice_number(clinic, date)` | one counter per clinic and year | Gap-free automatic bill numbers |
| rule | a bill/payment can only use a patient/supplier of its own clinic (or a shared one) | Keeps clinics' data apart |
| `trg_audit_row` | also masks `totp_secret` | Two-factor secrets never reach the activity log |
| sessions | handled by Auth.js (JWT or a sessions table, decided in milestone 1) | Login sessions |

**Note on `counterparties.id_clinic`:** without it, every clinic's staff could see every clinic's patients, which conflicts with the "own clinic only" rule. This is the most important addition.

---

## 9. Security

### Built in while developing
- Passwords hashed with **argon2**; never logged (the database audit already masks them).
- Secure, HTTP-only session cookies; **automatic logout after 30 min of inactivity**.
- **Login rate limiting and lockout** after repeated failures, recorded in the activity history.
- **Two-factor (authenticator app)**, required for System Admin and HQ Finance.
- Permission and clinic checks **on the server for every action**, not just hidden buttons.
- Input validation (Zod), parameterised queries (Drizzle), Next.js protections against XSS/CSRF.
- Security headers (CSP, HSTS, etc.).
- Secrets only in `.env` (git-ignored); `.env.example` documents them.

### At deployment (§12)
- HTTPS only (Caddy, automatic certificates).
- The database is not reachable from the internet.
- Encrypted nightly backups to a second provider, test-restored monthly.
- Server firewall and automatic security updates.
- Hosting provider that signs a **HIPAA BAA** before real patient data is used.

---

## 10. Look and feel

- All colours are **design tokens** (CSS variables): `primary`, `secondary`, `background`, `surface`, `text`, `muted`, `border`, `success`, `warning`, `danger`, `info`, plus dark-mode versions.
- **Waiting on:** the owner's reference pictures. They become the palette, and contrast is checked (WCAG AA) before use.
- Status colours are fixed in meaning and always paired with an icon and a word: Paid = success, Partly paid = info, Waiting = warning, Overdue = danger, Cancelled = muted.
- Typography: one clean sans-serif with good Spanish accent support, large base size (16–18 px).

---

## 11. Build order (milestones)

Each milestone ends with something usable and tested.

| # | Milestone | Done when |
|---|---|---|
| 0 ✅ | **Dev setup:** Next.js 16, Tailwind + shadcn, ES/EN routing and dictionaries, Drizzle + `withActor()` audit helper, dbmate migrations (v3 schema, reference data, app additions) into `clinic_dev` | App starts in both languages and reads the database; SQL smoke test passes (78/78) |
| 1 | **Login and access:** first-run wizard, login, 2FA, lockout, session timeout, role-based menu, the "set user in transaction" helper, activity logging | Each seed role logs in and sees only its menu; logins appear in the activity history |
| 2 | **Settings:** clinics, categories, payment methods, patients/suppliers | Manager can set up a clinic from scratch |
| 3 | **Money in / out** | Record, edit, cancel; list with filters and totals |
| 4 | **Bills** with items, step-by-step creation, PDF | Create, view, cancel; numbering per clinic |
| 5 | **Apply payments** | Apply from either side, partial payments, undo; only valid options offered |
| 6 | **Equipment, services, staff assignments** | Full CRUD with the 100% bar |
| 7 | **Home dashboards and reports** | Monthly summary, who owes us, equipment value; PDF/CSV export |
| 8 | **Help and tour** | Glossary, per-role tour, empty states everywhere |
| 9 | **Docker and deployment** (§12) | Running online over HTTPS with backups |
| 10 | **Pilot** with 1–2 clinics, then all | Feedback collected, fixes prioritised |

The colour palette can be applied at any point after milestone 0, since only the tokens change.

---

## 12. Docker and deployment (later)

```
docker-compose.yml
  db       postgres:18            data in a named volume, no public port
  migrate  dbmate                 applies sql/migrations, then exits
  app      Next.js (standalone)   multi-stage build, small image
  caddy    reverse proxy          automatic HTTPS, security headers
  backup   pg_dump on a schedule  encrypted, copied off-server
```

- **Development:** the same compose file, running only `db` (and `migrate`); the app runs locally with hot reload.
- **Server:** one VPS (2–4 GB RAM) is enough for 5–10 clinics. The provider must sign a **BAA** before real patient data goes in (e.g. AWS, Azure, Google Cloud, DigitalOcean's HIPAA-eligible setup).
- **Updates:** build the image, run migrations, restart the app. Short downtime is acceptable for the pilot.
- **Prerequisite:** Docker Desktop (with WSL2) on the dev machine. Not installed yet.

---

## 13. Risks and open points

| Item | Note |
|---|---|
| **HIPAA** | Clinics are in the US. Real patient names + payments online = PHI. **During the pilot, use coded patients** until hosting with a BAA is in place. Get a short legal check before going live with real data. |
| Spanish wording | Have a native-speaking manager review it during the pilot. |
| Phones/tablets | Responsive from the start; dedicated polish after the pilot. |
| Receipt/bill PDF layout | Needs the clinic's details/logo; decide during milestone 4. |
| Bill numbering format | Proposed: `<CLINIC CODE>-<YEAR>-<0001>` (needs `clinics.clinic_code`, see §8.4). |
| Patients visible across clinics | v3 `counterparties` has no clinic, so all clinics would share one patient list. Fixed by `counterparties.id_clinic` in migration 0002 (§8.4). |
| Insurance claims | Out of scope for now. Insurers are just a type of counterparty. |
| Multi-clinic users | Users have one home clinic; others only via HQ permission or temporary access. Revisit if managers run several clinics. |
| Docker | Not installed yet on the dev machine; needed for milestone 9. |
| DBML out of date | `sql/Versions/v3/*.dbml` doesn't include migration 0003 yet. Update dbdiagram to a v4 before the next design review. |
| `clinic_scratch` database | Old manual test database from before migrations. Can be dropped; `clinic_dev` replaces it. |
