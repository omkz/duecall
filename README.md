# DueCall

## CALL-E Goal Run configuration

DueCall submits overdue-invoice follow-ups through an already-published CALL-E Goal. Configure these server-side environment variables:

* `CALLE_API_KEY` — CALL-E API key.
* `CALLE_OVERDUE_INVOICE_GOAL_ID` — public ID of the published overdue-invoice Goal.
* `CALLE_BASE_URL` — optional; defaults to `https://api.heycall-e.com`.

The API key and Goal ID may instead be stored under `calle.api_key` and
`calle.overdue_invoice_goal_id` in Rails credentials. Never expose the API key
to browser code.

`call_attempt.run_calle_goal!` submits one Goal Run. The model derives a stable
idempotency key, saves the public Goal Run ID in `provider_goal_run_id`, and
records the provider response in `raw_result`.

`call_attempt.sync_calle_goal!` fetches that Goal Run once and synchronizes the
latest provider response. Result payloads remain intact in `raw_result` unless
an explicit published result schema is available for mapping.

# Rails application notes

This README would normally document whatever steps are necessary to get the
application up and running.

Things you may want to cover:

* Ruby version

* System dependencies

* Configuration

* Database creation

* Database initialization

* How to run the test suite

* Services (job queues, cache servers, search engines, etc.)

* Deployment instructions

* ...
