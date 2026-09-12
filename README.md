# DueCall

## CALL-E Goal Run configuration

DueCall submits overdue-invoice follow-ups through an already-published CALL-E Goal. Configure these server-side environment variables:

* `CALLE_API_KEY` — CALL-E API key.
* `CALLE_OVERDUE_INVOICE_GOAL_ID` — public ID of the published overdue-invoice Goal.
* `CALLE_BASE_URL` — optional; defaults to `https://api.heycall-e.com`.

The API key and Goal ID may instead be stored under `calle.api_key` and
`calle.overdue_invoice_goal_id` in Rails credentials. Never expose the API key
to browser code.

`Calle::RunGoal.call(call_attempt: call_attempt)` submits one Goal Run. The
service derives a stable idempotency key from the persisted `CallAttempt`, saves
the public Goal Run ID in `provider_goal_run_id`, and records the provider
response in `raw_result`.

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
