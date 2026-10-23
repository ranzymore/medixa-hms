import { Pool } from 'pg';

if (!process.env.DATABASE_URL) {
  throw new Error("DATABASE_URL is required.");
}

const isLocal = /@(localhost|127\.0\.0\.1)\b/.test(process.env.DATABASE_URL);
// DATABASE_SSL=false for the in-stack Postgres container (host `db`, no TLS).
const useSsl = process.env.DATABASE_SSL ? process.env.DATABASE_SSL === "true" : !isLocal;

const pool = new Pool({
  connectionString: process.env.DATABASE_URL,
  ssl: useSsl ? { rejectUnauthorized: false } : false
});

console.log(`✅ Connected to ${useSsl ? 'Cloud Database (Supabase)' : 'local Postgres'}`);

export const query = (text: string, params?: any[]) => {
  return pool.query(text, params);
}
export default pool;
