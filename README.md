# DueCall

DueCall helps accounts-receivable teams track overdue invoices and follow up with customer contacts using CALL-E.

## Local setup

Requirements: Ruby, PostgreSQL, and the versions pinned by the repository.

```bash
bin/setup
bin/rails server
```

Run the test suite with:

```bash
bin/rspec
```

## Deploying to Render

The [Render Blueprint](render.yaml) provisions one Docker web service and one PostgreSQL instance in Singapore. Rails uses four logical databases on that single instance:

- `duecall_production`
- `duecall_production_cache`
- `duecall_production_queue`
- `duecall_production_cable`

The existing Docker entrypoint runs `bin/rails db:prepare` before starting Rails. On the initial deployment this creates and prepares the logical databases and loads the demo seed. On later deployments, `db:prepare` migrates existing databases without rerunning seeds against an already initialized primary database.

The Blueprint supplies individual host, port, user, and password values. Do not add `DATABASE_URL`, because it would override this explicit multi-database configuration.

The Blueprint uses Render's free plans for an initial demo. Free Render PostgreSQL instances currently expire after 30 days, so upgrade the database plan before using this setup for persistent production data.

To deploy:

1. In Render, create a Blueprint from `render.yaml`.
2. Enter the requested secret values for `RAILS_MASTER_KEY`, `CALLE_API_KEY`, and `DUECALL_DEMO_PASSWORD`. Do not store these values in the repository.
3. Wait for the initial Docker deployment and database preparation to finish.
4. Verify `https://<actual-render-hostname>/up` returns a successful response.
5. Copy the web service's actual `.onrender.com` hostname.
6. Add `CALLE_WEBHOOK_URL=https://<actual-render-hostname>/webhooks/calle` to the Render web service.
7. Redeploy or restart the service if Render does not apply the environment change automatically.
8. Sign in as `demo@duecall.test` with the configured `DUECALL_DEMO_PASSWORD`.

Render terminates HTTPS at its load balancer. Thruster listens for public HTTP traffic on port 10000 and forwards it to Puma on port 3000; Thruster TLS is intentionally not enabled.

The production Active Storage service currently uses the container's local disk. Render web-service filesystems are ephemeral, so persistent uploads will require object storage in a future deployment.
