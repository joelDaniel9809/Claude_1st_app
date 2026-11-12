// After "drizzle-kit pull", keep only schema.ts and relations.ts.
// drizzle-kit also writes a migration file and a meta/ folder, but
// migrations are owned by dbmate (../sql/migrations), so they're removed.
import { readdirSync, rmSync } from "node:fs";
import { join } from "node:path";

const dir = "src/server/db/generated";
for (const name of readdirSync(dir)) {
  if (name === "schema.ts" || name === "relations.ts") continue;
  rmSync(join(dir, name), { recursive: true, force: true });
  console.log(`removed ${join(dir, name)}`);
}
