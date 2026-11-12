// drizzle-kit is used ONLY to read the database and generate TypeScript
// types ("npm run db:pull"). Schema changes are made with SQL migrations
// in ../sql/migrations (dbmate), never with drizzle-kit push/migrate.
import { defineConfig } from "drizzle-kit";

process.loadEnvFile?.(".env");

export default defineConfig({
  dialect: "postgresql",
  out: "./src/server/db/generated",
  dbCredentials: { url: process.env.DATABASE_URL! },
  schemaFilter: ["public"],
  tablesFilter: ["!schema_migrations"],
  introspect: { casing: "camel" },
});
