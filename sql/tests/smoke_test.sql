-- =====================================================================
-- Smoke test for Clinic Finance DB v3.
--
-- HOW TO RUN (pgAdmin): right-click the database -> Query Tool,
-- open this file, press Run (F5). Results are in the "Messages" tab:
-- one PASS / FAIL line per test, and a summary at the end.
-- HOW TO RUN (psql): psql -U postgres -h localhost -d clinic_scratch -f sql/tests/smoke_test.sql
--
-- Everything runs inside one transaction that ends with ROLLBACK, so
-- nothing is left behind. Test rows use ids 9001+ so they don't clash
-- with the seed data. Don't run it on a database that has real rows
-- with ids in the 9000s.
-- =====================================================================

BEGIN;

-- ---------------- helpers ----------------
CREATE TEMP TABLE test_results (n serial, line text) ON COMMIT DROP;

-- expect_fail: the statement MUST be rejected by the database
CREATE FUNCTION pg_temp.expect_fail(label text, stmt text) RETURNS void AS $$
DECLARE r text;
BEGIN
  BEGIN
    EXECUTE stmt;
    r := 'FAIL  ' || label || '  (statement was accepted)';
    RAISE EXCEPTION 'undo' USING ERRCODE = 'P0099';   -- undo what it did
  EXCEPTION
    WHEN SQLSTATE 'P0099' THEN NULL;
    WHEN OTHERS THEN r := 'PASS  ' || label || '  ->  ' || SQLERRM;
  END;
  EXECUTE 'SET CONSTRAINTS invoice_total_on_invoice, invoice_total_on_lines IMMEDIATE';
  INSERT INTO test_results (line) VALUES (r);
  RAISE NOTICE '%', r;
END $$ LANGUAGE plpgsql;

-- expect_ok: the statement MUST succeed (and its changes are kept)
CREATE FUNCTION pg_temp.expect_ok(label text, stmt text) RETURNS void AS $$
DECLARE r text;
BEGIN
  BEGIN
    EXECUTE stmt;
    r := 'PASS  ' || label;
  EXCEPTION WHEN OTHERS THEN
    r := 'FAIL  ' || label || '  ->  ' || SQLERRM;
  END;
  EXECUTE 'SET CONSTRAINTS invoice_total_on_invoice, invoice_total_on_lines IMMEDIATE';
  INSERT INTO test_results (line) VALUES (r);
  RAISE NOTICE '%', r;
END $$ LANGUAGE plpgsql;

-- ---------------- seed test data ----------------
INSERT INTO clinics (id_clinic, clinic_name) VALUES (9001, 'T North'), (9002, 'T South');
INSERT INTO roles (id_role, role_name) VALUES (9001, 'T Admin'), (9002, 'T Staff');
INSERT INTO role_permissions (id_role, id_permission)
  SELECT 9001, id_permission FROM permissions WHERE permission_code IN ('access.grant', 'audit.view');
INSERT INTO users (id_user, first_name, last_name, email, id_clinic, id_role, password_hash) VALUES
  (9001, 'Ana',  'Test', 'ana@test.local',  9001, 9001, 'hash-ana'),
  (9002, 'Ben',  'Test', 'ben@test.local',  9001, 9002, 'hash-ben'),
  (9003, 'Carl', 'Test', 'carl@test.local', NULL, 9002, 'hash-carl');

-- from here on, everything is done "as Ana" (shows up in audit_log)
SET LOCAL app.user_id = '9001';
SET LOCAL app.client_ip = '10.0.0.5';

INSERT INTO financial_categories (id_category, financial_type, category_name) VALUES
  (9001, 'Income', 'T Consults'), (9002, 'Expense', 'T Supplies'), (9003, 'Income', 'T Lab');
INSERT INTO payment_methods (id_method, method_name) VALUES (9001, 'T Cash');
INSERT INTO counterparties (id_counterparty, counterparty_name) VALUES (9001, 'Patient A'), (9002, 'Patient B');
INSERT INTO depreciation_categories (id_dep_category, category_name, useful_life_months) VALUES (9001, 'T Equipment', 12);
INSERT INTO clinic_assets (id_asset, id_clinic, asset_name, id_dep_category, depreciation_start_date, purchase_date) VALUES
  (9001, 9001, 'Ultrasound', 9001, '2024-01-01', '2024-01-01'),
  (9002, 9002, 'X-Ray',      9001, '2025-01-01', '2025-01-01');
INSERT INTO service_lines (id_service_line, id_clinic, service_name) VALUES
  (9001, 9001, 'T Office Visit'), (9002, 9002, 'T Office Visit');

INSERT INTO transactions (id_transaction, id_clinic, id_category, id_method, id_registered_by, id_counterparty, amount, transaction_status) VALUES
  (9001, 9001, 9001, 9001, 9001, 9001, 100, 'Completed'),   -- income 100 from Patient A
  (9002, 9001, 9002, 9001, 9001, NULL,  50, 'Completed'),   -- expense 50
  (9003, 9001, 9001, 9001, 9001, NULL,  40, 'Pending'),     -- pending income 40
  (9004, 9001, 9001, 9001, 9001, 9002,  30, 'Completed');   -- income 30 from Patient B

INSERT INTO invoices (id_invoice, id_clinic, id_counterparty, invoice_number, financial_type, total_amount, issue_date, due_date) VALUES
  (9001, 9001, 9001, 'N-0001', 'Income',   80, '2026-01-01', '2026-02-01'),
  (9002, 9001, 9001, 'N-0002', 'Income',  120, '2026-01-01', '2026-02-01'),
  (9003, 9002, 9001, 'S-0001', 'Income',   10, '2026-01-01', '2026-02-01'),
  (9004, 9001, 9001, 'SUP-77', 'Expense',  50, '2026-01-01', '2026-02-01');
INSERT INTO invoice_lines (id_line, id_invoice, line_number, description, id_category, id_service_line, quantity, unit_price, financial_type, line_total) VALUES
  (9001, 9001, 1, 'Consultation', 9001, 9001, 1, 50, 'Income', 0),   -- financial_type / line_total are filled in by the database
  (9002, 9001, 2, 'Blood test',   9003, NULL, 2, 15, 'Income', 0),
  (9003, 9002, 1, 'Procedure',    9001, NULL, 1, 120, 'Income', 0),
  (9004, 9003, 1, 'Consultation', 9001, 9002, 1, 10, 'Income', 0),
  (9005, 9004, 1, 'Gloves',       9002, NULL, 10, 5, 'Expense', 0);

-- check the invoice totals now instead of at the end
SET CONSTRAINTS invoice_total_on_invoice, invoice_total_on_lines IMMEDIATE;

-- ---------------- tests ----------------
DO $test$
DECLARE r text;
BEGIN
  RAISE NOTICE '=== valid operations (must succeed) ===';
  PERFORM pg_temp.expect_ok('line_total and financial_type filled in automatically',
    $q$DO $x$ BEGIN
         IF (SELECT line_total FROM invoice_lines WHERE id_line = 9002) <> 30 THEN RAISE EXCEPTION 'line_total wrong'; END IF;
       END $x$$q$);
  PERFORM pg_temp.expect_ok('reconcile 80 of invoice N-0001 with Patient A payment',
    'INSERT INTO reconciliation_history (id_reconciliation, id_invoice, id_transaction, id_user, applied_amount) VALUES (9001,9001,9001,9001,80)');
  PERFORM pg_temp.expect_ok('reconcile payable SUP-77 with expense trx',
    'INSERT INTO reconciliation_history (id_reconciliation, id_invoice, id_transaction, id_user, applied_amount) VALUES (9002,9004,9002,9001,50)');
  PERFORM pg_temp.expect_ok('transaction with asset + link type',
    'INSERT INTO transactions (id_clinic,id_category,id_method,id_registered_by,amount,id_asset,asset_link_type) VALUES (9001,9002,9001,9001,10,9001,''Maintenance'')');
  PERFORM pg_temp.expect_ok('allocation 60% of Ana to asset',
    'INSERT INTO operator_allocations (id_user,id_asset,allocation_percentage,assigned_at) VALUES (9001,9001,60,''2026-01-01'')');
  PERFORM pg_temp.expect_ok('allocation 40% of Ana to service line (total = 100)',
    'INSERT INTO operator_allocations (id_user,id_service_line,allocation_percentage,assigned_at) VALUES (9001,9001,40,''2026-01-01'')');
  PERFORM pg_temp.expect_ok('new invoice: header first, then 2 lines, checked at the end',
    'SET CONSTRAINTS invoice_total_on_invoice, invoice_total_on_lines DEFERRED;
     INSERT INTO invoices (id_invoice,id_clinic,id_counterparty,invoice_number,financial_type,total_amount,issue_date,due_date) VALUES (9005,9001,9002,''N-0003'',''Income'',70,''2026-03-01'',''2026-04-01'');
     INSERT INTO invoice_lines (id_invoice,line_number,description,id_category,quantity,unit_price,financial_type,line_total) VALUES (9005,1,''Consultation'',9001,1,40,''Income'',0);
     INSERT INTO invoice_lines (id_invoice,line_number,description,id_category,quantity,unit_price,financial_type,line_total) VALUES (9005,2,''Lab'',9003,1,30,''Income'',0);
     SET CONSTRAINTS invoice_total_on_invoice, invoice_total_on_lines IMMEDIATE');
  PERFORM pg_temp.expect_ok('same invoice number, different counterparty',
    'SET CONSTRAINTS invoice_total_on_invoice, invoice_total_on_lines DEFERRED;
     INSERT INTO invoices (id_invoice,id_clinic,id_counterparty,invoice_number,financial_type,total_amount,issue_date,due_date) VALUES (9006,9001,9002,''SUP-77'',''Expense'',5,''2026-01-01'',''2026-02-01'');
     INSERT INTO invoice_lines (id_invoice,line_number,description,id_category,quantity,unit_price,financial_type,line_total) VALUES (9006,1,''Tape'',9002,1,5,''Expense'',0);
     SET CONSTRAINTS invoice_total_on_invoice, invoice_total_on_lines IMMEDIATE');
  PERFORM pg_temp.expect_ok('Ana (has access.grant) gives Carl 1 day of access to South',
    'INSERT INTO user_clinic_access (id_access,id_user,id_clinic,id_granted_by,reason,expires_at) VALUES (9001,9003,9002,9001,''ticket #123'',now() + interval ''1 day'')');
  PERFORM pg_temp.expect_ok('v_user_clinics: Carl sees South through the grant',
    $q$DO $x$ BEGIN
         IF NOT EXISTS (SELECT 1 FROM v_user_clinics WHERE id_user = 9003 AND id_clinic = 9002 AND access_via = 'grant') THEN RAISE EXCEPTION 'grant not visible'; END IF;
         IF EXISTS (SELECT 1 FROM v_user_clinics WHERE id_user = 9003 AND id_clinic = 9001) THEN RAISE EXCEPTION 'Carl should not see North'; END IF;
       END $x$$q$);

  RAISE NOTICE '=== reconciliation rules (must be rejected) ===';
  PERFORM pg_temp.expect_fail('overpay invoice N-0001 (already 80 of 80)',
    'INSERT INTO reconciliation_history (id_invoice,id_transaction,id_user,applied_amount) VALUES (9001,9001,9001,1)');
  PERFORM pg_temp.expect_fail('over-apply trx 9001 (80 used, +30 > 100)',
    'INSERT INTO reconciliation_history (id_invoice,id_transaction,id_user,applied_amount) VALUES (9002,9001,9001,30)');
  PERFORM pg_temp.expect_fail('income invoice vs expense trx',
    'INSERT INTO reconciliation_history (id_invoice,id_transaction,id_user,applied_amount) VALUES (9002,9002,9001,1)');
  PERFORM pg_temp.expect_fail('cross-clinic reconciliation',
    'INSERT INTO reconciliation_history (id_invoice,id_transaction,id_user,applied_amount) VALUES (9003,9001,9001,5)');
  PERFORM pg_temp.expect_fail('reconcile a Pending transaction',
    'INSERT INTO reconciliation_history (id_invoice,id_transaction,id_user,applied_amount) VALUES (9002,9003,9001,5)');
  PERFORM pg_temp.expect_fail('Patient B payment on Patient A invoice',
    'INSERT INTO reconciliation_history (id_invoice,id_transaction,id_user,applied_amount) VALUES (9002,9004,9001,5)');
  PERFORM pg_temp.expect_fail('duplicate active pair (same invoice + trx twice)',
    'INSERT INTO reconciliation_history (id_invoice,id_transaction,id_user,applied_amount) VALUES (9002,9001,9001,10);
     INSERT INTO reconciliation_history (id_invoice,id_transaction,id_user,applied_amount) VALUES (9002,9001,9001,5)');
  PERFORM pg_temp.expect_fail('delete reconciliation row',
    'DELETE FROM reconciliation_history WHERE id_reconciliation = 9001');
  PERFORM pg_temp.expect_fail('edit applied_amount of reconciliation',
    'UPDATE reconciliation_history SET applied_amount = 70 WHERE id_reconciliation = 9001');

  RAISE NOTICE '=== guards on reconciled records (must be rejected) ===';
  PERFORM pg_temp.expect_fail('void a reconciled invoice',
    'UPDATE invoices SET is_void = true WHERE id_invoice = 9001');
  PERFORM pg_temp.expect_fail('shrink reconciled invoice below applied',
    'UPDATE invoices SET total_amount = 50 WHERE id_invoice = 9001');
  PERFORM pg_temp.expect_fail('change counterparty of reconciled invoice',
    'UPDATE invoices SET id_counterparty = 9002 WHERE id_invoice = 9001');
  PERFORM pg_temp.expect_fail('cancel a reconciled transaction',
    'UPDATE transactions SET transaction_status = ''Cancelled'' WHERE id_transaction = 9001');
  PERFORM pg_temp.expect_fail('shrink reconciled trx below applied',
    'UPDATE transactions SET amount = 60 WHERE id_transaction = 9001');
  PERFORM pg_temp.expect_fail('change category of reconciled trx',
    'UPDATE transactions SET id_category = 9003 WHERE id_transaction = 9001');
  PERFORM pg_temp.expect_fail('change counterparty of reconciled trx to Patient B',
    'UPDATE transactions SET id_counterparty = 9002 WHERE id_transaction = 9001');

  RAISE NOTICE '=== invoice lines (must be rejected) ===';
  PERFORM pg_temp.expect_fail('invoice total does not match its lines',
    'SET CONSTRAINTS invoice_total_on_invoice, invoice_total_on_lines DEFERRED;
     INSERT INTO invoices (id_invoice,id_clinic,id_counterparty,invoice_number,financial_type,total_amount,issue_date,due_date) VALUES (9010,9001,9001,''N-0010'',''Income'',100,''2026-03-01'',''2026-04-01'');
     INSERT INTO invoice_lines (id_invoice,line_number,description,id_category,quantity,unit_price,financial_type,line_total) VALUES (9010,1,''Consultation'',9001,1,90,''Income'',0);
     SET CONSTRAINTS invoice_total_on_invoice, invoice_total_on_lines IMMEDIATE');
  PERFORM pg_temp.expect_fail('invoice with no lines',
    'SET CONSTRAINTS invoice_total_on_invoice, invoice_total_on_lines DEFERRED;
     INSERT INTO invoices (id_invoice,id_clinic,id_counterparty,invoice_number,financial_type,total_amount,issue_date,due_date) VALUES (9011,9001,9001,''N-0011'',''Income'',10,''2026-03-01'',''2026-04-01'');
     SET CONSTRAINTS invoice_total_on_invoice, invoice_total_on_lines IMMEDIATE');
  PERFORM pg_temp.expect_fail('change a line price without fixing the invoice total',
    'UPDATE invoice_lines SET unit_price = 100 WHERE id_line = 9003');
  PERFORM pg_temp.expect_fail('Expense category on an Income invoice line',
    'UPDATE invoice_lines SET id_category = 9002 WHERE id_line = 9003');
  PERFORM pg_temp.expect_fail('line service line from another clinic',
    'UPDATE invoice_lines SET id_service_line = 9002 WHERE id_line = 9001');
  PERFORM pg_temp.expect_fail('duplicate line number on one invoice',
    'UPDATE invoice_lines SET line_number = 1 WHERE id_line = 9002');
  PERFORM pg_temp.expect_fail('duplicate invoice number, same clinic + counterparty',
    'SET CONSTRAINTS invoice_total_on_invoice, invoice_total_on_lines DEFERRED;
     INSERT INTO invoices (id_clinic,id_counterparty,invoice_number,financial_type,total_amount,issue_date,due_date) VALUES (9001,9001,''N-0001'',''Income'',10,''2026-03-01'',''2026-04-01'')');
  PERFORM pg_temp.expect_fail('negative quantity',
    'UPDATE invoice_lines SET quantity = -1 WHERE id_line = 9003');

  RAISE NOTICE '=== other data rules (must be rejected) ===';
  PERFORM pg_temp.expect_fail('asset from another clinic on a transaction',
    'INSERT INTO transactions (id_clinic,id_category,id_method,id_registered_by,amount,id_asset,asset_link_type) VALUES (9001,9002,9001,9001,10,9002,''Maintenance'')');
  PERFORM pg_temp.expect_fail('asset without link type',
    'INSERT INTO transactions (id_clinic,id_category,id_method,id_registered_by,amount,id_asset) VALUES (9001,9002,9001,9001,10,9001)');
  PERFORM pg_temp.expect_fail('negative amount',
    'INSERT INTO transactions (id_clinic,id_category,id_method,id_registered_by,amount) VALUES (9001,9002,9001,9001,-5)');
  PERFORM pg_temp.expect_fail('user allocation above 100% (100 + 10)',
    'INSERT INTO operator_allocations (id_user,id_service_line,allocation_percentage,assigned_at) VALUES (9001,9001,10,''2026-06-01'')');
  PERFORM pg_temp.expect_fail('overlapping allocation, same user + asset',
    'INSERT INTO operator_allocations (id_user,id_asset,allocation_percentage,assigned_at) VALUES (9002,9001,10,''2026-01-01'');
     INSERT INTO operator_allocations (id_user,id_asset,allocation_percentage,assigned_at) VALUES (9002,9001,10,''2026-03-01'')');
  PERFORM pg_temp.expect_fail('earlier allocation pushing a later date above 100%',
    'INSERT INTO operator_allocations (id_user,id_asset,allocation_percentage,assigned_at) VALUES (9001,9002,10,''2025-12-01'')');
  PERFORM pg_temp.expect_fail('allocation with both asset and service line',
    'INSERT INTO operator_allocations (id_user,id_asset,id_service_line) VALUES (9002,9001,9001)');
  PERFORM pg_temp.expect_fail('depreciable asset without category',
    'INSERT INTO clinic_assets (id_clinic,asset_name) VALUES (9001,''Chair'')');
  PERFORM pg_temp.expect_fail('Sold asset without disposal date',
    'INSERT INTO clinic_assets (id_clinic,asset_name,is_depreciable,asset_status) VALUES (9001,''Desk'',false,''Sold'')');
  PERFORM pg_temp.expect_fail('invoice due before issue',
    'INSERT INTO invoices (id_clinic,id_counterparty,invoice_number,financial_type,total_amount,issue_date,due_date) VALUES (9001,9001,''N-0099'',''Income'',10,''2026-02-01'',''2026-01-01'')');
  PERFORM pg_temp.expect_fail('delete clinic with history',
    'DELETE FROM clinics WHERE id_clinic = 9001');

  RAISE NOTICE '=== access grants (must be rejected) ===';
  PERFORM pg_temp.expect_fail('grant access to yourself',
    'INSERT INTO user_clinic_access (id_user,id_clinic,id_granted_by,reason,expires_at) VALUES (9001,9002,9001,''me'',now() + interval ''1 day'')');
  PERFORM pg_temp.expect_fail('Ben (no access.grant) grants access',
    'INSERT INTO user_clinic_access (id_user,id_clinic,id_granted_by,reason,expires_at) VALUES (9003,9002,9002,''x'',now() + interval ''1 day'')');
  PERFORM pg_temp.expect_fail('grant that expires before it starts',
    'INSERT INTO user_clinic_access (id_user,id_clinic,id_granted_by,reason,expires_at) VALUES (9003,9002,9001,''x'',now() - interval ''1 day'')');
  PERFORM pg_temp.expect_fail('delete a grant',
    'DELETE FROM user_clinic_access WHERE id_access = 9001');
  PERFORM pg_temp.expect_fail('extend a grant (edit expires_at)',
    'UPDATE user_clinic_access SET expires_at = now() + interval ''1 year'' WHERE id_access = 9001');

  RAISE NOTICE '=== audit log ===';
  PERFORM pg_temp.expect_ok('invoice insert was logged as Ana, clinic North, with IP',
    $q$DO $x$ BEGIN
         IF NOT EXISTS (SELECT 1 FROM audit_log WHERE table_name = 'invoices' AND record_id = 9001 AND action = 'db_insert'
                          AND id_user = 9001 AND id_clinic = 9001 AND ip_address = '10.0.0.5') THEN RAISE EXCEPTION 'missing'; END IF;
       END $x$$q$);
  PERFORM pg_temp.expect_ok('invoice line logged with the invoice''s clinic',
    $q$DO $x$ BEGIN
         IF NOT EXISTS (SELECT 1 FROM audit_log WHERE table_name = 'invoice_lines' AND record_id = 9004 AND id_clinic = 9002) THEN RAISE EXCEPTION 'missing'; END IF;
       END $x$$q$);
  PERFORM pg_temp.expect_ok('update logs only the changed column',
    $q$DO $x$ BEGIN
         UPDATE transactions SET description = 'fixed note' WHERE id_transaction = 9003;
         IF (SELECT details FROM audit_log WHERE table_name = 'transactions' AND record_id = 9003 AND action = 'db_update'
              ORDER BY id_audit DESC LIMIT 1)
            <> '{"changes": {"description": {"old": null, "new": "fixed note"}}}'::jsonb THEN RAISE EXCEPTION 'unexpected details'; END IF;
       END $x$$q$);
  PERFORM pg_temp.expect_ok('password change logged without the hash',
    $q$DO $x$ BEGIN
         UPDATE users SET password_hash = 'secret-new-hash' WHERE id_user = 9002;
         IF NOT EXISTS (SELECT 1 FROM audit_log WHERE table_name = 'users' AND record_id = 9002
                          AND details -> 'changes' ->> 'password_hash' = 'changed') THEN RAISE EXCEPTION 'not logged'; END IF;
         IF EXISTS (SELECT 1 FROM audit_log WHERE details::text LIKE '%hash-%' OR details::text LIKE '%secret-new-hash%') THEN RAISE EXCEPTION 'hash leaked into log'; END IF;
       END $x$$q$);
  PERFORM pg_temp.expect_fail('edit an audit_log row',
    'UPDATE audit_log SET action = ''x'' WHERE id_audit = (SELECT max(id_audit) FROM audit_log)');
  PERFORM pg_temp.expect_fail('delete an audit_log row',
    'DELETE FROM audit_log WHERE id_audit = (SELECT max(id_audit) FROM audit_log)');

  RAISE NOTICE '=== reversal, void, revoke ===';
  PERFORM pg_temp.expect_ok('reverse reconciliation 9001',
    'UPDATE reconciliation_history SET reversed_at = now() WHERE id_reconciliation = 9001');
  PERFORM pg_temp.expect_fail('re-activate a reversed reconciliation',
    'UPDATE reconciliation_history SET reversed_at = NULL WHERE id_reconciliation = 9001');
  PERFORM pg_temp.expect_ok('re-apply same pair after reversal (30)',
    'INSERT INTO reconciliation_history (id_invoice,id_transaction,id_user,applied_amount) VALUES (9001,9001,9001,30)');
  PERFORM pg_temp.expect_ok('void invoice N-0002 (no active reconciliations)',
    'UPDATE invoices SET is_void = true WHERE id_invoice = 9002');
  PERFORM pg_temp.expect_fail('change a line of a void invoice',
    'UPDATE invoice_lines SET description = ''x'' WHERE id_line = 9003');
  PERFORM pg_temp.expect_fail('un-void an invoice',
    'UPDATE invoices SET is_void = false WHERE id_invoice = 9002');
  PERFORM pg_temp.expect_ok('revoke Carl''s grant',
    'UPDATE user_clinic_access SET revoked_at = now() WHERE id_access = 9001');
  PERFORM pg_temp.expect_fail('revoke the same grant twice',
    'UPDATE user_clinic_access SET revoked_at = now() WHERE id_access = 9001');
  PERFORM pg_temp.expect_ok('Carl no longer sees South',
    $q$DO $x$ BEGIN
         IF EXISTS (SELECT 1 FROM v_user_clinics WHERE id_user = 9003) THEN RAISE EXCEPTION 'still visible'; END IF;
       END $x$$q$);

  RAISE NOTICE '=== views ===';
  PERFORM pg_temp.expect_ok('v_invoice_balances: void invoice shows Void and 0 outstanding',
    $q$DO $x$ BEGIN
         IF NOT EXISTS (SELECT 1 FROM v_invoice_balances WHERE id_invoice = 9002 AND reconciliation_status = 'Void' AND outstanding = 0) THEN RAISE EXCEPTION 'wrong'; END IF;
         IF NOT EXISTS (SELECT 1 FROM v_invoice_balances WHERE id_invoice = 9001 AND reconciliation_status = 'Partial' AND outstanding = 50) THEN RAISE EXCEPTION 'wrong partial'; END IF;
       END $x$$q$);
  PERFORM pg_temp.expect_ok('v_ledger: no Pending rows, expenses negative',
    $q$DO $x$ BEGIN
         IF EXISTS (SELECT 1 FROM v_ledger WHERE id_transaction = 9003) THEN RAISE EXCEPTION 'pending row in ledger'; END IF;
         IF (SELECT signed_amount FROM v_ledger WHERE id_transaction = 9002) <> -50 THEN RAISE EXCEPTION 'expense not negative'; END IF;
         IF (SELECT signed_amount FROM v_ledger WHERE id_transaction = 9001) <> 100 THEN RAISE EXCEPTION 'income not positive'; END IF;
       END $x$$q$);

  FOR r IN
    SELECT format('  %s  %s  %s  total=%s  paid=%s  outstanding=%s  %s',
                  invoice_number, invoice_type, financial_type, total_amount, amount_paid, outstanding, reconciliation_status)
      FROM v_invoice_balances WHERE id_invoice >= 9001 ORDER BY id_invoice
  LOOP RAISE NOTICE '%', r; END LOOP;

  RAISE NOTICE '=== updated_at trigger ===';
  PERFORM pg_temp.expect_ok('updated_at set automatically on update',
    $q$DO $x$ BEGIN
         UPDATE counterparties SET updated_at = '2000-01-01' WHERE id_counterparty = 9001;
         IF (SELECT updated_at FROM counterparties WHERE id_counterparty = 9001) <> now() THEN RAISE EXCEPTION 'not touched'; END IF;
       END $x$$q$);

  SELECT format('=== SUMMARY: %s PASS, %s FAIL ===',
                count(*) FILTER (WHERE line LIKE 'PASS%'), count(*) FILTER (WHERE line LIKE 'FAIL%'))
    INTO r FROM test_results;
  RAISE NOTICE '%', r;
END
$test$;

-- undo everything: the database is left exactly as it was
ROLLBACK;
