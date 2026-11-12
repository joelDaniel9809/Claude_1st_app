import "server-only";
import { drizzle } from "drizzle-orm/node-postgres";
import { sql } from "drizzle-orm";
import { Pool } from "pg";
import * as schema from "./generated/schema";
import * as relations from "./generated/relations";

// The table definitions in ./generated are produced by "npm run db:pull"
// from the real database. Don't edit them by hand: change the database
// with a migration in ../sql/migrations, run it, then pull again.

const fullSchema = { ...schema, ...relations };

function createDb() {
  const url = process.env.DATABASE_URL;
  if (!url) throw new Error("DATABASE_URL is not set. Copy app/.env.example to app/.env.");
  const pool = new Pool({ connectionString: url, max: 10 });
  return drizzle(pool, { schema: fullSchema });
}

// Reuse one connection pool across hot reloads in development.
const globalForDb = globalThis as unknown as { db?: ReturnType<typeof createDb> };
export const db = globalForDb.db ?? createDb();
if (process.env.NODE_ENV !== "production") globalForDb.db = db;

export type Db = typeof db;
export type Tx = Parameters<Parameters<Db["transaction"]>[0]>[0];

/** Who is acting. userId null = system action. */
export type Actor = { userId: number | null; ip?: string | null };

/**
 * Run database work as a specific user, inside one transaction.
 *
 * Sets app.user_id and app.client_ip for this transaction only, so the
 * database's automatic audit log records who did each insert/update/delete.
 * EVERY write in the app must go through this helper.
 */
export async function withActor<T>(actor: Actor, work: (tx: Tx) => Promise<T>): Promise<T> {
  return db.transaction(async (tx) => {
    await tx.execute(sql`
      select set_config('app.user_id', ${actor.userId === null ? "" : String(actor.userId)}, true),
             set_config('app.client_ip', ${actor.ip ?? ""}, true)
    `);
    return work(tx);
  });
}

export { schema };
