# Deploying Medixa HMS (Atmos VPS)

Same pattern as the other ranzymore apps on the Atmos box (212.28.176.183):
GitHub Actions builds the image → GHCR → a repo-scoped self-hosted runner (user `github`)
runs `docker compose -p medixa-<env>` → host nginx + certbot terminate TLS.

| Branch    | Stack            | Host port      | URL                                  | GitHub environment |
|-----------|------------------|----------------|--------------------------------------|--------------------|
| `staging` | `medixa-staging` | 127.0.0.1:3301 | https://medixa-staging.wavesoms.com  | `staging`          |
| `main`    | `medixa-prod`    | 127.0.0.1:3300 | https://medixa.wavesoms.com          | `production`       |

Each stack = `medixa-app-<env>` (Next.js standalone) + `medixa-db-<env>` (Postgres 17, own volume).
Stack files live in `/home/github/medixa/<env>/` (written by the workflow, incl. a `0600` `.env`).

## Pipeline (`.github/workflows/deploy.yml`)

PRs into `main`/`staging`: lint + tsc + tests. Pushes additionally build `:<env>` and
`:<env>-<sha>` images, then deploy: pull → start db → `deploy/migrate.sh` → start app → health check.

**Database.** On first boot (empty volume) Postgres restores the newest `db/dump/*.sql`, sets every
doctor/staff password to `DEMO_PASSWORD`, and marks every migration in `database/migrations/` as applied.
After that, each deploy applies any new `database/migrations/*.sql` (not `.down.sql`) once, tracked in
`schema_migrations`. Each migration runs in a single transaction.

**Rollback.** Re-run the deploy job of an earlier green workflow run (it pins `IMAGE_TAG=<env>-<sha>`).
Migrations are not rolled back automatically; apply the `.down.sql` by hand if needed.

## One-time setup

1. **Repo access**: push + admin on `ranzymore/medixa-hms` (admin is needed for secrets and the runner).
2. **Branches**: create `main` and `staging` from the current branch.
3. **GitHub environments** `staging` and `production`, each with secrets
   (generate with `openssl rand -hex 32`; avoid `'` in values):
   - `POSTGRES_PASSWORD`
   - `SECRET_KEY` (JWT signing secret)
   - `DEMO_PASSWORD` (login password for all seeded accounts)
4. **DNS** (Namecheap, `wavesoms.com`): A records `medixa` and `medixa-staging` → `212.28.176.183`.
5. **Runner** (on the VPS, as `github`): repo Settings → Actions → Runners → New self-hosted runner, then
   ```sh
   mkdir ~/actions-runner-medixa && cd ~/actions-runner-medixa
   # download + extract the tarball shown on that page, then:
   ./config.sh --url https://github.com/ranzymore/medixa-hms --token <TOKEN> --name medixa-runner --unattended
   sudo ./svc.sh install github && sudo ./svc.sh start   # as root
   ```
6. **nginx + TLS** (as root, after DNS resolves):
   ```sh
   cp deploy/nginx/medixa-proxy.conf /etc/nginx/snippets/
   cp deploy/nginx/medixa.conf /etc/nginx/sites-available/medixa
   ln -s /etc/nginx/sites-available/medixa /etc/nginx/sites-enabled/medixa
   nginx -t && systemctl reload nginx
   certbot --nginx -d medixa.wavesoms.com -d medixa-staging.wavesoms.com
   ```
7. Push to `staging`, check the site, then merge `staging` → `main`.

## Day-to-day

```sh
ssh atmosgh
cd /home/github/medixa/staging
docker compose -p medixa-staging ps
docker compose -p medixa-staging logs -f app
docker exec -it medixa-db-staging psql -U medixa -d hms
```

Reset an environment to the demo dump (destroys its data):
`docker compose -p medixa-staging down -v`, then re-run its deploy.

**Backups:** the nightly job (`/root/data_backup_and_recovery_workflow`) only dumps the DB containers listed in
`backup_config.sh` (Odoo-shaped entries). `medixa-db-prod` is **not** covered until it is added there.
