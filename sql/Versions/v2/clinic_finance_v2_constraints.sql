-- =====================================================================
-- Run AFTER the tables generated from clinic_finance_v2.dbml exist.
-- Covers what DBML cannot express. NOTE: written carefully but not run
-- against a live PostgreSQL here, so test it on a scratch database first.
-- =====================================================================

CREATE EXTENSION IF NOT EXISTS btree_gist;

-- ---------------------------------------------------------------------
-- 1. Partial unique: one ACTIVE reconciliation per (invoice, transaction)
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
-- 3. A user's total allocation across all targets can't exceed 100%
--    at any point in time. Concurrent totals only change on start dates,
--    so it is enough to test the new row's start date plus every start
--    date of the user's other allocations that fall inside its range.
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
  v_inv_type  enum_financial_type;
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
  SELECT financial_type INTO v_inv_type FROM financial_categories WHERE id_category = v_inv.id_category;
  SELECT financial_type INTO v_trx_type FROM financial_categories WHERE id_category = v_trx.id_category;
  IF v_inv_type <> v_trx_type THEN
    RAISE EXCEPTION 'Invoice is % but transaction is %', v_inv_type, v_trx_type;
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

CREATE OR REPLACE FUNCTION trg_reconciliation_no_delete() RETURNS trigger AS $$
BEGIN
  RAISE EXCEPTION 'reconciliation_history is append-only; set reversed_at instead';
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER reconciliation_no_delete
  BEFORE DELETE ON reconciliation_history
  FOR EACH ROW EXECUTE FUNCTION trg_reconciliation_no_delete();

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
    IF NEW.id_clinic <> OLD.id_clinic OR NEW.id_category <> OLD.id_category THEN
      RAISE EXCEPTION 'Clinic/category of a reconciled invoice cannot change';
    END IF;
  END IF;
  RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER invoices_guard
  BEFORE UPDATE ON invoices
  FOR EACH ROW EXECUTE FUNCTION trg_invoices_guard();

-- ---------------------------------------------------------------------
-- 6. updated_at maintenance
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
    'operator_allocations','transactions','invoices'
  ] LOOP
    EXECUTE format(
      'CREATE TRIGGER set_updated_at BEFORE UPDATE ON %I
       FOR EACH ROW EXECUTE FUNCTION trg_set_updated_at()', t);
  END LOOP;
END $$;

-- ---------------------------------------------------------------------
-- 7. Views for values that used to be stored (and could go stale)
-- ---------------------------------------------------------------------
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
       i.id_category,
       i.is_void,
       CASE fc.financial_type
         WHEN 'Income' THEN 'Accounts Receivable'
         ELSE 'Accounts Payable'
       END                                              AS invoice_type,
       i.total_amount,
       COALESCE(p.amount_paid, 0)                       AS amount_paid,
       i.total_amount - COALESCE(p.amount_paid, 0)      AS outstanding,
       CASE
         WHEN COALESCE(p.amount_paid, 0) = 0               THEN 'Pending'
         WHEN COALESCE(p.amount_paid, 0) < i.total_amount  THEN 'Partial'
         ELSE 'Reconciled'
       END                                              AS reconciliation_status,
       i.issue_date,
       i.due_date
  FROM invoices i
  JOIN financial_categories fc ON fc.id_category = i.id_category
  LEFT JOIN paid p             ON p.id_invoice   = i.id_invoice;

CREATE VIEW v_clinic_assets AS
SELECT a.*,
       (a.asset_status = 'Active'
        AND a.is_depreciable
        AND (a.depreciation_start_date + make_interval(months => dc.useful_life_months))::date <= CURRENT_DATE
       ) AS is_fully_depreciated
  FROM clinic_assets a
  LEFT JOIN depreciation_categories dc ON dc.id_dep_category = a.id_dep_category;
