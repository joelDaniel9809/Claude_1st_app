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
