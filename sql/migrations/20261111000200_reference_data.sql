-- migrate:up
-- Starter roles, permissions and lookup lists (from sql/Versions/v3/seed_v3.sql).
-- =====================================================================
-- Starter data for Clinic Finance DB v3.
-- Run after Clinic_export_v3_Postgresql.sql and clinic_finance_v3_constraints.sql.
--
-- Everything here is a STARTING POINT: rename, add or remove freely.
-- Clinics and users are NOT created here; the app's setup screen
-- creates the first admin (password hashing belongs in the app).
-- =====================================================================


-- ---------------------------------------------------------------------
-- Permissions
-- ---------------------------------------------------------------------
INSERT INTO permissions (permission_code, description) VALUES
  -- system administration (no access to financial or patient data)
  ('users.manage',            'Create, edit and deactivate users'),
  ('roles.manage',            'Edit roles and what each role can do'),
  ('clinics.manage',          'Create and edit clinics'),
  ('settings.manage',         'Edit categories, payment methods, depreciation categories'),
  ('access.grant',            'Grant/revoke temporary access to a clinic (user_clinic_access)'),
  ('audit.view',              'Read the audit log'),
  -- scope
  ('clinics.view_all',        'See data of every clinic, not only the home clinic'),
  -- counterparties (patients, suppliers, insurers)
  ('counterparties.view',     'See counterparties'),
  ('counterparties.manage',   'Create and edit counterparties'),
  -- money
  ('transactions.view',       'See transactions'),
  ('transactions.create',     'Record transactions'),
  ('transactions.edit',       'Edit transactions'),
  ('transactions.cancel',     'Cancel transactions'),
  ('invoices.view',           'See invoices'),
  ('invoices.create',         'Create invoices'),
  ('invoices.edit',           'Edit invoices and their lines'),
  ('invoices.void',           'Void invoices'),
  ('reconciliation.view',     'See payment/invoice matches'),
  ('reconciliation.create',   'Match payments to invoices'),
  ('reconciliation.reverse',  'Undo a match'),
  -- assets, service lines, staff allocation
  ('assets.view',             'See assets'),
  ('assets.manage',           'Create and edit assets'),
  ('service_lines.manage',    'Create and edit service lines'),
  ('allocations.manage',      'Assign staff to assets / service lines'),
  -- reports
  ('reports.view',            'See financial reports');

-- ---------------------------------------------------------------------
-- Roles
-- ---------------------------------------------------------------------
INSERT INTO roles (role_name, description) VALUES
  ('System Admin',   'Runs the system: users, roles, clinics, settings, access grants, audit. No financial or patient data by default.'),
  ('HQ Finance',     'Finance team across all clinics.'),
  ('Clinic Manager', 'Full financial control of their own clinic.'),
  ('Clinic Staff',   'Day-to-day entry in their own clinic: patients, payments, invoices.'),
  ('IT Maintenance', 'Read-only support role. Has no home clinic: sees data only through a temporary access grant.');

-- ---------------------------------------------------------------------
-- What each role can do
-- ---------------------------------------------------------------------
INSERT INTO role_permissions (id_role, id_permission)
SELECT r.id_role, p.id_permission
  FROM (VALUES
    ('System Admin',   ARRAY['users.manage','roles.manage','clinics.manage','settings.manage','access.grant','audit.view']),

    ('HQ Finance',     ARRAY['clinics.view_all',
                             'counterparties.view','counterparties.manage',
                             'transactions.view','transactions.create','transactions.edit','transactions.cancel',
                             'invoices.view','invoices.create','invoices.edit','invoices.void',
                             'reconciliation.view','reconciliation.create','reconciliation.reverse',
                             'assets.view','reports.view']),

    ('Clinic Manager', ARRAY['counterparties.view','counterparties.manage',
                             'transactions.view','transactions.create','transactions.edit','transactions.cancel',
                             'invoices.view','invoices.create','invoices.edit','invoices.void',
                             'reconciliation.view','reconciliation.create','reconciliation.reverse',
                             'assets.view','assets.manage','service_lines.manage','allocations.manage',
                             'reports.view']),

    ('Clinic Staff',   ARRAY['counterparties.view','counterparties.manage',
                             'transactions.view','transactions.create',
                             'invoices.view','invoices.create',
                             'reconciliation.view']),

    ('IT Maintenance', ARRAY['counterparties.view','transactions.view','invoices.view',
                             'reconciliation.view','assets.view'])
  ) AS m(role_name, codes)
  JOIN roles r       ON r.role_name = m.role_name
  JOIN permissions p ON p.permission_code = ANY (m.codes);

-- ---------------------------------------------------------------------
-- Payment methods
-- ---------------------------------------------------------------------
INSERT INTO payment_methods (method_name) VALUES
  ('Cash'), ('Bank Transfer'), ('Credit Card'), ('Debit Card'), ('Check'), ('Insurance');

-- ---------------------------------------------------------------------
-- Financial categories (examples)
-- ---------------------------------------------------------------------
INSERT INTO financial_categories (financial_type, category_name, suggested_periodicity) VALUES
  ('Income',  'Consultations',            'Variable'),
  ('Income',  'Procedures',               'Variable'),
  ('Income',  'Lab Tests',                'Variable'),
  ('Income',  'Insurance Reimbursements', 'Variable'),
  ('Income',  'Other Income',             'Variable'),
  ('Expense', 'Salaries',                 'Monthly'),
  ('Expense', 'Rent',                     'Monthly'),
  ('Expense', 'Utilities',                'Monthly'),
  ('Expense', 'Medical Supplies',         'Variable'),
  ('Expense', 'Equipment Purchase',       'Variable'),
  ('Expense', 'Equipment Maintenance',    'Variable'),
  ('Expense', 'Insurance',                'Annual'),
  ('Expense', 'Taxes',                    'Quarterly'),
  ('Expense', 'Other Expense',            'Variable');

-- ---------------------------------------------------------------------
-- Depreciation categories (examples, straight-line)
-- ---------------------------------------------------------------------
INSERT INTO depreciation_categories (category_name, useful_life_months) VALUES
  ('Medical Equipment', 60),
  ('Computers',         36),
  ('Furniture',        120),
  ('Vehicles',          60);


-- migrate:down
DO $$ BEGIN RAISE EXCEPTION 'Reference data cannot be rolled back automatically.'; END $$;
