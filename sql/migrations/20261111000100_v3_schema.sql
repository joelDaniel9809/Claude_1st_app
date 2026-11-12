-- migrate:up
-- Clinic Finance v3: tables (dbdiagram export) + rules, views and triggers.
-- Generated from sql/Versions/v3. Do not edit an applied migration: add a new one.

CREATE TYPE "enum_financial_type" AS ENUM (
  'Income',
  'Expense'
);

CREATE TYPE "enum_periodicity" AS ENUM (
  'Daily',
  'Weekly',
  'Biweekly',
  'Monthly',
  'Quarterly',
  'Annual',
  'Variable'
);

CREATE TYPE "enum_transaction_status" AS ENUM (
  'Completed',
  'Pending',
  'Cancelled'
);

CREATE TYPE "enum_asset_status" AS ENUM (
  'Active',
  'Sold',
  'Damaged Write-Off'
);

CREATE TYPE "enum_asset_link_type" AS ENUM (
  'Purchase',
  'Maintenance',
  'Revenue',
  'Other'
);

CREATE TABLE "clinics" (
  "id_clinic" SERIAL PRIMARY KEY,
  "clinic_name" varchar(150) NOT NULL,
  "address" text,
  "active" boolean NOT NULL DEFAULT true,
  "created_at" timestamptz NOT NULL DEFAULT (now()),
  "updated_at" timestamptz NOT NULL DEFAULT (now())
);

CREATE TABLE "financial_categories" (
  "id_category" SERIAL PRIMARY KEY,
  "financial_type" enum_financial_type NOT NULL,
  "category_name" varchar(100) NOT NULL,
  "suggested_periodicity" enum_periodicity NOT NULL DEFAULT 'Variable'
);

CREATE TABLE "payment_methods" (
  "id_method" SERIAL PRIMARY KEY,
  "method_name" varchar(50) UNIQUE NOT NULL
);

CREATE TABLE "depreciation_categories" (
  "id_dep_category" SERIAL PRIMARY KEY,
  "category_name" varchar(100) UNIQUE NOT NULL,
  "useful_life_months" int NOT NULL,
  CONSTRAINT "chk_dep_life_positive" CHECK (useful_life_months > 0)
);

CREATE TABLE "counterparties" (
  "id_counterparty" SERIAL PRIMARY KEY,
  "counterparty_name" varchar(150) NOT NULL,
  "tax_id" varchar(50) UNIQUE,
  "active" boolean NOT NULL DEFAULT true,
  "created_at" timestamptz NOT NULL DEFAULT (now()),
  "updated_at" timestamptz NOT NULL DEFAULT (now())
);

CREATE TABLE "roles" (
  "id_role" SERIAL PRIMARY KEY,
  "role_name" varchar(50) UNIQUE NOT NULL,
  "description" text
);

CREATE TABLE "permissions" (
  "id_permission" SERIAL PRIMARY KEY,
  "permission_code" varchar(100) UNIQUE NOT NULL,
  "description" text
);

CREATE TABLE "role_permissions" (
  "id_role" int NOT NULL,
  "id_permission" int NOT NULL,
  PRIMARY KEY ("id_role", "id_permission")
);

CREATE TABLE "users" (
  "id_user" SERIAL PRIMARY KEY,
  "first_name" varchar(100) NOT NULL,
  "last_name" varchar(100) NOT NULL,
  "email" varchar(150) UNIQUE NOT NULL,
  "phone" varchar(20),
  "id_clinic" int,
  "id_role" int NOT NULL,
  "password_hash" varchar(255) NOT NULL,
  "active" boolean NOT NULL DEFAULT true,
  "created_at" timestamptz NOT NULL DEFAULT (now()),
  "updated_at" timestamptz NOT NULL DEFAULT (now())
);

CREATE TABLE "user_clinic_access" (
  "id_access" SERIAL PRIMARY KEY,
  "id_user" int NOT NULL,
  "id_clinic" int NOT NULL,
  "id_granted_by" int NOT NULL,
  "reason" text NOT NULL,
  "granted_at" timestamptz NOT NULL DEFAULT (now()),
  "expires_at" timestamptz NOT NULL,
  "revoked_at" timestamptz,
  CONSTRAINT "chk_access_expiry" CHECK (expires_at > granted_at),
  CONSTRAINT "chk_access_revoked" CHECK (revoked_at IS NULL OR revoked_at >= granted_at),
  CONSTRAINT "chk_access_not_self_granted" CHECK (id_user <> id_granted_by)
);

CREATE TABLE "audit_log" (
  "id_audit" BIGSERIAL PRIMARY KEY,
  "id_user" int,
  "id_clinic" int,
  "action" varchar(50) NOT NULL,
  "table_name" varchar(100),
  "record_id" bigint,
  "details" jsonb,
  "ip_address" varchar(45),
  "created_at" timestamptz NOT NULL DEFAULT (now())
);

CREATE TABLE "service_lines" (
  "id_service_line" SERIAL PRIMARY KEY,
  "id_clinic" int NOT NULL,
  "service_name" varchar(150) NOT NULL,
  "active" boolean NOT NULL DEFAULT true,
  "created_at" timestamptz NOT NULL DEFAULT (now()),
  "updated_at" timestamptz NOT NULL DEFAULT (now())
);

CREATE TABLE "clinic_assets" (
  "id_asset" SERIAL PRIMARY KEY,
  "id_clinic" int NOT NULL,
  "asset_name" varchar(150) NOT NULL,
  "serial_number" varchar(100) UNIQUE,
  "is_depreciable" boolean NOT NULL DEFAULT true,
  "id_dep_category" int,
  "acquisition_cost" numeric(12,2) NOT NULL DEFAULT 0,
  "purchase_date" date NOT NULL DEFAULT (CURRENT_DATE),
  "depreciation_start_date" date,
  "asset_status" enum_asset_status NOT NULL DEFAULT 'Active',
  "disposal_date" date,
  "disposal_amount" numeric(12,2),
  "created_at" timestamptz NOT NULL DEFAULT (now()),
  "updated_at" timestamptz NOT NULL DEFAULT (now()),
  CONSTRAINT "chk_depreciation_conditional" CHECK ((is_depreciable AND id_dep_category IS NOT NULL AND depreciation_start_date IS NOT NULL) OR (NOT is_depreciable AND id_dep_category IS NULL AND depreciation_start_date IS NULL)),
  CONSTRAINT "chk_asset_cost_nonneg" CHECK (acquisition_cost >= 0),
  CONSTRAINT "chk_dep_start_after_purchase" CHECK (depreciation_start_date IS NULL OR depreciation_start_date >= purchase_date),
  CONSTRAINT "chk_asset_disposal" CHECK ((asset_status = 'Active' AND disposal_date IS NULL AND disposal_amount IS NULL) OR (asset_status = 'Sold' AND disposal_date IS NOT NULL AND disposal_date >= purchase_date) OR (asset_status = 'Damaged Write-Off' AND disposal_date IS NOT NULL AND disposal_date >= purchase_date AND disposal_amount IS NULL))
);

CREATE TABLE "operator_allocations" (
  "id_allocation" SERIAL PRIMARY KEY,
  "id_user" int NOT NULL,
  "id_asset" int,
  "id_service_line" int,
  "allocation_percentage" numeric(5,2) NOT NULL DEFAULT 100,
  "assigned_at" date NOT NULL DEFAULT (CURRENT_DATE),
  "retracted_at" date,
  "created_at" timestamptz NOT NULL DEFAULT (now()),
  "updated_at" timestamptz NOT NULL DEFAULT (now()),
  CONSTRAINT "chk_alloc_exactly_one_target" CHECK ((id_asset IS NOT NULL AND id_service_line IS NULL) OR (id_asset IS NULL AND id_service_line IS NOT NULL)),
  CONSTRAINT "chk_alloc_pct_range" CHECK (allocation_percentage > 0 AND allocation_percentage <= 100),
  CONSTRAINT "chk_alloc_dates" CHECK (retracted_at IS NULL OR retracted_at >= assigned_at)
);

CREATE TABLE "transactions" (
  "id_transaction" BIGSERIAL PRIMARY KEY,
  "id_clinic" int NOT NULL,
  "id_category" int NOT NULL,
  "id_method" int NOT NULL,
  "id_registered_by" int NOT NULL,
  "id_payee_user" int,
  "id_counterparty" int,
  "id_asset" int,
  "asset_link_type" enum_asset_link_type,
  "id_service_line" int,
  "amount" numeric(12,2) NOT NULL,
  "transaction_date" date NOT NULL DEFAULT (CURRENT_DATE),
  "description" text,
  "transaction_status" enum_transaction_status NOT NULL DEFAULT 'Completed',
  "created_at" timestamptz NOT NULL DEFAULT (now()),
  "updated_at" timestamptz NOT NULL DEFAULT (now()),
  CONSTRAINT "chk_trx_amount_positive" CHECK (amount > 0),
  CONSTRAINT "chk_trx_asset_link" CHECK ((id_asset IS NULL) = (asset_link_type IS NULL))
);

CREATE TABLE "invoices" (
  "id_invoice" SERIAL PRIMARY KEY,
  "id_clinic" int NOT NULL,
  "id_counterparty" int NOT NULL,
  "invoice_number" varchar(50) NOT NULL,
  "financial_type" enum_financial_type NOT NULL,
  "total_amount" numeric(12,2) NOT NULL,
  "issue_date" date NOT NULL,
  "due_date" date NOT NULL,
  "is_void" boolean NOT NULL DEFAULT false,
  "created_at" timestamptz NOT NULL DEFAULT (now()),
  "updated_at" timestamptz NOT NULL DEFAULT (now()),
  CONSTRAINT "chk_invoice_total_positive" CHECK (total_amount > 0),
  CONSTRAINT "chk_invoice_dates" CHECK (due_date >= issue_date)
);

CREATE TABLE "invoice_lines" (
  "id_line" SERIAL PRIMARY KEY,
  "id_invoice" int NOT NULL,
  "line_number" smallint NOT NULL,
  "description" varchar(255) NOT NULL,
  "financial_type" enum_financial_type NOT NULL,
  "id_category" int NOT NULL,
  "id_service_line" int,
  "quantity" numeric(10,2) NOT NULL DEFAULT 1,
  "unit_price" numeric(12,2) NOT NULL,
  "line_total" numeric(12,2) NOT NULL,
  "created_at" timestamptz NOT NULL DEFAULT (now()),
  "updated_at" timestamptz NOT NULL DEFAULT (now()),
  CONSTRAINT "chk_line_qty_positive" CHECK (quantity > 0),
  CONSTRAINT "chk_line_price_nonneg" CHECK (unit_price >= 0),
  CONSTRAINT "chk_line_total" CHECK (line_total = ROUND(quantity * unit_price, 2))
);

CREATE TABLE "reconciliation_history" (
  "id_reconciliation" SERIAL PRIMARY KEY,
  "id_invoice" int NOT NULL,
  "id_transaction" bigint NOT NULL,
  "id_user" int NOT NULL,
  "applied_amount" numeric(12,2) NOT NULL,
  "reconciliation_date" timestamptz NOT NULL DEFAULT (now()),
  "reversed_at" timestamptz,
  CONSTRAINT "chk_recon_amount_positive" CHECK (applied_amount > 0)
);

CREATE UNIQUE INDEX ON "financial_categories" ("financial_type", "category_name");

CREATE UNIQUE INDEX ON "financial_categories" ("id_category", "financial_type");

CREATE INDEX ON "user_clinic_access" ("id_user", "id_clinic");

CREATE INDEX ON "user_clinic_access" ("id_clinic");

CREATE INDEX ON "audit_log" ("id_clinic", "created_at");

CREATE INDEX ON "audit_log" ("id_user", "created_at");

CREATE INDEX ON "audit_log" ("table_name", "record_id");

CREATE UNIQUE INDEX ON "service_lines" ("id_clinic", "service_name");

CREATE UNIQUE INDEX ON "service_lines" ("id_service_line", "id_clinic");

CREATE INDEX ON "clinic_assets" ("id_clinic");

CREATE UNIQUE INDEX ON "clinic_assets" ("id_asset", "id_clinic");

CREATE INDEX ON "operator_allocations" ("id_user");

CREATE INDEX ON "operator_allocations" ("id_asset");

CREATE INDEX ON "operator_allocations" ("id_service_line");

CREATE INDEX ON "transactions" ("id_clinic", "transaction_date");

CREATE INDEX ON "transactions" ("id_category");

CREATE INDEX ON "transactions" ("id_counterparty");

CREATE INDEX ON "transactions" ("id_asset");

CREATE INDEX ON "transactions" ("id_service_line");

CREATE INDEX ON "transactions" ("id_payee_user");

CREATE UNIQUE INDEX ON "invoices" ("id_clinic", "id_counterparty", "invoice_number");

CREATE UNIQUE INDEX ON "invoices" ("id_invoice", "financial_type");

CREATE INDEX ON "invoices" ("id_clinic", "due_date");

CREATE INDEX ON "invoices" ("id_counterparty");

CREATE UNIQUE INDEX ON "invoice_lines" ("id_invoice", "line_number");

CREATE INDEX ON "invoice_lines" ("id_category");

CREATE INDEX ON "invoice_lines" ("id_service_line");

CREATE INDEX ON "reconciliation_history" ("id_invoice");

CREATE INDEX ON "reconciliation_history" ("id_transaction");

COMMENT ON COLUMN "clinics"."active" IS 'Soft delete. Never cascade-delete a clinic''s financial history';

COMMENT ON COLUMN "financial_categories"."suggested_periodicity" IS 'Hint for the UI only';

COMMENT ON COLUMN "depreciation_categories"."useful_life_months" IS 'Single source of truth. Straight-line annual % = 1200 / useful_life_months';

COMMENT ON TABLE "counterparties" IS 'Suppliers, patients, insurers... Patient data is personal: access is limited by clinic and logged in audit_log';

COMMENT ON COLUMN "counterparties"."tax_id" IS 'Optional, unique when present';

COMMENT ON COLUMN "permissions"."permission_code" IS 'e.g. invoices.view, invoices.create, invoices.void, transactions.create, reconciliation.reverse, reports.view, users.manage, clinics.view_all, audit.view';

COMMENT ON TABLE "role_permissions" IS 'What each role may do. Being a system admin (users.manage) does NOT imply reading financial/patient data: that needs its own permissions';

COMMENT ON COLUMN "users"."id_clinic" IS 'Home clinic: the user sees this clinic''s data. NULL = HQ user with no clinic data by default. Other clinics only via the clinics.view_all permission or an active user_clinic_access grant';

COMMENT ON TABLE "user_clinic_access" IS 'Temporary ''break-glass'' access to another clinic (maintenance, audits, cover). Active = revoked_at IS NULL AND now() < expires_at';

COMMENT ON COLUMN "user_clinic_access"."id_user" IS 'Who receives access';

COMMENT ON COLUMN "user_clinic_access"."id_clinic" IS 'Clinic they may access';

COMMENT ON COLUMN "user_clinic_access"."id_granted_by" IS 'Who approved it';

COMMENT ON COLUMN "user_clinic_access"."reason" IS 'Why, e.g. ticket number for maintenance';

COMMENT ON COLUMN "user_clinic_access"."expires_at" IS 'Every grant is temporary';

COMMENT ON COLUMN "user_clinic_access"."revoked_at" IS 'Set to end the grant early. Never delete rows';

COMMENT ON TABLE "audit_log" IS 'Append-only: rows can''t be updated or deleted (enforced in the SQL file)';

COMMENT ON COLUMN "audit_log"."id_user" IS 'NULL = system/automated action';

COMMENT ON COLUMN "audit_log"."id_clinic" IS 'Clinic whose data was touched, if any';

COMMENT ON COLUMN "audit_log"."action" IS 'e.g. view, create, update, void, reverse, export, login, access_granted, access_revoked';

COMMENT ON COLUMN "audit_log"."details" IS 'Before/after values or other context';

COMMENT ON COLUMN "service_lines"."service_name" IS 'e.g. Office Visit, Counseling. A revenue/cost center, not a physical asset';

COMMENT ON COLUMN "clinic_assets"."serial_number" IS 'Optional for every asset';

COMMENT ON COLUMN "clinic_assets"."id_dep_category" IS 'Required if and only if is_depreciable';

COMMENT ON COLUMN "clinic_assets"."depreciation_start_date" IS 'Required if and only if is_depreciable';

COMMENT ON COLUMN "clinic_assets"."disposal_amount" IS 'Sale price, only meaningful when Sold';

COMMENT ON TABLE "operator_allocations" IS 'No-overlap and total <= 100% per user are enforced in the SQL file';

COMMENT ON COLUMN "operator_allocations"."allocation_percentage" IS 'Share of the user''s working time/salary dedicated to this target';

COMMENT ON COLUMN "operator_allocations"."retracted_at" IS 'NULL while the user is still assigned';

COMMENT ON COLUMN "transactions"."id_registered_by" IS 'User who recorded the entry';

COMMENT ON COLUMN "transactions"."id_payee_user" IS 'User who received the money, e.g. payroll';

COMMENT ON COLUMN "transactions"."id_counterparty" IS 'NEW. Who paid / who was paid (patient, supplier, insurer). Optional. If set, it must match the invoice''s counterparty when reconciled';

COMMENT ON COLUMN "transactions"."asset_link_type" IS 'What this transaction is to the asset. Required iff id_asset is set';

COMMENT ON COLUMN "transactions"."amount" IS 'Always positive. Direction comes from the category';

COMMENT ON COLUMN "transactions"."transaction_date" IS 'When the money actually moved. Entry time = created_at';

COMMENT ON COLUMN "transactions"."transaction_status" IS 'Reports must only count Completed: use the v_ledger view';

COMMENT ON TABLE "invoices" IS 'Paid amount and status are derived from reconciliation_history (see v_invoice_balances)';

COMMENT ON COLUMN "invoices"."invoice_number" IS 'NEW. Receivables: generated by the app per clinic. Payables: the supplier''s own number';

COMMENT ON COLUMN "invoices"."financial_type" IS 'NEW, replaces id_category. Income = receivable, Expense = payable. Categories now live on each line';

COMMENT ON COLUMN "invoices"."total_amount" IS 'Must equal the sum of its invoice_lines.line_total (checked at commit in the SQL file)';

COMMENT ON COLUMN "invoice_lines"."line_number" IS 'Order on the invoice: 1, 2, 3...';

COMMENT ON COLUMN "invoice_lines"."description" IS 'e.g. Consultation, Lab test';

COMMENT ON COLUMN "invoice_lines"."financial_type" IS 'Copy of the invoice''s type. The two composite FKs force the line''s category to have the same type as its invoice';

COMMENT ON COLUMN "invoice_lines"."id_service_line" IS 'Optional. Must belong to the invoice''s clinic (checked in the SQL file)';

COMMENT ON COLUMN "invoice_lines"."line_total" IS '= ROUND(quantity * unit_price, 2), enforced by a check';

COMMENT ON TABLE "reconciliation_history" IS 'One ACTIVE link per (invoice, transaction) pair: partial unique index in the SQL file';

COMMENT ON COLUMN "reconciliation_history"."reversed_at" IS 'Append-only audit trail: undo = set this, never delete';

ALTER TABLE "users" ADD FOREIGN KEY ("id_clinic") REFERENCES "clinics" ("id_clinic") ON DELETE RESTRICT DEFERRABLE INITIALLY IMMEDIATE;

ALTER TABLE "users" ADD FOREIGN KEY ("id_role") REFERENCES "roles" ("id_role") ON DELETE RESTRICT DEFERRABLE INITIALLY IMMEDIATE;

ALTER TABLE "role_permissions" ADD FOREIGN KEY ("id_role") REFERENCES "roles" ("id_role") ON DELETE RESTRICT DEFERRABLE INITIALLY IMMEDIATE;

ALTER TABLE "role_permissions" ADD FOREIGN KEY ("id_permission") REFERENCES "permissions" ("id_permission") ON DELETE RESTRICT DEFERRABLE INITIALLY IMMEDIATE;

ALTER TABLE "user_clinic_access" ADD FOREIGN KEY ("id_user") REFERENCES "users" ("id_user") ON DELETE RESTRICT DEFERRABLE INITIALLY IMMEDIATE;

ALTER TABLE "user_clinic_access" ADD FOREIGN KEY ("id_granted_by") REFERENCES "users" ("id_user") ON DELETE RESTRICT DEFERRABLE INITIALLY IMMEDIATE;

ALTER TABLE "user_clinic_access" ADD FOREIGN KEY ("id_clinic") REFERENCES "clinics" ("id_clinic") ON DELETE RESTRICT DEFERRABLE INITIALLY IMMEDIATE;

ALTER TABLE "audit_log" ADD FOREIGN KEY ("id_user") REFERENCES "users" ("id_user") ON DELETE RESTRICT DEFERRABLE INITIALLY IMMEDIATE;

ALTER TABLE "audit_log" ADD FOREIGN KEY ("id_clinic") REFERENCES "clinics" ("id_clinic") ON DELETE RESTRICT DEFERRABLE INITIALLY IMMEDIATE;

ALTER TABLE "service_lines" ADD FOREIGN KEY ("id_clinic") REFERENCES "clinics" ("id_clinic") ON DELETE RESTRICT DEFERRABLE INITIALLY IMMEDIATE;

ALTER TABLE "clinic_assets" ADD FOREIGN KEY ("id_clinic") REFERENCES "clinics" ("id_clinic") ON DELETE RESTRICT DEFERRABLE INITIALLY IMMEDIATE;

ALTER TABLE "clinic_assets" ADD FOREIGN KEY ("id_dep_category") REFERENCES "depreciation_categories" ("id_dep_category") ON DELETE RESTRICT DEFERRABLE INITIALLY IMMEDIATE;

ALTER TABLE "operator_allocations" ADD FOREIGN KEY ("id_user") REFERENCES "users" ("id_user") ON DELETE RESTRICT DEFERRABLE INITIALLY IMMEDIATE;

ALTER TABLE "operator_allocations" ADD FOREIGN KEY ("id_asset") REFERENCES "clinic_assets" ("id_asset") ON DELETE RESTRICT DEFERRABLE INITIALLY IMMEDIATE;

ALTER TABLE "operator_allocations" ADD FOREIGN KEY ("id_service_line") REFERENCES "service_lines" ("id_service_line") ON DELETE RESTRICT DEFERRABLE INITIALLY IMMEDIATE;

ALTER TABLE "transactions" ADD FOREIGN KEY ("id_clinic") REFERENCES "clinics" ("id_clinic") ON DELETE RESTRICT DEFERRABLE INITIALLY IMMEDIATE;

ALTER TABLE "transactions" ADD FOREIGN KEY ("id_category") REFERENCES "financial_categories" ("id_category") ON DELETE RESTRICT DEFERRABLE INITIALLY IMMEDIATE;

ALTER TABLE "transactions" ADD FOREIGN KEY ("id_method") REFERENCES "payment_methods" ("id_method") ON DELETE RESTRICT DEFERRABLE INITIALLY IMMEDIATE;

ALTER TABLE "transactions" ADD FOREIGN KEY ("id_registered_by") REFERENCES "users" ("id_user") ON DELETE RESTRICT DEFERRABLE INITIALLY IMMEDIATE;

ALTER TABLE "transactions" ADD FOREIGN KEY ("id_payee_user") REFERENCES "users" ("id_user") ON DELETE RESTRICT DEFERRABLE INITIALLY IMMEDIATE;

ALTER TABLE "transactions" ADD FOREIGN KEY ("id_counterparty") REFERENCES "counterparties" ("id_counterparty") ON DELETE RESTRICT DEFERRABLE INITIALLY IMMEDIATE;

ALTER TABLE "transactions" ADD FOREIGN KEY ("id_asset", "id_clinic") REFERENCES "clinic_assets" ("id_asset", "id_clinic") ON DELETE RESTRICT DEFERRABLE INITIALLY IMMEDIATE;

ALTER TABLE "transactions" ADD FOREIGN KEY ("id_service_line", "id_clinic") REFERENCES "service_lines" ("id_service_line", "id_clinic") ON DELETE RESTRICT DEFERRABLE INITIALLY IMMEDIATE;

ALTER TABLE "invoices" ADD FOREIGN KEY ("id_clinic") REFERENCES "clinics" ("id_clinic") ON DELETE RESTRICT DEFERRABLE INITIALLY IMMEDIATE;

ALTER TABLE "invoices" ADD FOREIGN KEY ("id_counterparty") REFERENCES "counterparties" ("id_counterparty") ON DELETE RESTRICT DEFERRABLE INITIALLY IMMEDIATE;

ALTER TABLE "invoice_lines" ADD FOREIGN KEY ("id_invoice", "financial_type") REFERENCES "invoices" ("id_invoice", "financial_type") ON DELETE RESTRICT DEFERRABLE INITIALLY IMMEDIATE;

ALTER TABLE "invoice_lines" ADD FOREIGN KEY ("id_category", "financial_type") REFERENCES "financial_categories" ("id_category", "financial_type") ON DELETE RESTRICT DEFERRABLE INITIALLY IMMEDIATE;

ALTER TABLE "invoice_lines" ADD FOREIGN KEY ("id_service_line") REFERENCES "service_lines" ("id_service_line") ON DELETE RESTRICT DEFERRABLE INITIALLY IMMEDIATE;

ALTER TABLE "reconciliation_history" ADD FOREIGN KEY ("id_invoice") REFERENCES "invoices" ("id_invoice") ON DELETE RESTRICT DEFERRABLE INITIALLY IMMEDIATE;

ALTER TABLE "reconciliation_history" ADD FOREIGN KEY ("id_transaction") REFERENCES "transactions" ("id_transaction") ON DELETE RESTRICT DEFERRABLE INITIALLY IMMEDIATE;

ALTER TABLE "reconciliation_history" ADD FOREIGN KEY ("id_user") REFERENCES "users" ("id_user") ON DELETE RESTRICT DEFERRABLE INITIALLY IMMEDIATE;


-- =====================================================================
-- Clinic Finance DB v3 - rules DBML can't express.
--
-- Run order on an empty database:
--   1. Clinic_export_v3_Postgresql.sql   (tables, from dbdiagram)
--   2. clinic_finance_v3_constraints.sql (this file)
--   3. seed_v3.sql                       (roles, permissions, lookups)
--
-- Sections
--   1. Reconciliation: one active link per pair
--   2-3. Operator allocations: no overlap, total <= 100%
--   4. Reconciliation validation (type, clinic, counterparty, amounts)
--   5. Guards on reconciled transactions / invoices
--   6. Invoice lines (type, total, service line clinic, void)
--   7. Invoice total = sum of lines (checked at COMMIT)
--   8. Access grants (user_clinic_access)
--   9. Append-only tables (audit_log, reconciliation_history)
--  10. Database-level audit (every insert/update/delete -> audit_log)
--  11. updated_at maintenance
--  12. Views
--
-- The app tells the database who is acting, at the start of each
-- transaction:
--   SET LOCAL app.user_id = '42';
--   SET LOCAL app.client_ip = '10.0.0.5';
-- The audit triggers read these. If they're not set, id_user is NULL
-- (= system action).
-- =====================================================================

CREATE EXTENSION IF NOT EXISTS btree_gist;

-- ---------------------------------------------------------------------
-- 1. One ACTIVE reconciliation per (invoice, transaction)
--    (a reversed one doesn't block re-applying later)
-- ---------------------------------------------------------------------
CREATE UNIQUE INDEX uq_reconciliation_active_pair
  ON reconciliation_history (id_invoice, id_transaction)
  WHERE reversed_at IS NULL;

-- ---------------------------------------------------------------------
-- 2. A user can't be assigned twice to the same target in overlapping periods
-- ---------------------------------------------------------------------
ALTER TABLE operator_allocations
  ADD CONSTRAINT ex_alloc_no_overlap_asset
    EXCLUDE USING gist (
      id_user WITH =,
      id_asset WITH =,
      daterange(assigned_at, retracted_at, '[]') WITH &&
    ) WHERE (id_asset IS NOT NULL),
  ADD CONSTRAINT ex_alloc_no_overlap_service
    EXCLUDE USING gist (
      id_user WITH =,
      id_service_line WITH =,
      daterange(assigned_at, retracted_at, '[]') WITH &&
    ) WHERE (id_service_line IS NOT NULL);

-- ---------------------------------------------------------------------
-- 3. A user's total allocation can't exceed 100% at any point in time.
--    Totals only change on start dates, so test the new row's start date
--    plus every other start date that falls inside its range.
-- ---------------------------------------------------------------------
CREATE OR REPLACE FUNCTION trg_allocation_total_check() RETURNS trigger AS $$
DECLARE
  d     DATE;
  total NUMERIC;
BEGIN
  -- serialize concurrent changes for the same user
  PERFORM 1 FROM users WHERE id_user = NEW.id_user FOR UPDATE;

  FOR d IN
    SELECT NEW.assigned_at
    UNION
    SELECT assigned_at
      FROM operator_allocations
     WHERE id_user = NEW.id_user
       AND id_allocation IS DISTINCT FROM NEW.id_allocation
       AND assigned_at BETWEEN NEW.assigned_at AND COALESCE(NEW.retracted_at, 'infinity'::date)
  LOOP
    SELECT COALESCE(SUM(allocation_percentage), 0) INTO total
      FROM operator_allocations
     WHERE id_user = NEW.id_user
       AND id_allocation IS DISTINCT FROM NEW.id_allocation
       AND assigned_at <= d
       AND (retracted_at IS NULL OR retracted_at >= d);

    IF total + NEW.allocation_percentage > 100 THEN
      RAISE EXCEPTION 'User % would be allocated % percent on %, above the 100 percent limit',
        NEW.id_user, total + NEW.allocation_percentage, d;
    END IF;
  END LOOP;

  RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER allocation_total_check
  BEFORE INSERT OR UPDATE ON operator_allocations
  FOR EACH ROW EXECUTE FUNCTION trg_allocation_total_check();

-- ---------------------------------------------------------------------
-- 4. Reconciliation validation
-- ---------------------------------------------------------------------
CREATE OR REPLACE FUNCTION trg_reconciliation_validate() RETURNS trigger AS $$
DECLARE
  v_inv       invoices%ROWTYPE;
  v_trx       transactions%ROWTYPE;
  v_trx_type  enum_financial_type;
  v_applied   NUMERIC;
BEGIN
  -- history is append-only: only reversed_at may change
  IF TG_OP = 'UPDATE' THEN
    IF (NEW.id_invoice, NEW.id_transaction, NEW.id_user, NEW.applied_amount, NEW.reconciliation_date)
       IS DISTINCT FROM
       (OLD.id_invoice, OLD.id_transaction, OLD.id_user, OLD.applied_amount, OLD.reconciliation_date) THEN
      RAISE EXCEPTION 'reconciliation_history rows are immutable; reverse them instead';
    END IF;
    IF OLD.reversed_at IS NOT NULL AND NEW.reversed_at IS NULL THEN
      RAISE EXCEPTION 'A reversed reconciliation cannot be re-activated; create a new one';
    END IF;
  END IF;

  -- reversing needs no further checks
  IF NEW.reversed_at IS NOT NULL THEN
    RETURN NEW;
  END IF;

  -- lock parents in a fixed order (invoice, then transaction)
  SELECT * INTO v_inv FROM invoices     WHERE id_invoice     = NEW.id_invoice     FOR UPDATE;
  SELECT * INTO v_trx FROM transactions WHERE id_transaction = NEW.id_transaction FOR UPDATE;

  IF v_inv.is_void THEN
    RAISE EXCEPTION 'Invoice % is void', v_inv.id_invoice;
  END IF;
  IF v_trx.transaction_status <> 'Completed' THEN
    RAISE EXCEPTION 'Transaction % is %, only Completed transactions can be reconciled',
      v_trx.id_transaction, v_trx.transaction_status;
  END IF;
  IF v_inv.id_clinic <> v_trx.id_clinic THEN
    RAISE EXCEPTION 'Invoice and transaction belong to different clinics';
  END IF;

  -- direction must match: receivable <-> income, payable <-> expense
  SELECT financial_type INTO v_trx_type FROM financial_categories WHERE id_category = v_trx.id_category;
  IF v_inv.financial_type <> v_trx_type THEN
    RAISE EXCEPTION 'Invoice is % but transaction is %', v_inv.financial_type, v_trx_type;
  END IF;

  -- if the transaction says who paid, it must be the invoice's counterparty
  IF v_trx.id_counterparty IS NOT NULL AND v_trx.id_counterparty <> v_inv.id_counterparty THEN
    RAISE EXCEPTION 'Transaction % is from counterparty % but invoice % belongs to counterparty %',
      v_trx.id_transaction, v_trx.id_counterparty, v_inv.id_invoice, v_inv.id_counterparty;
  END IF;

  -- invoice cannot be overpaid
  SELECT COALESCE(SUM(applied_amount), 0) INTO v_applied
    FROM reconciliation_history
   WHERE id_invoice = NEW.id_invoice
     AND reversed_at IS NULL
     AND id_reconciliation IS DISTINCT FROM NEW.id_reconciliation;
  IF v_applied + NEW.applied_amount > v_inv.total_amount THEN
    RAISE EXCEPTION 'Applying % exceeds invoice % total (% already applied of %)',
      NEW.applied_amount, v_inv.id_invoice, v_applied, v_inv.total_amount;
  END IF;

  -- transaction cannot be over-allocated
  SELECT COALESCE(SUM(applied_amount), 0) INTO v_applied
    FROM reconciliation_history
   WHERE id_transaction = NEW.id_transaction
     AND reversed_at IS NULL
     AND id_reconciliation IS DISTINCT FROM NEW.id_reconciliation;
  IF v_applied + NEW.applied_amount > v_trx.amount THEN
    RAISE EXCEPTION 'Applying % exceeds transaction % amount (% already applied of %)',
      NEW.applied_amount, v_trx.id_transaction, v_applied, v_trx.amount;
  END IF;

  RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER reconciliation_validate
  BEFORE INSERT OR UPDATE ON reconciliation_history
  FOR EACH ROW EXECUTE FUNCTION trg_reconciliation_validate();

-- ---------------------------------------------------------------------
-- 5. Guards: can't edit a reconciled transaction/invoice into an
--    inconsistent state
-- ---------------------------------------------------------------------
CREATE OR REPLACE FUNCTION trg_transactions_guard() RETURNS trigger AS $$
DECLARE
  v_applied NUMERIC;
BEGIN
  SELECT COALESCE(SUM(applied_amount), 0) INTO v_applied
    FROM reconciliation_history
   WHERE id_transaction = NEW.id_transaction AND reversed_at IS NULL;

  IF v_applied > 0 THEN
    IF NEW.transaction_status <> 'Completed' THEN
      RAISE EXCEPTION 'Transaction % has active reconciliations; reverse them before changing its status', NEW.id_transaction;
    END IF;
    IF NEW.amount < v_applied THEN
      RAISE EXCEPTION 'Transaction % amount cannot drop below the % already applied', NEW.id_transaction, v_applied;
    END IF;
    IF NEW.id_clinic <> OLD.id_clinic OR NEW.id_category <> OLD.id_category THEN
      RAISE EXCEPTION 'Clinic/category of a reconciled transaction cannot change';
    END IF;
    IF NEW.id_counterparty IS DISTINCT FROM OLD.id_counterparty
       AND NEW.id_counterparty IS NOT NULL
       AND EXISTS (SELECT 1
                     FROM reconciliation_history r
                     JOIN invoices i ON i.id_invoice = r.id_invoice
                    WHERE r.id_transaction = NEW.id_transaction
                      AND r.reversed_at IS NULL
                      AND i.id_counterparty <> NEW.id_counterparty) THEN
      RAISE EXCEPTION 'Transaction % is reconciled with invoices of a different counterparty', NEW.id_transaction;
    END IF;
  END IF;
  RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER transactions_guard
  BEFORE UPDATE ON transactions
  FOR EACH ROW EXECUTE FUNCTION trg_transactions_guard();

CREATE OR REPLACE FUNCTION trg_invoices_guard() RETURNS trigger AS $$
DECLARE
  v_applied NUMERIC;
BEGIN
  SELECT COALESCE(SUM(applied_amount), 0) INTO v_applied
    FROM reconciliation_history
   WHERE id_invoice = NEW.id_invoice AND reversed_at IS NULL;

  IF v_applied > 0 THEN
    IF NEW.is_void THEN
      RAISE EXCEPTION 'Invoice % has active reconciliations; reverse them before voiding', NEW.id_invoice;
    END IF;
    IF NEW.total_amount < v_applied THEN
      RAISE EXCEPTION 'Invoice % total cannot drop below the % already applied', NEW.id_invoice, v_applied;
    END IF;
    IF NEW.id_clinic <> OLD.id_clinic
       OR NEW.financial_type <> OLD.financial_type
       OR NEW.id_counterparty <> OLD.id_counterparty THEN
      RAISE EXCEPTION 'Clinic/type/counterparty of a reconciled invoice cannot change';
    END IF;
  END IF;

  -- a voided invoice stays void
  IF OLD.is_void AND NOT NEW.is_void THEN
    RAISE EXCEPTION 'Invoice % is void and cannot be un-voided; create a new invoice', NEW.id_invoice;
  END IF;

  -- moving an invoice to another clinic: its lines' service lines must follow
  IF NEW.id_clinic <> OLD.id_clinic AND EXISTS (
       SELECT 1 FROM invoice_lines l
         JOIN service_lines s ON s.id_service_line = l.id_service_line
        WHERE l.id_invoice = NEW.id_invoice AND s.id_clinic <> NEW.id_clinic) THEN
    RAISE EXCEPTION 'Invoice % has lines with service lines from another clinic', NEW.id_invoice;
  END IF;

  RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER invoices_guard
  BEFORE UPDATE ON invoices
  FOR EACH ROW EXECUTE FUNCTION trg_invoices_guard();

-- ---------------------------------------------------------------------
-- 6. Invoice lines
--    * financial_type is copied from the invoice automatically (the
--      composite FK then forces the category to have the same type)
--    * line_total is calculated automatically
--    * service line must belong to the invoice's clinic
--    * lines of a void invoice can't change
-- ---------------------------------------------------------------------
CREATE OR REPLACE FUNCTION trg_invoice_lines_validate() RETURNS trigger AS $$
DECLARE
  v_inv invoices%ROWTYPE;
BEGIN
  IF TG_OP = 'DELETE' THEN
    SELECT * INTO v_inv FROM invoices WHERE id_invoice = OLD.id_invoice;
    IF v_inv.is_void THEN
      RAISE EXCEPTION 'Invoice % is void; its lines cannot change', OLD.id_invoice;
    END IF;
    RETURN OLD;
  END IF;

  -- moving a line off a void invoice is also a change to that invoice
  IF TG_OP = 'UPDATE' THEN
    IF NEW.id_invoice <> OLD.id_invoice
       AND EXISTS (SELECT 1 FROM invoices WHERE id_invoice = OLD.id_invoice AND is_void) THEN
      RAISE EXCEPTION 'Invoice % is void; its lines cannot change', OLD.id_invoice;
    END IF;
  END IF;

  SELECT * INTO v_inv FROM invoices WHERE id_invoice = NEW.id_invoice;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'Invoice % does not exist', NEW.id_invoice;
  END IF;
  IF v_inv.is_void THEN
    RAISE EXCEPTION 'Invoice % is void; its lines cannot change', NEW.id_invoice;
  END IF;

  NEW.financial_type := v_inv.financial_type;
  NEW.line_total     := ROUND(NEW.quantity * NEW.unit_price, 2);

  IF NEW.id_service_line IS NOT NULL AND NOT EXISTS (
       SELECT 1 FROM service_lines
        WHERE id_service_line = NEW.id_service_line AND id_clinic = v_inv.id_clinic) THEN
    RAISE EXCEPTION 'Service line % does not belong to clinic % of invoice %',
      NEW.id_service_line, v_inv.id_clinic, v_inv.id_invoice;
  END IF;

  RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER invoice_lines_validate
  BEFORE INSERT OR UPDATE OR DELETE ON invoice_lines
  FOR EACH ROW EXECUTE FUNCTION trg_invoice_lines_validate();

-- ---------------------------------------------------------------------
-- 7. Invoice total must equal the sum of its lines.
--    Checked at COMMIT (deferred), so the app can insert the header and
--    then its lines inside one transaction. An invoice with no lines
--    fails too (total must be > 0).
--    To check earlier inside a transaction:
--      SET CONSTRAINTS invoice_total_on_invoice, invoice_total_on_lines IMMEDIATE;
-- ---------------------------------------------------------------------
CREATE OR REPLACE FUNCTION trg_invoice_total_check() RETURNS trigger AS $$
DECLARE
  v_ids   INT[] := '{}';
  v_id    INT;
  v_total NUMERIC;
  v_sum   NUMERIC;
BEGIN
  IF TG_OP <> 'DELETE' THEN
    v_ids := v_ids || NEW.id_invoice;
  END IF;
  IF TG_OP <> 'INSERT' THEN
    v_ids := v_ids || OLD.id_invoice;
  END IF;

  FOR v_id IN SELECT DISTINCT x FROM unnest(v_ids) AS x
  LOOP
    SELECT total_amount INTO v_total FROM invoices WHERE id_invoice = v_id;
    CONTINUE WHEN NOT FOUND;
    SELECT COALESCE(SUM(line_total), 0) INTO v_sum FROM invoice_lines WHERE id_invoice = v_id;
    IF v_total <> v_sum THEN
      RAISE EXCEPTION 'Invoice % total is % but its lines add up to %', v_id, v_total, v_sum;
    END IF;
  END LOOP;
  RETURN NULL;
END;
$$ LANGUAGE plpgsql;

CREATE CONSTRAINT TRIGGER invoice_total_on_invoice
  AFTER INSERT OR UPDATE ON invoices
  DEFERRABLE INITIALLY DEFERRED
  FOR EACH ROW EXECUTE FUNCTION trg_invoice_total_check();

CREATE CONSTRAINT TRIGGER invoice_total_on_lines
  AFTER INSERT OR UPDATE OR DELETE ON invoice_lines
  DEFERRABLE INITIALLY DEFERRED
  FOR EACH ROW EXECUTE FUNCTION trg_invoice_total_check();

-- ---------------------------------------------------------------------
-- 8. Access grants (user_clinic_access)
--    * the granter must be active and hold the access.grant permission
--    * the receiver must be active
--    * rows are never deleted; only revoked_at may be set (once)
-- ---------------------------------------------------------------------
CREATE OR REPLACE FUNCTION trg_access_validate() RETURNS trigger AS $$
BEGIN
  IF TG_OP = 'DELETE' THEN
    RAISE EXCEPTION 'user_clinic_access rows cannot be deleted; set revoked_at instead';
  END IF;

  IF TG_OP = 'UPDATE' THEN
    IF (NEW.id_user, NEW.id_clinic, NEW.id_granted_by, NEW.reason, NEW.granted_at, NEW.expires_at)
       IS DISTINCT FROM
       (OLD.id_user, OLD.id_clinic, OLD.id_granted_by, OLD.reason, OLD.granted_at, OLD.expires_at) THEN
      RAISE EXCEPTION 'Access grants are immutable; revoke it and create a new one';
    END IF;
    IF OLD.revoked_at IS NOT NULL THEN
      RAISE EXCEPTION 'Access grant % is already revoked', OLD.id_access;
    END IF;
    RETURN NEW;
  END IF;

  -- INSERT
  IF NOT EXISTS (
       SELECT 1 FROM users u
         JOIN role_permissions rp ON rp.id_role = u.id_role
         JOIN permissions p       ON p.id_permission = rp.id_permission
        WHERE u.id_user = NEW.id_granted_by AND u.active AND p.permission_code = 'access.grant') THEN
    RAISE EXCEPTION 'User % is not allowed to grant clinic access (needs access.grant)', NEW.id_granted_by;
  END IF;
  IF NOT EXISTS (SELECT 1 FROM users WHERE id_user = NEW.id_user AND active) THEN
    RAISE EXCEPTION 'User % is inactive and cannot receive access', NEW.id_user;
  END IF;
  RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER access_validate
  BEFORE INSERT OR UPDATE OR DELETE ON user_clinic_access
  FOR EACH ROW EXECUTE FUNCTION trg_access_validate();

-- ---------------------------------------------------------------------
-- 9. Append-only tables
-- ---------------------------------------------------------------------
CREATE OR REPLACE FUNCTION trg_append_only() RETURNS trigger AS $$
BEGIN
  RAISE EXCEPTION '% is append-only: rows cannot be %d', TG_TABLE_NAME, lower(TG_OP);
END;
$$ LANGUAGE plpgsql;

-- audit_log: no update, no delete, no truncate
CREATE TRIGGER audit_log_append_only
  BEFORE UPDATE OR DELETE ON audit_log
  FOR EACH ROW EXECUTE FUNCTION trg_append_only();
CREATE TRIGGER audit_log_no_truncate
  BEFORE TRUNCATE ON audit_log
  FOR EACH STATEMENT EXECUTE FUNCTION trg_append_only();

-- reconciliation_history: updates are checked in section 4 (only reversed_at)
CREATE TRIGGER reconciliation_no_delete
  BEFORE DELETE ON reconciliation_history
  FOR EACH ROW EXECUTE FUNCTION trg_append_only();
CREATE TRIGGER reconciliation_no_truncate
  BEFORE TRUNCATE ON reconciliation_history
  FOR EACH STATEMENT EXECUTE FUNCTION trg_append_only();

-- ---------------------------------------------------------------------
-- 10. Database-level audit: every insert / update / delete on the
--     business tables writes a row to audit_log, even if the app
--     forgets to. action = db_insert / db_update / db_delete.
--     * id_user / ip come from SET LOCAL app.user_id / app.client_ip
--     * updates store only the changed columns (old -> new)
--     * password_hash values are never copied into the log
-- ---------------------------------------------------------------------
CREATE OR REPLACE FUNCTION trg_audit_row() RETURNS trigger AS $$
DECLARE
  v_pk      TEXT  := TG_ARGV[0];
  v_user    INT   := NULLIF(current_setting('app.user_id', true), '')::int;
  v_ip      TEXT  := NULLIF(current_setting('app.client_ip', true), '');
  v_old     JSONB;
  v_new     JSONB;
  v_row     JSONB;
  v_changes JSONB;
  v_details JSONB;
  v_clinic  INT;
  v_record  BIGINT;
BEGIN
  IF TG_OP IN ('UPDATE', 'DELETE') THEN v_old := to_jsonb(OLD) - 'password_hash'; END IF;
  IF TG_OP IN ('INSERT', 'UPDATE') THEN v_new := to_jsonb(NEW) - 'password_hash'; END IF;
  v_row := COALESCE(v_new, v_old);

  IF TG_OP = 'UPDATE' THEN
    SELECT jsonb_object_agg(n.key, jsonb_build_object('old', o.value, 'new', n.value))
      INTO v_changes
      FROM jsonb_each(v_new) n
      JOIN jsonb_each(v_old) o USING (key)
     WHERE n.value IS DISTINCT FROM o.value
       AND n.key <> 'updated_at';
    IF to_jsonb(NEW) -> 'password_hash' IS DISTINCT FROM to_jsonb(OLD) -> 'password_hash' THEN
      v_changes := COALESCE(v_changes, '{}'::jsonb) || '{"password_hash": "changed"}'::jsonb;
    END IF;
    IF v_changes IS NULL THEN
      RETURN NULL;   -- nothing really changed
    END IF;
    v_details := jsonb_build_object('changes', v_changes);
  ELSIF TG_OP = 'INSERT' THEN
    v_details := jsonb_build_object('new', v_new);
  ELSE
    v_details := jsonb_build_object('old', v_old);
  END IF;

  IF v_pk <> '' THEN
    v_record := (v_row ->> v_pk)::bigint;
  END IF;

  -- which clinic's data was touched
  v_clinic := (v_row ->> 'id_clinic')::int;
  IF v_clinic IS NULL AND v_row ? 'id_invoice' THEN
    SELECT id_clinic INTO v_clinic FROM invoices WHERE id_invoice = (v_row ->> 'id_invoice')::int;
  END IF;

  INSERT INTO audit_log (id_user, id_clinic, action, table_name, record_id, details, ip_address)
  VALUES (v_user, v_clinic, 'db_' || lower(TG_OP), TG_TABLE_NAME, v_record, v_details, v_ip);

  RETURN NULL;
END;
$$ LANGUAGE plpgsql;

DO $$
DECLARE
  r RECORD;
BEGIN
  -- table name, primary key column ('' = composite key)
  FOR r IN SELECT * FROM (VALUES
    ('clinics',                 'id_clinic'),
    ('roles',                   'id_role'),
    ('permissions',             'id_permission'),
    ('role_permissions',        ''),
    ('users',                   'id_user'),
    ('user_clinic_access',      'id_access'),
    ('financial_categories',    'id_category'),
    ('payment_methods',         'id_method'),
    ('depreciation_categories', 'id_dep_category'),
    ('counterparties',          'id_counterparty'),
    ('service_lines',           'id_service_line'),
    ('clinic_assets',           'id_asset'),
    ('operator_allocations',    'id_allocation'),
    ('transactions',            'id_transaction'),
    ('invoices',                'id_invoice'),
    ('invoice_lines',           'id_line'),
    ('reconciliation_history',  'id_reconciliation')
  ) AS t(tbl, pk)
  LOOP
    EXECUTE format(
      'CREATE TRIGGER audit_row AFTER INSERT OR UPDATE OR DELETE ON %I
       FOR EACH ROW EXECUTE FUNCTION trg_audit_row(%L)', r.tbl, r.pk);
  END LOOP;
END $$;

-- ---------------------------------------------------------------------
-- 11. updated_at maintenance
-- ---------------------------------------------------------------------
CREATE OR REPLACE FUNCTION trg_set_updated_at() RETURNS trigger AS $$
BEGIN
  NEW.updated_at := now();
  RETURN NEW;
END;
$$ LANGUAGE plpgsql;

DO $$
DECLARE t TEXT;
BEGIN
  FOREACH t IN ARRAY ARRAY[
    'clinics','users','counterparties','service_lines','clinic_assets',
    'operator_allocations','transactions','invoices','invoice_lines'
  ] LOOP
    EXECUTE format(
      'CREATE TRIGGER set_updated_at BEFORE UPDATE ON %I
       FOR EACH ROW EXECUTE FUNCTION trg_set_updated_at()', t);
  END LOOP;
END $$;

-- ---------------------------------------------------------------------
-- 12. Views
-- ---------------------------------------------------------------------

-- Invoice balances. Void invoices show status 'Void' and 0 outstanding.
CREATE VIEW v_invoice_balances AS
WITH paid AS (
  SELECT id_invoice, SUM(applied_amount) AS amount_paid
    FROM reconciliation_history
   WHERE reversed_at IS NULL
   GROUP BY id_invoice
)
SELECT i.id_invoice,
       i.id_clinic,
       i.id_counterparty,
       i.invoice_number,
       i.financial_type,
       CASE i.financial_type
         WHEN 'Income' THEN 'Accounts Receivable'
         ELSE 'Accounts Payable'
       END                                                   AS invoice_type,
       i.is_void,
       i.total_amount,
       COALESCE(p.amount_paid, 0)                            AS amount_paid,
       CASE WHEN i.is_void THEN 0
            ELSE i.total_amount - COALESCE(p.amount_paid, 0)
       END                                                   AS outstanding,
       CASE
         WHEN i.is_void                                    THEN 'Void'
         WHEN COALESCE(p.amount_paid, 0) = 0               THEN 'Pending'
         WHEN COALESCE(p.amount_paid, 0) < i.total_amount  THEN 'Partial'
         ELSE 'Reconciled'
       END                                                   AS reconciliation_status,
       i.issue_date,
       i.due_date
  FROM invoices i
  LEFT JOIN paid p ON p.id_invoice = i.id_invoice;

-- Ledger: ONLY Completed transactions, with signed amount (+ income, - expense).
-- Reports should read from here, never from transactions directly.
CREATE VIEW v_ledger AS
SELECT t.id_transaction,
       t.id_clinic,
       t.transaction_date,
       t.id_category,
       fc.category_name,
       fc.financial_type,
       t.amount,
       CASE fc.financial_type WHEN 'Income' THEN t.amount ELSE -t.amount END AS signed_amount,
       t.id_method,
       t.id_counterparty,
       t.id_payee_user,
       t.id_asset,
       t.asset_link_type,
       t.id_service_line,
       t.description
  FROM transactions t
  JOIN financial_categories fc ON fc.id_category = t.id_category
 WHERE t.transaction_status = 'Completed';

-- Assets with derived "fully depreciated" flag
CREATE VIEW v_clinic_assets AS
SELECT a.*,
       (a.asset_status = 'Active'
        AND a.is_depreciable
        AND (a.depreciation_start_date + make_interval(months => dc.useful_life_months))::date <= CURRENT_DATE
       ) AS is_fully_depreciated
  FROM clinic_assets a
  LEFT JOIN depreciation_categories dc ON dc.id_dep_category = a.id_dep_category;

-- What each user may do (for the app's permission checks)
CREATE VIEW v_user_permissions AS
SELECT u.id_user, p.permission_code
  FROM users u
  JOIN role_permissions rp ON rp.id_role = u.id_role
  JOIN permissions p       ON p.id_permission = rp.id_permission
 WHERE u.active;

-- Which clinics each user may see right now, and why
--   home        = their own clinic
--   all_clinics = role has clinics.view_all
--   grant       = active temporary grant in user_clinic_access
CREATE VIEW v_user_clinics AS
SELECT u.id_user, u.id_clinic, 'home'::text AS access_via, NULL::timestamptz AS expires_at
  FROM users u
 WHERE u.active AND u.id_clinic IS NOT NULL
UNION
SELECT up.id_user, c.id_clinic, 'all_clinics', NULL
  FROM v_user_permissions up
 CROSS JOIN clinics c
 WHERE up.permission_code = 'clinics.view_all' AND c.active
UNION
SELECT a.id_user, a.id_clinic, 'grant', a.expires_at
  FROM user_clinic_access a
  JOIN users u ON u.id_user = a.id_user
 WHERE u.active AND a.revoked_at IS NULL AND now() < a.expires_at;


-- migrate:down
DO $$ BEGIN RAISE EXCEPTION 'The base schema cannot be rolled back. Recreate the database instead.'; END $$;
