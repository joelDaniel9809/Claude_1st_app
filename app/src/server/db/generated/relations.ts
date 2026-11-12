import { relations } from "drizzle-orm/relations";
import { users, userClinicAccess, clinics, auditLog, serviceLines, clinicAssets, depreciationCategories, operatorAllocations, transactions, financialCategories, paymentMethods, counterparties, invoices, invoiceLines, reconciliationHistory, roles, rolePermissions, permissions, invoiceNumberSequences } from "./schema";

export const userClinicAccessRelations = relations(userClinicAccess, ({one}) => ({
	user_idUser: one(users, {
		fields: [userClinicAccess.idUser],
		references: [users.idUser],
		relationName: "userClinicAccess_idUser_users_idUser"
	}),
	user_idGrantedBy: one(users, {
		fields: [userClinicAccess.idGrantedBy],
		references: [users.idUser],
		relationName: "userClinicAccess_idGrantedBy_users_idUser"
	}),
	clinic: one(clinics, {
		fields: [userClinicAccess.idClinic],
		references: [clinics.idClinic]
	}),
}));

export const usersRelations = relations(users, ({one, many}) => ({
	userClinicAccesses_idUser: many(userClinicAccess, {
		relationName: "userClinicAccess_idUser_users_idUser"
	}),
	userClinicAccesses_idGrantedBy: many(userClinicAccess, {
		relationName: "userClinicAccess_idGrantedBy_users_idUser"
	}),
	auditLogs: many(auditLog),
	operatorAllocations: many(operatorAllocations),
	transactions_idRegisteredBy: many(transactions, {
		relationName: "transactions_idRegisteredBy_users_idUser"
	}),
	transactions_idPayeeUser: many(transactions, {
		relationName: "transactions_idPayeeUser_users_idUser"
	}),
	reconciliationHistories: many(reconciliationHistory),
	clinic: one(clinics, {
		fields: [users.idClinic],
		references: [clinics.idClinic]
	}),
	role: one(roles, {
		fields: [users.idRole],
		references: [roles.idRole]
	}),
}));

export const clinicsRelations = relations(clinics, ({many}) => ({
	userClinicAccesses: many(userClinicAccess),
	auditLogs: many(auditLog),
	serviceLines: many(serviceLines),
	clinicAssets: many(clinicAssets),
	transactions: many(transactions),
	invoices: many(invoices),
	users: many(users),
	counterparties: many(counterparties),
	invoiceNumberSequences: many(invoiceNumberSequences),
}));

export const auditLogRelations = relations(auditLog, ({one}) => ({
	user: one(users, {
		fields: [auditLog.idUser],
		references: [users.idUser]
	}),
	clinic: one(clinics, {
		fields: [auditLog.idClinic],
		references: [clinics.idClinic]
	}),
}));

export const serviceLinesRelations = relations(serviceLines, ({one, many}) => ({
	clinic: one(clinics, {
		fields: [serviceLines.idClinic],
		references: [clinics.idClinic]
	}),
	operatorAllocations: many(operatorAllocations),
	transactions: many(transactions),
	invoiceLines: many(invoiceLines),
}));

export const clinicAssetsRelations = relations(clinicAssets, ({one, many}) => ({
	clinic: one(clinics, {
		fields: [clinicAssets.idClinic],
		references: [clinics.idClinic]
	}),
	depreciationCategory: one(depreciationCategories, {
		fields: [clinicAssets.idDepCategory],
		references: [depreciationCategories.idDepCategory]
	}),
	operatorAllocations: many(operatorAllocations),
	transactions: many(transactions),
}));

export const depreciationCategoriesRelations = relations(depreciationCategories, ({many}) => ({
	clinicAssets: many(clinicAssets),
}));

export const operatorAllocationsRelations = relations(operatorAllocations, ({one}) => ({
	user: one(users, {
		fields: [operatorAllocations.idUser],
		references: [users.idUser]
	}),
	clinicAsset: one(clinicAssets, {
		fields: [operatorAllocations.idAsset],
		references: [clinicAssets.idAsset]
	}),
	serviceLine: one(serviceLines, {
		fields: [operatorAllocations.idServiceLine],
		references: [serviceLines.idServiceLine]
	}),
}));

export const transactionsRelations = relations(transactions, ({one, many}) => ({
	clinic: one(clinics, {
		fields: [transactions.idClinic],
		references: [clinics.idClinic]
	}),
	financialCategory: one(financialCategories, {
		fields: [transactions.idCategory],
		references: [financialCategories.idCategory]
	}),
	paymentMethod: one(paymentMethods, {
		fields: [transactions.idMethod],
		references: [paymentMethods.idMethod]
	}),
	user_idRegisteredBy: one(users, {
		fields: [transactions.idRegisteredBy],
		references: [users.idUser],
		relationName: "transactions_idRegisteredBy_users_idUser"
	}),
	user_idPayeeUser: one(users, {
		fields: [transactions.idPayeeUser],
		references: [users.idUser],
		relationName: "transactions_idPayeeUser_users_idUser"
	}),
	counterparty: one(counterparties, {
		fields: [transactions.idCounterparty],
		references: [counterparties.idCounterparty]
	}),
	clinicAsset: one(clinicAssets, {
		fields: [transactions.idClinic],
		references: [clinicAssets.idAsset]
	}),
	serviceLine: one(serviceLines, {
		fields: [transactions.idClinic],
		references: [serviceLines.idServiceLine]
	}),
	reconciliationHistories: many(reconciliationHistory),
}));

export const financialCategoriesRelations = relations(financialCategories, ({many}) => ({
	transactions: many(transactions),
	invoiceLines: many(invoiceLines),
}));

export const paymentMethodsRelations = relations(paymentMethods, ({many}) => ({
	transactions: many(transactions),
}));

export const counterpartiesRelations = relations(counterparties, ({one, many}) => ({
	transactions: many(transactions),
	invoices: many(invoices),
	clinic: one(clinics, {
		fields: [counterparties.idClinic],
		references: [clinics.idClinic]
	}),
}));

export const invoicesRelations = relations(invoices, ({one, many}) => ({
	clinic: one(clinics, {
		fields: [invoices.idClinic],
		references: [clinics.idClinic]
	}),
	counterparty: one(counterparties, {
		fields: [invoices.idCounterparty],
		references: [counterparties.idCounterparty]
	}),
	invoiceLines: many(invoiceLines),
	reconciliationHistories: many(reconciliationHistory),
}));

export const invoiceLinesRelations = relations(invoiceLines, ({one}) => ({
	invoice: one(invoices, {
		fields: [invoiceLines.idInvoice],
		references: [invoices.idInvoice]
	}),
	financialCategory: one(financialCategories, {
		fields: [invoiceLines.financialType],
		references: [financialCategories.idCategory]
	}),
	serviceLine: one(serviceLines, {
		fields: [invoiceLines.idServiceLine],
		references: [serviceLines.idServiceLine]
	}),
}));

export const reconciliationHistoryRelations = relations(reconciliationHistory, ({one}) => ({
	invoice: one(invoices, {
		fields: [reconciliationHistory.idInvoice],
		references: [invoices.idInvoice]
	}),
	transaction: one(transactions, {
		fields: [reconciliationHistory.idTransaction],
		references: [transactions.idTransaction]
	}),
	user: one(users, {
		fields: [reconciliationHistory.idUser],
		references: [users.idUser]
	}),
}));

export const rolesRelations = relations(roles, ({many}) => ({
	users: many(users),
	rolePermissions: many(rolePermissions),
}));

export const rolePermissionsRelations = relations(rolePermissions, ({one}) => ({
	role: one(roles, {
		fields: [rolePermissions.idRole],
		references: [roles.idRole]
	}),
	permission: one(permissions, {
		fields: [rolePermissions.idPermission],
		references: [permissions.idPermission]
	}),
}));

export const permissionsRelations = relations(permissions, ({many}) => ({
	rolePermissions: many(rolePermissions),
}));

export const invoiceNumberSequencesRelations = relations(invoiceNumberSequences, ({one}) => ({
	clinic: one(clinics, {
		fields: [invoiceNumberSequences.idClinic],
		references: [clinics.idClinic]
	}),
}));