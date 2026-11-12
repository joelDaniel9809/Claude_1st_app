-- migrate:up
-- Additions the app needs (docs/APP_PLAN.md §8.4):
--   * users: language, two-factor, lockout, first-login password change
--   * counterparties: type (patient/supplier/insurer) and owning clinic
--   * clinics: short code for bill numbers
--   * gap-free bill numbering per clinic and year
--   * audit log also masks two-factor secrets

-- ---------------------------------------------------------------------
-- Users
-- ---------------------------------------------------------------------
ALTER TABLE users
  ADD COLUMN preferred_language   varchar(2)  NOT NULL DEFAULT 'es',
  ADD COLUMN totp_secret          text,
  ADD COLUMN totp_enabled         boolean     NOT NULL DEFAULT false,
  ADD COLUMN failed_login_count   int         NOT NULL DEFAULT 0,
  ADD COLUMN locked_until         timestamptz,
  ADD COLUMN last_login_at        timestamptz,
  ADD COLUMN must_change_password boolean     NOT NULL DEFAULT true,
  ADD CONSTRAINT chk_user_language      CHECK (preferred_language IN ('es', 'en')),
  ADD CONSTRAINT chk_user_failed_logins CHECK (failed_login_count >= 0),
  ADD CONSTRAINT chk_user_totp          CHECK (NOT totp_enabled OR totp_secret IS NOT NULL);

COMMENT ON COLUMN users.preferred_language   IS 'Screen language: es or en';
COMMENT ON COLUMN users.totp_secret          IS 'Two-factor secret, encrypted by the app. Never written to audit_log';
COMMENT ON COLUMN users.failed_login_count   IS 'Consecutive failed logins; reset on success';
COMMENT ON COLUMN users.locked_until         IS 'Login blocked until this time after too many failures';
COMMENT ON COLUMN users.must_change_password IS 'True for invited users until they set their own password';

-- ---------------------------------------------------------------------
-- Counterparties: type and owning clinic
-- ---------------------------------------------------------------------
CREATE TYPE enum_counterparty_type AS ENUM ('Patient', 'Supplier', 'Insurer', 'Other');

ALTER TABLE counterparties
  ADD COLUMN counterparty_type enum_counterparty_type NOT NULL DEFAULT 'Patient',
  ADD COLUMN id_clinic int REFERENCES clinics (id_clinic) ON DELETE RESTRICT;

CREATE INDEX idx_counterparties_clinic ON counterparties (id_clinic);

COMMENT ON COLUMN counterparties.counterparty_type IS 'Patient, Supplier, Insurer or Other';
COMMENT ON COLUMN counterparties.id_clinic IS 'Owning clinic. NULL = shared by all clinics (e.g. a common supplier or insurer). Patients should always have a clinic';

-- An invoice or transaction can only use a counterparty of its own clinic (or a shared one)
CREATE OR REPLACE FUNCTION trg_counterparty_clinic_check() RETURNS trigger AS $$
DECLARE
  v_clinic INT;
BEGIN
  IF NEW.id_counterparty IS NOT NULL THEN
    SELECT id_clinic INTO v_clinic FROM counterparties WHERE id_counterparty = NEW.id_counterparty;
    IF v_clinic IS NOT NULL AND v_clinic <> NEW.id_clinic THEN
      RAISE EXCEPTION 'Counterparty % belongs to clinic %, not clinic %',
        NEW.id_counterparty, v_clinic, NEW.id_clinic;
    END IF;
  END IF;
  RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER counterparty_clinic_check
  BEFORE INSERT OR UPDATE OF id_counterparty, id_clinic ON invoices
  FOR EACH ROW EXECUTE FUNCTION trg_counterparty_clinic_check();

CREATE TRIGGER counterparty_clinic_check
  BEFORE INSERT OR UPDATE OF id_counterparty, id_clinic ON transactions
  FOR EACH ROW EXECUTE FUNCTION trg_counterparty_clinic_check();

-- Moving a counterparty to a clinic: it must not already be used by another clinic
CREATE OR REPLACE FUNCTION trg_counterparty_move_check() RETURNS trigger AS $$
BEGIN
  IF NEW.id_clinic IS NOT NULL AND NEW.id_clinic IS DISTINCT FROM OLD.id_clinic AND (
       EXISTS (SELECT 1 FROM invoices     WHERE id_counterparty = NEW.id_counterparty AND id_clinic <> NEW.id_clinic) OR
       EXISTS (SELECT 1 FROM transactions WHERE id_counterparty = NEW.id_counterparty AND id_clinic <> NEW.id_clinic)) THEN
    RAISE EXCEPTION 'Counterparty % already has records in another clinic and cannot be limited to clinic %',
      NEW.id_counterparty, NEW.id_clinic;
  END IF;
  RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER counterparty_move_check
  BEFORE UPDATE OF id_clinic ON counterparties
  FOR EACH ROW EXECUTE FUNCTION trg_counterparty_move_check();

-- ---------------------------------------------------------------------
-- Clinics: short code (used in bill numbers, e.g. NOR-2026-0001)
-- ---------------------------------------------------------------------
ALTER TABLE clinics ADD COLUMN clinic_code varchar(10);
UPDATE clinics SET clinic_code = 'C' || id_clinic WHERE clinic_code IS NULL;
ALTER TABLE clinics
  ALTER COLUMN clinic_code SET NOT NULL,
  ADD CONSTRAINT uq_clinic_code  UNIQUE (clinic_code),
  ADD CONSTRAINT chk_clinic_code CHECK (clinic_code ~ '^[A-Z0-9]{2,10}$');

COMMENT ON COLUMN clinics.clinic_code IS 'Short unique code, 2-10 capital letters/digits. Used in bill numbers';

-- ---------------------------------------------------------------------
-- Gap-free bill numbers per clinic and year
-- Call next_invoice_number() in the SAME transaction that inserts the
-- invoice: if that transaction fails, the number is not used up.
-- ---------------------------------------------------------------------
CREATE TABLE invoice_number_sequences (
  id_clinic   int NOT NULL REFERENCES clinics (id_clinic) ON DELETE RESTRICT,
  year        int NOT NULL,
  last_number int NOT NULL DEFAULT 0,
  PRIMARY KEY (id_clinic, year),
  CONSTRAINT chk_invseq_nonneg CHECK (last_number >= 0)
);

COMMENT ON TABLE invoice_number_sequences IS 'Last bill number used per clinic and year. Only next_invoice_number() should change it';

CREATE OR REPLACE FUNCTION next_invoice_number(p_clinic int, p_issue_date date DEFAULT CURRENT_DATE)
RETURNS varchar AS $$
DECLARE
  v_code varchar;
  v_year int := extract(year FROM p_issue_date)::int;
  v_next int;
BEGIN
  SELECT clinic_code INTO v_code FROM clinics WHERE id_clinic = p_clinic;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'Clinic % does not exist', p_clinic;
  END IF;

  INSERT INTO invoice_number_sequences (id_clinic, year, last_number)
  VALUES (p_clinic, v_year, 1)
  ON CONFLICT (id_clinic, year)
  DO UPDATE SET last_number = invoice_number_sequences.last_number + 1
  RETURNING last_number INTO v_next;

  RETURN v_code || '-' || v_year || '-' || lpad(v_next::text, 4, '0');
END;
$$ LANGUAGE plpgsql;

-- ---------------------------------------------------------------------
-- Audit log: never copy password hashes or two-factor secrets
-- (replaces the v3 version of the function; triggers keep using it)
-- ---------------------------------------------------------------------
CREATE OR REPLACE FUNCTION trg_audit_row() RETURNS trigger AS $$
DECLARE
  v_secrets CONSTANT TEXT[] := ARRAY['password_hash', 'totp_secret'];
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
  v_col     TEXT;
BEGIN
  IF TG_OP IN ('UPDATE', 'DELETE') THEN v_old := to_jsonb(OLD) - v_secrets; END IF;
  IF TG_OP IN ('INSERT', 'UPDATE') THEN v_new := to_jsonb(NEW) - v_secrets; END IF;
  v_row := COALESCE(v_new, v_old);

  IF TG_OP = 'UPDATE' THEN
    SELECT jsonb_object_agg(n.key, jsonb_build_object('old', o.value, 'new', n.value))
      INTO v_changes
      FROM jsonb_each(v_new) n
      JOIN jsonb_each(v_old) o USING (key)
     WHERE n.value IS DISTINCT FROM o.value
       AND n.key <> 'updated_at';
    FOREACH v_col IN ARRAY v_secrets LOOP
      IF to_jsonb(NEW) -> v_col IS DISTINCT FROM to_jsonb(OLD) -> v_col THEN
        v_changes := COALESCE(v_changes, '{}'::jsonb) || jsonb_build_object(v_col, 'changed');
      END IF;
    END LOOP;
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

  v_clinic := (v_row ->> 'id_clinic')::int;
  IF v_clinic IS NULL AND v_row ? 'id_invoice' THEN
    SELECT id_clinic INTO v_clinic FROM invoices WHERE id_invoice = (v_row ->> 'id_invoice')::int;
  END IF;

  INSERT INTO audit_log (id_user, id_clinic, action, table_name, record_id, details, ip_address)
  VALUES (v_user, v_clinic, 'db_' || lower(TG_OP), TG_TABLE_NAME, v_record, v_details, v_ip);

  RETURN NULL;
END;
$$ LANGUAGE plpgsql;

-- migrate:down
DROP TRIGGER counterparty_move_check ON counterparties;
DROP TRIGGER counterparty_clinic_check ON transactions;
DROP TRIGGER counterparty_clinic_check ON invoices;
DROP FUNCTION trg_counterparty_move_check();
DROP FUNCTION trg_counterparty_clinic_check();
DROP FUNCTION next_invoice_number(int, date);
DROP TABLE invoice_number_sequences;
ALTER TABLE clinics DROP COLUMN clinic_code;
ALTER TABLE counterparties DROP COLUMN id_clinic, DROP COLUMN counterparty_type;
DROP TYPE enum_counterparty_type;
ALTER TABLE users
  DROP CONSTRAINT chk_user_totp,
  DROP CONSTRAINT chk_user_failed_logins,
  DROP CONSTRAINT chk_user_language,
  DROP COLUMN must_change_password,
  DROP COLUMN last_login_at,
  DROP COLUMN locked_until,
  DROP COLUMN failed_login_count,
  DROP COLUMN totp_enabled,
  DROP COLUMN totp_secret,
  DROP COLUMN preferred_language;
-- trg_audit_row keeps the stricter masking: harmless without the columns.
