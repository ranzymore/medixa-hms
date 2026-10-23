# Setup

## Requirements

- Node.js `20+`
- `pnpm` (the repo also ships `pnpm` as a dependency, so `npx pnpm` works in a pinch)
- Postgres `17.x` (locally) **or** access to the live Supabase project
- Optional: Docker, `psql`, `pg_dump` / `pg_restore` (matched to Postgres 17)

## Install

```bash
pnpm install
```

If pnpm warns about ignored build scripts for `@tailwindcss/oxide`, `sharp`, or `unrs-resolver`, that's non-fatal — Tailwind falls back to its WASM build. Approve them with `pnpm approve-builds` if you want the native binaries.

## Environment

Create `.env.local` at the repo root:

```env
DATABASE_URL=postgresql://<user>:<password>@<host>:<port>/<db>
secret_key=any-long-random-string
```

`database/db.ts` throws on import if `DATABASE_URL` is missing.

## Option A — connect to the live Supabase DB

Pull the env directly from Vercel (recommended):

```bash
pnpm dlx vercel login
pnpm dlx vercel link        # link this folder to the project
pnpm dlx vercel env pull .env.local
```

That writes a fully-populated `.env.local`. Use the **Development** environment when prompted unless you want production.

If you don't have Vercel access, copy the connection string from the Supabase Dashboard:

- Settings → Database → Connection string → **Session pooler** tab (recommended for dev)
- The pooler URL uses username `postgres.<project-ref>` and port `5432` or `6543`

Common errors:

- `(ENOTFOUND) tenant/user postgres.xxxxxx not found` — the Supabase project is **paused** (free tier auto-pauses after ~7 days idle). Restore it from the Supabase Dashboard. The dev server picks it up on the next request — no restart needed.
- `Error: DATABASE_URL is required` — file is missing or not in the repo root.

## Option B — fully local Postgres (offline-friendly)

Useful when the Supabase project is paused, you want a sandbox, or you're on a plane.

### 1. Dump from Supabase

Use the **Direct** connection (port `5432`, host `db.<project-ref>.supabase.co`) — `pg_dump` needs features the pooler strips.

```bash
# Recommended: custom format (compressed, restorable selectively)
pg_dump -Fc --no-owner --no-privileges \
  -d "postgresql://postgres:<password>@db.<project-ref>.supabase.co:5432/postgres" \
  -f hms.dump

# Plain SQL alternative (human-readable; slower to restore)
pg_dump -Fp --no-owner --no-privileges \
  -d "postgresql://postgres:<password>@db.<project-ref>.supabase.co:5432/postgres" \
  -f hms.sql
```

`--no-owner --no-privileges` strips Supabase-specific roles so it restores cleanly into a generic local Postgres.

### 2. Run Postgres locally

The fastest option is Docker, with the same major version as Supabase (`17.x`):

```bash
docker run -d --name hms-pg \
  -e POSTGRES_PASSWORD=hms \
  -e POSTGRES_DB=hms \
  -p 5432:5432 \
  -v hms-pgdata:/var/lib/postgresql/data \
  postgres:17
```

Native installs (Homebrew / `apt` / installer) work fine too — just create a `hms` database first.

### 3. Restore

```bash
# Custom-format dump:
pg_restore --no-owner --no-privileges \
  -d "postgresql://postgres:hms@localhost:5432/hms" hms.dump

# Plain-SQL dump:
psql "postgresql://postgres:hms@localhost:5432/hms" -f hms.sql
```

Some lines may warn about missing roles or `auth.*` schema — that's expected when restoring outside Supabase. Public schema, triggers, functions, and data restore correctly.

### 4. Point the app at it

Edit `.env.local`:

```env
DATABASE_URL=postgresql://postgres:hms@localhost:5432/hms
secret_key=any-long-random-string
```

The pool in [database/db.ts](../database/db.ts) sets `ssl: { rejectUnauthorized: false }` unconditionally. For local Postgres without SSL, either set it conditionally:

```ts
const isLocal = /localhost|127\.0\.0\.1/.test(process.env.DATABASE_URL ?? "");
const pool = new Pool({
  connectionString: process.env.DATABASE_URL,
  ssl: isLocal ? false : { rejectUnauthorized: false },
});
```

…or run Postgres with TLS enabled.

## Run

```bash
pnpm dev
```

The dev server listens on `http://localhost:3000`. First load is ~2–3 s with Turbopack; subsequent HMR is sub-second.

Look for `✅ Connected to Cloud Database (Supabase)` in the server logs. The message is printed on import even for non-Supabase URLs — ignore the wording.

## Other commands

```bash
pnpm lint                                                           # ESLint
pnpm test                                                           # Vitest, jsdom env
pnpm test path/to/file.test.ts                                      # single file
pnpm test -t "test name pattern"                                    # filter by name
pnpm build && pnpm start                                            # production build
pnpm docs                                                           # TypeDoc to docs/
node --env-file=.env.local scripts/introspect-db.mjs                # refresh database/snapshot/
```

## Refreshing the DB snapshot

After applying a migration to Supabase (or your local restore), refresh the introspection so future Claude sessions have current schema:

```bash
node --env-file=.env.local scripts/introspect-db.mjs
```

That regenerates the 8 files under [`database/snapshot/`](../database/snapshot/).

## First-time login data

Fastest local setup: `scripts/db-reset-local.sh` drops the local `public` schema, restores the newest `db/dump/*.sql` (Supabase schema + demo data), and resets every doctor/staff password to `password123`. It refuses to run unless `DATABASE_URL` points at localhost.

The seeded `doctor` and `staff` rows use codes like `DOC001`–`DOC005` and `STF001`–`STF007`. Some have plaintext `password123`; others have scrypt-hashed passwords. The lookup endpoint is `GET /api/login/<userCode>`; the credential check is `POST /api/login`. Successful plaintext logins auto-upgrade to scrypt on the same request.
