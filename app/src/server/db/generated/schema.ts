import { pgTable, unique, serial, varchar, text, index, foreignKey, check, integer, timestamp, bigserial, bigint, jsonb, uniqueIndex, boolean, numeric, date, smallint, primaryKey, pgView, pgEnum } from "drizzle-orm/pg-core"
import { sql } from "drizzle-orm"

export const enumAssetLinkType = pgEnum("enum_asset_link_type", ['Purchase', 'Maintenance', 'Revenue', 'Other'])
export const enumAssetStatus = pgEnum("enum_asset_status", ['Active', 'Sold', 'Damaged Write-Off'])
export const enumCounterpartyType = pgEnum("enum_counterparty_type", ['Patient', 'Supplier', 'Insurer', 'Other'])
export const enumFinancialType = pgEnum("enum_financial_type", ['Income', 'Expense'])
export const enumPeriodicity = pgEnum("enum_periodicity", ['Daily', 'Weekly', 'Biweekly', 'Monthly', 'Quarterly', 'Annual', 'Variable'])
export const enumTransactionStatus = pgEnum("enum_transaction_status", ['Completed', 'Pending', 'Cancelled'])


export const roles = pgTable("roles", {
	idRole: serial("id_role").primaryKey().notNull(),
	roleName: varchar("role_name", { length: 50 }).notNull(),
	description: text(),
}, (table) => [
	unique("roles_role_name_key").on(table.roleName),
]);

export const permissions = pgTable("permissions", {
	idPermission: serial("id_permission").primaryKey().notNull(),
	permissionCode: varchar("permission_code", { length: 100 }).notNull(),
	description: text(),
}, (table) => [
	unique("permissions_permission_code_key").on(table.permissionCode),
]);

export const userClinicAccess = pgTable("user_clinic_access", {
	idAccess: serial("id_access").primaryKey().notNull(),
	idUser: integer("id_user").notNull(),
	idClinic: integer("id_clinic").notNull(),
	idGrantedBy: integer("id_granted_by").notNull(),
	reason: text().notNull(),
	grantedAt: timestamp("granted_at", { withTimezone: true, mode: 'string' }).defaultNow().notNull(),
	expiresAt: timestamp("expires_at", { withTimezone: true, mode: 'string' }).notNull(),
	revokedAt: timestamp("revoked_at", { withTimezone: true, mode: 'string' }),
}, (table) => [
	index("user_clinic_access_id_clinic_idx").using("btree", table.idClinic.asc().nullsLast().op("int4_ops")),
	index("user_clinic_access_id_user_id_clinic_idx").using("btree", table.idUser.asc().nullsLast().op("int4_ops"), table.idClinic.asc().nullsLast().op("int4_ops")),
	foreignKey({
			columns: [table.idUser],
			foreignColumns: [users.idUser],
			name: "user_clinic_access_id_user_fkey"
		}).onDelete("restrict"),
	foreignKey({
			columns: [table.idGrantedBy],
			foreignColumns: [users.idUser],
			name: "user_clinic_access_id_granted_by_fkey"
		}).onDelete("restrict"),
	foreignKey({
			columns: [table.idClinic],
			foreignColumns: [clinics.idClinic],
			name: "user_clinic_access_id_clinic_fkey"
		}).onDelete("restrict"),
	check("chk_access_expiry", sql`expires_at > granted_at`),
	check("chk_access_revoked", sql`(revoked_at IS NULL) OR (revoked_at >= granted_at)`),
	check("chk_access_not_self_granted", sql`id_user <> id_granted_by`),
]);

export const auditLog = pgTable("audit_log", {
	idAudit: bigserial("id_audit", { mode: "bigint" }).primaryKey().notNull(),
	idUser: integer("id_user"),
	idClinic: integer("id_clinic"),
	action: varchar({ length: 50 }).notNull(),
	tableName: varchar("table_name", { length: 100 }),
	// You can use { mode: "bigint" } if numbers are exceeding js number limitations
	recordId: bigint("record_id", { mode: "number" }),
	details: jsonb(),
	ipAddress: varchar("ip_address", { length: 45 }),
	createdAt: timestamp("created_at", { withTimezone: true, mode: 'string' }).defaultNow().notNull(),
}, (table) => [
	index("audit_log_id_clinic_created_at_idx").using("btree", table.idClinic.asc().nullsLast().op("int4_ops"), table.createdAt.asc().nullsLast().op("int4_ops")),
	index("audit_log_id_user_created_at_idx").using("btree", table.idUser.asc().nullsLast().op("timestamptz_ops"), table.createdAt.asc().nullsLast().op("int4_ops")),
	index("audit_log_table_name_record_id_idx").using("btree", table.tableName.asc().nullsLast().op("int8_ops"), table.recordId.asc().nullsLast().op("int8_ops")),
	foreignKey({
			columns: [table.idUser],
			foreignColumns: [users.idUser],
			name: "audit_log_id_user_fkey"
		}).onDelete("restrict"),
	foreignKey({
			columns: [table.idClinic],
			foreignColumns: [clinics.idClinic],
			name: "audit_log_id_clinic_fkey"
		}).onDelete("restrict"),
]);

export const serviceLines = pgTable("service_lines", {
	idServiceLine: serial("id_service_line").primaryKey().notNull(),
	idClinic: integer("id_clinic").notNull(),
	serviceName: varchar("service_name", { length: 150 }).notNull(),
	active: boolean().default(true).notNull(),
	createdAt: timestamp("created_at", { withTimezone: true, mode: 'string' }).defaultNow().notNull(),
	updatedAt: timestamp("updated_at", { withTimezone: true, mode: 'string' }).defaultNow().notNull(),
}, (table) => [
	uniqueIndex("service_lines_id_clinic_service_name_idx").using("btree", table.idClinic.asc().nullsLast().op("text_ops"), table.serviceName.asc().nullsLast().op("int4_ops")),
	foreignKey({
			columns: [table.idClinic],
			foreignColumns: [clinics.idClinic],
			name: "service_lines_id_clinic_fkey"
		}).onDelete("restrict"),
]);

export const clinicAssets = pgTable("clinic_assets", {
	idAsset: serial("id_asset").primaryKey().notNull(),
	idClinic: integer("id_clinic").notNull(),
	assetName: varchar("asset_name", { length: 150 }).notNull(),
	serialNumber: varchar("serial_number", { length: 100 }),
	isDepreciable: boolean("is_depreciable").default(true).notNull(),
	idDepCategory: integer("id_dep_category"),
	acquisitionCost: numeric("acquisition_cost", { precision: 12, scale:  2 }).default('0').notNull(),
	purchaseDate: date("purchase_date").default(sql`CURRENT_DATE`).notNull(),
	depreciationStartDate: date("depreciation_start_date"),
	assetStatus: enumAssetStatus("asset_status").default('Active').notNull(),
	disposalDate: date("disposal_date"),
	disposalAmount: numeric("disposal_amount", { precision: 12, scale:  2 }),
	createdAt: timestamp("created_at", { withTimezone: true, mode: 'string' }).defaultNow().notNull(),
	updatedAt: timestamp("updated_at", { withTimezone: true, mode: 'string' }).defaultNow().notNull(),
}, (table) => [
	index("clinic_assets_id_clinic_idx").using("btree", table.idClinic.asc().nullsLast().op("int4_ops")),
	foreignKey({
			columns: [table.idClinic],
			foreignColumns: [clinics.idClinic],
			name: "clinic_assets_id_clinic_fkey"
		}).onDelete("restrict"),
	foreignKey({
			columns: [table.idDepCategory],
			foreignColumns: [depreciationCategories.idDepCategory],
			name: "clinic_assets_id_dep_category_fkey"
		}).onDelete("restrict"),
	unique("clinic_assets_serial_number_key").on(table.serialNumber),
	check("chk_depreciation_conditional", sql`(is_depreciable AND (id_dep_category IS NOT NULL) AND (depreciation_start_date IS NOT NULL)) OR ((NOT is_depreciable) AND (id_dep_category IS NULL) AND (depreciation_start_date IS NULL))`),
	check("chk_asset_cost_nonneg", sql`acquisition_cost >= (0)::numeric`),
	check("chk_dep_start_after_purchase", sql`(depreciation_start_date IS NULL) OR (depreciation_start_date >= purchase_date)`),
	check("chk_asset_disposal", sql`((asset_status = 'Active'::enum_asset_status) AND (disposal_date IS NULL) AND (disposal_amount IS NULL)) OR ((asset_status = 'Sold'::enum_asset_status) AND (disposal_date IS NOT NULL) AND (disposal_date >= purchase_date)) OR ((asset_status = 'Damaged Write-Off'::enum_asset_status) AND (disposal_date IS NOT NULL) AND (disposal_date >= purchase_date) AND (disposal_amount IS NULL))`),
]);

export const depreciationCategories = pgTable("depreciation_categories", {
	idDepCategory: serial("id_dep_category").primaryKey().notNull(),
	categoryName: varchar("category_name", { length: 100 }).notNull(),
	usefulLifeMonths: integer("useful_life_months").notNull(),
}, (table) => [
	unique("depreciation_categories_category_name_key").on(table.categoryName),
	check("chk_dep_life_positive", sql`useful_life_months > 0`),
]);

export const operatorAllocations = pgTable("operator_allocations", {
	idAllocation: serial("id_allocation").primaryKey().notNull(),
	idUser: integer("id_user").notNull(),
	idAsset: integer("id_asset"),
	idServiceLine: integer("id_service_line"),
	allocationPercentage: numeric("allocation_percentage", { precision: 5, scale:  2 }).default('100').notNull(),
	assignedAt: date("assigned_at").default(sql`CURRENT_DATE`).notNull(),
	retractedAt: date("retracted_at"),
	createdAt: timestamp("created_at", { withTimezone: true, mode: 'string' }).defaultNow().notNull(),
	updatedAt: timestamp("updated_at", { withTimezone: true, mode: 'string' }).defaultNow().notNull(),
}, (table) => [
	index("operator_allocations_id_asset_idx").using("btree", table.idAsset.asc().nullsLast().op("int4_ops")),
	index("operator_allocations_id_service_line_idx").using("btree", table.idServiceLine.asc().nullsLast().op("int4_ops")),
	index("operator_allocations_id_user_idx").using("btree", table.idUser.asc().nullsLast().op("int4_ops")),
	foreignKey({
			columns: [table.idUser],
			foreignColumns: [users.idUser],
			name: "operator_allocations_id_user_fkey"
		}).onDelete("restrict"),
	foreignKey({
			columns: [table.idAsset],
			foreignColumns: [clinicAssets.idAsset],
			name: "operator_allocations_id_asset_fkey"
		}).onDelete("restrict"),
	foreignKey({
			columns: [table.idServiceLine],
			foreignColumns: [serviceLines.idServiceLine],
			name: "operator_allocations_id_service_line_fkey"
		}).onDelete("restrict"),
	check("chk_alloc_exactly_one_target", sql`((id_asset IS NOT NULL) AND (id_service_line IS NULL)) OR ((id_asset IS NULL) AND (id_service_line IS NOT NULL))`),
	check("chk_alloc_pct_range", sql`(allocation_percentage > (0)::numeric) AND (allocation_percentage <= (100)::numeric)`),
	check("chk_alloc_dates", sql`(retracted_at IS NULL) OR (retracted_at >= assigned_at)`),
]);

export const transactions = pgTable("transactions", {
	idTransaction: bigserial("id_transaction", { mode: "bigint" }).primaryKey().notNull(),
	idClinic: integer("id_clinic").notNull(),
	idCategory: integer("id_category").notNull(),
	idMethod: integer("id_method").notNull(),
	idRegisteredBy: integer("id_registered_by").notNull(),
	idPayeeUser: integer("id_payee_user"),
	idCounterparty: integer("id_counterparty"),
	idAsset: integer("id_asset"),
	assetLinkType: enumAssetLinkType("asset_link_type"),
	idServiceLine: integer("id_service_line"),
	amount: numeric({ precision: 12, scale:  2 }).notNull(),
	transactionDate: date("transaction_date").default(sql`CURRENT_DATE`).notNull(),
	description: text(),
	transactionStatus: enumTransactionStatus("transaction_status").default('Completed').notNull(),
	createdAt: timestamp("created_at", { withTimezone: true, mode: 'string' }).defaultNow().notNull(),
	updatedAt: timestamp("updated_at", { withTimezone: true, mode: 'string' }).defaultNow().notNull(),
}, (table) => [
	index("transactions_id_asset_idx").using("btree", table.idAsset.asc().nullsLast().op("int4_ops")),
	index("transactions_id_category_idx").using("btree", table.idCategory.asc().nullsLast().op("int4_ops")),
	index("transactions_id_clinic_transaction_date_idx").using("btree", table.idClinic.asc().nullsLast().op("int4_ops"), table.transactionDate.asc().nullsLast().op("int4_ops")),
	index("transactions_id_counterparty_idx").using("btree", table.idCounterparty.asc().nullsLast().op("int4_ops")),
	index("transactions_id_payee_user_idx").using("btree", table.idPayeeUser.asc().nullsLast().op("int4_ops")),
	index("transactions_id_service_line_idx").using("btree", table.idServiceLine.asc().nullsLast().op("int4_ops")),
	foreignKey({
			columns: [table.idClinic],
			foreignColumns: [clinics.idClinic],
			name: "transactions_id_clinic_fkey"
		}).onDelete("restrict"),
	foreignKey({
			columns: [table.idCategory],
			foreignColumns: [financialCategories.idCategory],
			name: "transactions_id_category_fkey"
		}).onDelete("restrict"),
	foreignKey({
			columns: [table.idMethod],
			foreignColumns: [paymentMethods.idMethod],
			name: "transactions_id_method_fkey"
		}).onDelete("restrict"),
	foreignKey({
			columns: [table.idRegisteredBy],
			foreignColumns: [users.idUser],
			name: "transactions_id_registered_by_fkey"
		}).onDelete("restrict"),
	foreignKey({
			columns: [table.idPayeeUser],
			foreignColumns: [users.idUser],
			name: "transactions_id_payee_user_fkey"
		}).onDelete("restrict"),
	foreignKey({
			columns: [table.idCounterparty],
			foreignColumns: [counterparties.idCounterparty],
			name: "transactions_id_counterparty_fkey"
		}).onDelete("restrict"),
	foreignKey({
			columns: [table.idClinic, table.idAsset],
			foreignColumns: [clinicAssets.idAsset, clinicAssets.idClinic],
			name: "transactions_id_asset_id_clinic_fkey"
		}).onDelete("restrict"),
	foreignKey({
			columns: [table.idClinic, table.idServiceLine],
			foreignColumns: [serviceLines.idServiceLine, serviceLines.idClinic],
			name: "transactions_id_service_line_id_clinic_fkey"
		}).onDelete("restrict"),
	check("chk_trx_amount_positive", sql`amount > (0)::numeric`),
	check("chk_trx_asset_link", sql`(id_asset IS NULL) = (asset_link_type IS NULL)`),
]);

export const financialCategories = pgTable("financial_categories", {
	idCategory: serial("id_category").primaryKey().notNull(),
	financialType: enumFinancialType("financial_type").notNull(),
	categoryName: varchar("category_name", { length: 100 }).notNull(),
	suggestedPeriodicity: enumPeriodicity("suggested_periodicity").default('Variable').notNull(),
}, (table) => [
	uniqueIndex("financial_categories_financial_type_category_name_idx").using("btree", table.financialType.asc().nullsLast().op("text_ops"), table.categoryName.asc().nullsLast().op("text_ops")),
]);

export const paymentMethods = pgTable("payment_methods", {
	idMethod: serial("id_method").primaryKey().notNull(),
	methodName: varchar("method_name", { length: 50 }).notNull(),
}, (table) => [
	unique("payment_methods_method_name_key").on(table.methodName),
]);

export const invoices = pgTable("invoices", {
	idInvoice: serial("id_invoice").primaryKey().notNull(),
	idClinic: integer("id_clinic").notNull(),
	idCounterparty: integer("id_counterparty").notNull(),
	invoiceNumber: varchar("invoice_number", { length: 50 }).notNull(),
	financialType: enumFinancialType("financial_type").notNull(),
	totalAmount: numeric("total_amount", { precision: 12, scale:  2 }).notNull(),
	issueDate: date("issue_date").notNull(),
	dueDate: date("due_date").notNull(),
	isVoid: boolean("is_void").default(false).notNull(),
	createdAt: timestamp("created_at", { withTimezone: true, mode: 'string' }).defaultNow().notNull(),
	updatedAt: timestamp("updated_at", { withTimezone: true, mode: 'string' }).defaultNow().notNull(),
}, (table) => [
	index("invoices_id_clinic_due_date_idx").using("btree", table.idClinic.asc().nullsLast().op("int4_ops"), table.dueDate.asc().nullsLast().op("int4_ops")),
	uniqueIndex("invoices_id_clinic_id_counterparty_invoice_number_idx").using("btree", table.idClinic.asc().nullsLast().op("int4_ops"), table.idCounterparty.asc().nullsLast().op("text_ops"), table.invoiceNumber.asc().nullsLast().op("text_ops")),
	index("invoices_id_counterparty_idx").using("btree", table.idCounterparty.asc().nullsLast().op("int4_ops")),
	foreignKey({
			columns: [table.idClinic],
			foreignColumns: [clinics.idClinic],
			name: "invoices_id_clinic_fkey"
		}).onDelete("restrict"),
	foreignKey({
			columns: [table.idCounterparty],
			foreignColumns: [counterparties.idCounterparty],
			name: "invoices_id_counterparty_fkey"
		}).onDelete("restrict"),
	check("chk_invoice_total_positive", sql`total_amount > (0)::numeric`),
	check("chk_invoice_dates", sql`due_date >= issue_date`),
]);

export const invoiceLines = pgTable("invoice_lines", {
	idLine: serial("id_line").primaryKey().notNull(),
	idInvoice: integer("id_invoice").notNull(),
	lineNumber: smallint("line_number").notNull(),
	description: varchar({ length: 255 }).notNull(),
	financialType: enumFinancialType("financial_type").notNull(),
	idCategory: integer("id_category").notNull(),
	idServiceLine: integer("id_service_line"),
	quantity: numeric({ precision: 10, scale:  2 }).default('1').notNull(),
	unitPrice: numeric("unit_price", { precision: 12, scale:  2 }).notNull(),
	lineTotal: numeric("line_total", { precision: 12, scale:  2 }).notNull(),
	createdAt: timestamp("created_at", { withTimezone: true, mode: 'string' }).defaultNow().notNull(),
	updatedAt: timestamp("updated_at", { withTimezone: true, mode: 'string' }).defaultNow().notNull(),
}, (table) => [
	index("invoice_lines_id_category_idx").using("btree", table.idCategory.asc().nullsLast().op("int4_ops")),
	uniqueIndex("invoice_lines_id_invoice_line_number_idx").using("btree", table.idInvoice.asc().nullsLast().op("int4_ops"), table.lineNumber.asc().nullsLast().op("int4_ops")),
	index("invoice_lines_id_service_line_idx").using("btree", table.idServiceLine.asc().nullsLast().op("int4_ops")),
	foreignKey({
			columns: [table.idInvoice, table.financialType],
			foreignColumns: [invoices.idInvoice, invoices.financialType],
			name: "invoice_lines_id_invoice_financial_type_fkey"
		}).onDelete("restrict"),
	foreignKey({
			columns: [table.financialType, table.idCategory],
			foreignColumns: [financialCategories.idCategory, financialCategories.financialType],
			name: "invoice_lines_id_category_financial_type_fkey"
		}).onDelete("restrict"),
	foreignKey({
			columns: [table.idServiceLine],
			foreignColumns: [serviceLines.idServiceLine],
			name: "invoice_lines_id_service_line_fkey"
		}).onDelete("restrict"),
	check("chk_line_qty_positive", sql`quantity > (0)::numeric`),
	check("chk_line_price_nonneg", sql`unit_price >= (0)::numeric`),
	check("chk_line_total", sql`line_total = round((quantity * unit_price), 2)`),
]);

export const reconciliationHistory = pgTable("reconciliation_history", {
	idReconciliation: serial("id_reconciliation").primaryKey().notNull(),
	idInvoice: integer("id_invoice").notNull(),
	// You can use { mode: "bigint" } if numbers are exceeding js number limitations
	idTransaction: bigint("id_transaction", { mode: "number" }).notNull(),
	idUser: integer("id_user").notNull(),
	appliedAmount: numeric("applied_amount", { precision: 12, scale:  2 }).notNull(),
	reconciliationDate: timestamp("reconciliation_date", { withTimezone: true, mode: 'string' }).defaultNow().notNull(),
	reversedAt: timestamp("reversed_at", { withTimezone: true, mode: 'string' }),
}, (table) => [
	index("reconciliation_history_id_invoice_idx").using("btree", table.idInvoice.asc().nullsLast().op("int4_ops")),
	index("reconciliation_history_id_transaction_idx").using("btree", table.idTransaction.asc().nullsLast().op("int8_ops")),
	uniqueIndex("uq_reconciliation_active_pair").using("btree", table.idInvoice.asc().nullsLast().op("int4_ops"), table.idTransaction.asc().nullsLast().op("int4_ops")).where(sql`(reversed_at IS NULL)`),
	foreignKey({
			columns: [table.idInvoice],
			foreignColumns: [invoices.idInvoice],
			name: "reconciliation_history_id_invoice_fkey"
		}).onDelete("restrict"),
	foreignKey({
			columns: [table.idTransaction],
			foreignColumns: [transactions.idTransaction],
			name: "reconciliation_history_id_transaction_fkey"
		}).onDelete("restrict"),
	foreignKey({
			columns: [table.idUser],
			foreignColumns: [users.idUser],
			name: "reconciliation_history_id_user_fkey"
		}).onDelete("restrict"),
	check("chk_recon_amount_positive", sql`applied_amount > (0)::numeric`),
]);

export const clinics = pgTable("clinics", {
	idClinic: serial("id_clinic").primaryKey().notNull(),
	clinicName: varchar("clinic_name", { length: 150 }).notNull(),
	address: text(),
	active: boolean().default(true).notNull(),
	createdAt: timestamp("created_at", { withTimezone: true, mode: 'string' }).defaultNow().notNull(),
	updatedAt: timestamp("updated_at", { withTimezone: true, mode: 'string' }).defaultNow().notNull(),
	clinicCode: varchar("clinic_code", { length: 10 }).notNull(),
}, (table) => [
	unique("uq_clinic_code").on(table.clinicCode),
	check("chk_clinic_code", sql`(clinic_code)::text ~ '^[A-Z0-9]{2,10}$'::text`),
]);

export const users = pgTable("users", {
	idUser: serial("id_user").primaryKey().notNull(),
	firstName: varchar("first_name", { length: 100 }).notNull(),
	lastName: varchar("last_name", { length: 100 }).notNull(),
	email: varchar({ length: 150 }).notNull(),
	phone: varchar({ length: 20 }),
	idClinic: integer("id_clinic"),
	idRole: integer("id_role").notNull(),
	passwordHash: varchar("password_hash", { length: 255 }).notNull(),
	active: boolean().default(true).notNull(),
	createdAt: timestamp("created_at", { withTimezone: true, mode: 'string' }).defaultNow().notNull(),
	updatedAt: timestamp("updated_at", { withTimezone: true, mode: 'string' }).defaultNow().notNull(),
	preferredLanguage: varchar("preferred_language", { length: 2 }).default('es').notNull(),
	totpSecret: text("totp_secret"),
	totpEnabled: boolean("totp_enabled").default(false).notNull(),
	failedLoginCount: integer("failed_login_count").default(0).notNull(),
	lockedUntil: timestamp("locked_until", { withTimezone: true, mode: 'string' }),
	lastLoginAt: timestamp("last_login_at", { withTimezone: true, mode: 'string' }),
	mustChangePassword: boolean("must_change_password").default(true).notNull(),
}, (table) => [
	foreignKey({
			columns: [table.idClinic],
			foreignColumns: [clinics.idClinic],
			name: "users_id_clinic_fkey"
		}).onDelete("restrict"),
	foreignKey({
			columns: [table.idRole],
			foreignColumns: [roles.idRole],
			name: "users_id_role_fkey"
		}).onDelete("restrict"),
	unique("users_email_key").on(table.email),
	check("chk_user_language", sql`(preferred_language)::text = ANY ((ARRAY['es'::character varying, 'en'::character varying])::text[])`),
	check("chk_user_failed_logins", sql`failed_login_count >= 0`),
	check("chk_user_totp", sql`(NOT totp_enabled) OR (totp_secret IS NOT NULL)`),
]);

export const counterparties = pgTable("counterparties", {
	idCounterparty: serial("id_counterparty").primaryKey().notNull(),
	counterpartyName: varchar("counterparty_name", { length: 150 }).notNull(),
	taxId: varchar("tax_id", { length: 50 }),
	active: boolean().default(true).notNull(),
	createdAt: timestamp("created_at", { withTimezone: true, mode: 'string' }).defaultNow().notNull(),
	updatedAt: timestamp("updated_at", { withTimezone: true, mode: 'string' }).defaultNow().notNull(),
	counterpartyType: enumCounterpartyType("counterparty_type").default('Patient').notNull(),
	idClinic: integer("id_clinic"),
}, (table) => [
	index("idx_counterparties_clinic").using("btree", table.idClinic.asc().nullsLast().op("int4_ops")),
	foreignKey({
			columns: [table.idClinic],
			foreignColumns: [clinics.idClinic],
			name: "counterparties_id_clinic_fkey"
		}).onDelete("restrict"),
	unique("counterparties_tax_id_key").on(table.taxId),
]);

export const rolePermissions = pgTable("role_permissions", {
	idRole: integer("id_role").notNull(),
	idPermission: integer("id_permission").notNull(),
}, (table) => [
	foreignKey({
			columns: [table.idRole],
			foreignColumns: [roles.idRole],
			name: "role_permissions_id_role_fkey"
		}).onDelete("restrict"),
	foreignKey({
			columns: [table.idPermission],
			foreignColumns: [permissions.idPermission],
			name: "role_permissions_id_permission_fkey"
		}).onDelete("restrict"),
	primaryKey({ columns: [table.idRole, table.idPermission], name: "role_permissions_pkey"}),
]);

export const invoiceNumberSequences = pgTable("invoice_number_sequences", {
	idClinic: integer("id_clinic").notNull(),
	year: integer().notNull(),
	lastNumber: integer("last_number").default(0).notNull(),
}, (table) => [
	foreignKey({
			columns: [table.idClinic],
			foreignColumns: [clinics.idClinic],
			name: "invoice_number_sequences_id_clinic_fkey"
		}).onDelete("restrict"),
	primaryKey({ columns: [table.year, table.idClinic], name: "invoice_number_sequences_pkey"}),
	check("chk_invseq_nonneg", sql`last_number >= 0`),
]);
export const vInvoiceBalances = pgView("v_invoice_balances", {	idInvoice: integer("id_invoice"),
	idClinic: integer("id_clinic"),
	idCounterparty: integer("id_counterparty"),
	invoiceNumber: varchar("invoice_number", { length: 50 }),
	financialType: enumFinancialType("financial_type"),
	invoiceType: text("invoice_type"),
	isVoid: boolean("is_void"),
	totalAmount: numeric("total_amount", { precision: 12, scale:  2 }),
	amountPaid: numeric("amount_paid"),
	outstanding: numeric(),
	reconciliationStatus: text("reconciliation_status"),
	issueDate: date("issue_date"),
	dueDate: date("due_date"),
}).as(sql`WITH paid AS ( SELECT reconciliation_history.id_invoice, sum(reconciliation_history.applied_amount) AS amount_paid FROM reconciliation_history WHERE reconciliation_history.reversed_at IS NULL GROUP BY reconciliation_history.id_invoice ) SELECT i.id_invoice, i.id_clinic, i.id_counterparty, i.invoice_number, i.financial_type, CASE i.financial_type WHEN 'Income'::enum_financial_type THEN 'Accounts Receivable'::text ELSE 'Accounts Payable'::text END AS invoice_type, i.is_void, i.total_amount, COALESCE(p.amount_paid, 0::numeric) AS amount_paid, CASE WHEN i.is_void THEN 0::numeric ELSE i.total_amount - COALESCE(p.amount_paid, 0::numeric) END AS outstanding, CASE WHEN i.is_void THEN 'Void'::text WHEN COALESCE(p.amount_paid, 0::numeric) = 0::numeric THEN 'Pending'::text WHEN COALESCE(p.amount_paid, 0::numeric) < i.total_amount THEN 'Partial'::text ELSE 'Reconciled'::text END AS reconciliation_status, i.issue_date, i.due_date FROM invoices i LEFT JOIN paid p ON p.id_invoice = i.id_invoice`);

export const vLedger = pgView("v_ledger", {	// You can use { mode: "bigint" } if numbers are exceeding js number limitations
	idTransaction: bigint("id_transaction", { mode: "number" }),
	idClinic: integer("id_clinic"),
	transactionDate: date("transaction_date"),
	idCategory: integer("id_category"),
	categoryName: varchar("category_name", { length: 100 }),
	financialType: enumFinancialType("financial_type"),
	amount: numeric({ precision: 12, scale:  2 }),
	signedAmount: numeric("signed_amount"),
	idMethod: integer("id_method"),
	idCounterparty: integer("id_counterparty"),
	idPayeeUser: integer("id_payee_user"),
	idAsset: integer("id_asset"),
	assetLinkType: enumAssetLinkType("asset_link_type"),
	idServiceLine: integer("id_service_line"),
	description: text(),
}).as(sql`SELECT t.id_transaction, t.id_clinic, t.transaction_date, t.id_category, fc.category_name, fc.financial_type, t.amount, CASE fc.financial_type WHEN 'Income'::enum_financial_type THEN t.amount ELSE - t.amount END AS signed_amount, t.id_method, t.id_counterparty, t.id_payee_user, t.id_asset, t.asset_link_type, t.id_service_line, t.description FROM transactions t JOIN financial_categories fc ON fc.id_category = t.id_category WHERE t.transaction_status = 'Completed'::enum_transaction_status`);

export const vClinicAssets = pgView("v_clinic_assets", {	idAsset: integer("id_asset"),
	idClinic: integer("id_clinic"),
	assetName: varchar("asset_name", { length: 150 }),
	serialNumber: varchar("serial_number", { length: 100 }),
	isDepreciable: boolean("is_depreciable"),
	idDepCategory: integer("id_dep_category"),
	acquisitionCost: numeric("acquisition_cost", { precision: 12, scale:  2 }),
	purchaseDate: date("purchase_date"),
	depreciationStartDate: date("depreciation_start_date"),
	assetStatus: enumAssetStatus("asset_status"),
	disposalDate: date("disposal_date"),
	disposalAmount: numeric("disposal_amount", { precision: 12, scale:  2 }),
	createdAt: timestamp("created_at", { withTimezone: true, mode: 'string' }),
	updatedAt: timestamp("updated_at", { withTimezone: true, mode: 'string' }),
	isFullyDepreciated: boolean("is_fully_depreciated"),
}).as(sql`SELECT a.id_asset, a.id_clinic, a.asset_name, a.serial_number, a.is_depreciable, a.id_dep_category, a.acquisition_cost, a.purchase_date, a.depreciation_start_date, a.asset_status, a.disposal_date, a.disposal_amount, a.created_at, a.updated_at, a.asset_status = 'Active'::enum_asset_status AND a.is_depreciable AND (a.depreciation_start_date + make_interval(months => dc.useful_life_months))::date <= CURRENT_DATE AS is_fully_depreciated FROM clinic_assets a LEFT JOIN depreciation_categories dc ON dc.id_dep_category = a.id_dep_category`);

export const vUserPermissions = pgView("v_user_permissions", {	idUser: integer("id_user"),
	permissionCode: varchar("permission_code", { length: 100 }),
}).as(sql`SELECT u.id_user, p.permission_code FROM users u JOIN role_permissions rp ON rp.id_role = u.id_role JOIN permissions p ON p.id_permission = rp.id_permission WHERE u.active`);

export const vUserClinics = pgView("v_user_clinics", {	idUser: integer("id_user"),
	idClinic: integer("id_clinic"),
	accessVia: text("access_via"),
	expiresAt: timestamp("expires_at", { withTimezone: true, mode: 'string' }),
}).as(sql`SELECT u.id_user, u.id_clinic, 'home'::text AS access_via, NULL::timestamp with time zone AS expires_at FROM users u WHERE u.active AND u.id_clinic IS NOT NULL UNION SELECT up.id_user, c.id_clinic, 'all_clinics'::text AS access_via, NULL::timestamp with time zone AS expires_at FROM v_user_permissions up CROSS JOIN clinics c WHERE up.permission_code::text = 'clinics.view_all'::text AND c.active UNION SELECT a.id_user, a.id_clinic, 'grant'::text AS access_via, a.expires_at FROM user_clinic_access a JOIN users u ON u.id_user = a.id_user WHERE u.active AND a.revoked_at IS NULL AND now() < a.expires_at`);