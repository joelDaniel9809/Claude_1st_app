import "server-only";
import { count } from "drizzle-orm";
import { db, schema } from "./db";

export type SystemStatus =
  | { ok: true; roles: number; permissions: number; categories: number; clinics: number }
  | { ok: false };

// Read-only check used on the home page while the app is being built.
export async function getSystemStatus(): Promise<SystemStatus> {
  try {
    const [[roles], [permissions], [categories], [clinics]] = await Promise.all([
      db.select({ n: count() }).from(schema.roles),
      db.select({ n: count() }).from(schema.permissions),
      db.select({ n: count() }).from(schema.financialCategories),
      db.select({ n: count() }).from(schema.clinics),
    ]);
    return {
      ok: true,
      roles: roles.n,
      permissions: permissions.n,
      categories: categories.n,
      clinics: clinics.n,
    };
  } catch (error) {
    console.error("Database check failed:", error);
    return { ok: false };
  }
}
