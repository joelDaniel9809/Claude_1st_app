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
