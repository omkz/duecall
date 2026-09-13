# DueCall

## CALL-E Goal Run configuration

DueCall submits overdue-invoice follow-ups through an already-published CALL-E Goal. Configure these server-side environment variables:

* `CALLE_API_KEY` — CALL-E API key.
* `CALLE_OVERDUE_INVOICE_GOAL_ID` — public ID of the published overdue-invoice Goal.
* `DUECALL_CALLING_COMPANY_NAME` — company identity stated by the voice agent.
* `CALLE_BASE_URL` — optional; defaults to `https://api.heycall-e.com`.

The API key, Goal ID, and calling company name may instead be stored under
`calle.api_key`, `calle.overdue_invoice_goal_id`, and
`calle.calling_company_name` in Rails credentials. Never expose the API key to
browser code.

`call_attempt.run_calle_goal!` submits one Goal Run. The model derives a stable
idempotency key, saves the public Goal Run ID in `provider_goal_run_id`, and
records the provider response in `raw_result`.

`call_attempt.sync_calle_goal!` fetches that Goal Run once and synchronizes the
latest provider response. Result payloads remain intact in `raw_result` unless
an explicit published result schema is available for mapping.

## Local setup

Requirements: Ruby, PostgreSQL, and the versions pinned by the repository.
`bin/setup` runs `db:prepare`, which seeds a demo contact, so set
`DUECALL_DEMO_PHONE` to a valid E.164 phone number first (see
`db/seeds.rb`).

```bash
DUECALL_DEMO_PHONE=+15555550123 bin/setup
bin/dev
```

`bin/dev` starts three processes (see `Procfile.dev`): the Rails server, the
Tailwind watcher, and a Solid Queue worker (`bin/jobs`). Real-time updates on
the CallAttempt page are delivered over Action Cable using Solid Cable, so
development also uses three separate logical PostgreSQL databases —
`duecall_development`, `duecall_development_queue`, and
`duecall_development_cable` — configured in `config/database.yml` and
`config/cable.yml`.

Run the test suite with:

```bash
bin/rspec
```

## Background jobs and real-time updates

* **Solid Queue** runs `CallAttempt::SyncCalleGoalJob`, which polls CALL-E for
  the result of a submitted Goal Run. There is no CALL-E webhook; the app
  only uses polling jobs to synchronize call results.
* **Solid Cable** carries Action Cable traffic across processes (the web
  process and the Solid Queue worker). When a job updates a `CallAttempt`,
  the model broadcasts a Turbo Stream replacing that attempt's details
  partial, so the CallAttempt show page updates automatically without any
  client-side polling.

## Deploying to Render

The [Render Blueprint](render.yaml) provisions one Docker web service and one
PostgreSQL instance in Singapore. Rails uses four logical databases on that
single instance:

- `duecall_production`
- `duecall_production_cache`
- `duecall_production_queue`
- `duecall_production_cable`

The Blueprint supplies Render's internal PostgreSQL `connectionString` as
`DATABASE_URL`. The Rails database configuration (`config/database.yml`)
preserves that URL's scheme, credentials, host, port, and query parameters
while replacing only its database path for each logical database.

Solid Queue runs inside the same Puma process as the web server
(`SOLID_QUEUE_IN_PUMA=1`, see `config/puma.rb`) — there is no separate Render
background worker. Solid Cable uses its own `cable` logical database
(`config/cable.yml`, `config/environments/production.rb`).

The existing Docker entrypoint (`bin/docker-entrypoint`) runs
`bin/rails db:prepare` before starting Rails. On the initial deployment this
creates and prepares all four logical databases and seeds the primary
database (`db/seeds.rb`). On later deployments, `db:prepare` migrates
existing databases without reseeding an already-initialized primary
database.

The Blueprint uses Render's free plans for an initial demo. Free Render
PostgreSQL instances currently expire after 30 days, so upgrade the database
plan before using this setup for persistent production data.

### Required secrets

Render prompts for these when you create the Blueprint (`sync: false` in
`render.yaml`, never stored in the repository):

* `RAILS_MASTER_KEY` — from `config/master.key`.
* `CALLE_API_KEY` — CALL-E API key.
* `DUECALL_DEMO_PASSWORD` — password for the seeded demo user.
* `DUECALL_DEMO_PHONE` — E.164 phone number for the seeded demo contact (for
  example, the official CALL-E test hotline). `db/seeds.rb` requires this to
  be a valid E.164 number and raises during `db:prepare` if it is missing,
  so the very first deploy will fail to boot without it.

To actually place CALL-E calls (not just seed demo data), also add these as
regular environment variables on the web service after the Blueprint is
created — they are not part of `render.yaml` because they configure CALL-E
call behavior rather than infrastructure:

* `CALLE_OVERDUE_INVOICE_GOAL_ID` — public ID of the published overdue-invoice
  Goal.
* `DUECALL_CALLING_COMPANY_NAME` — company identity stated by the voice
  agent.

`DUECALL_DEMO_SEED` and `DUECALL_DEMO_EMAIL` are set by the Blueprint for
forward compatibility with a richer demo seed, but the current
`db/seeds.rb` seeds a single fixed demo account and does not read either
variable yet.

### To deploy

1. In Render, create a Blueprint from `render.yaml`.
2. Enter the requested secret values (`RAILS_MASTER_KEY`, `CALLE_API_KEY`,
   `DUECALL_DEMO_PASSWORD`, `DUECALL_DEMO_PHONE`). Do not store these values
   in the repository.
3. Wait for the initial Docker deployment and database preparation to
   finish.
4. Verify `https://<actual-render-hostname>/up` returns a successful
   response.
5. Add `CALLE_OVERDUE_INVOICE_GOAL_ID` and `DUECALL_CALLING_COMPANY_NAME` to
   the web service's environment if you want real CALL-E calls to succeed,
   then redeploy or restart.
6. Sign in as `demo@duecall.local` with the configured
   `DUECALL_DEMO_PASSWORD`.

Render terminates HTTPS at its load balancer. Thruster listens for public
HTTP traffic on port 10000 (`HTTP_PORT`) and forwards it to Puma on port 3000
(`TARGET_PORT`); Thruster TLS is intentionally not enabled.

The production Active Storage service currently uses the container's local
disk. Render web-service filesystems are ephemeral, so persistent uploads
will require object storage in a future deployment.
