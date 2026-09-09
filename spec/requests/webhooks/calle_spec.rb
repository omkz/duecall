require "rails_helper"

RSpec.describe "CALL-E webhooks", type: :request do
  let!(:user) { User.create!(email_address: "owner@example.com", password: "password") }
  let!(:customer) { user.customers.create!(name: "Acme") }
  let!(:contact) { customer.contacts.create!(name: "Rina", phone_number: "+628123456789") }
  let!(:invoice) do
    customer.invoices.create!(number: "INV-001", amount_cents: 12_500, due_on: Date.current - 1.day)
  end
  let!(:call_attempt) do
    invoice.call_attempts.create!(contact: contact, provider_call_id: "call_123")
  end

  def deliver(payload, event_id: payload["id"], content_type: "application/json")
    headers = { "CONTENT_TYPE" => content_type }
    headers["CALL-E-Event-Id"] = event_id if event_id
    post webhooks_calle_path, params: payload.to_json, headers: headers
  end

  def completed_payload(event_id: "evt_123", provider_call_id: "call_123", outcome: "promised_to_pay")
    {
      "id" => event_id,
      "type" => "call.completed",
      "data" => {
        "id" => provider_call_id,
        "status" => "completed",
        "structured_result" => {
          "outcome" => outcome,
          "reason" => "Payment is awaiting internal approval.",
          "promise_to_pay_on" => "2026-09-15",
          "sentiment" => "neutral"
        },
        "summary" => "The recipient promised to pay on September 15.",
        "completed_at" => "2026-09-10T10:05:00Z",
        "recipients" => [
          {
            "phones" => [ "+628123456789" ],
            "attempts" => [
              {
                "id" => "att_1",
                "started_at" => "2026-09-10T10:00:00Z",
                "completed_at" => "2026-09-10T10:04:00Z",
                "transcript_turns" => [
                  { "offset_seconds" => 0, "speaker" => "bot", "text" => "Hello, I'm calling about the invoice." },
                  { "offset_seconds" => 8, "speaker" => "user", "text" => "We can pay next Tuesday." },
                  { "speaker" => "system", "text" => "Internal routing detail" },
                  { "speaker" => "bot" }
                ]
              },
              {
                "started_at" => "2026-09-10T09:59:00Z",
                "completed_at" => "2026-09-10T10:03:00Z"
              }
            ]
          }
        ]
      }
    }
  end

  it "works without authentication or a browser CSRF token" do
    original_forgery_protection = ActionController::Base.allow_forgery_protection
    ActionController::Base.allow_forgery_protection = true

    deliver(completed_payload)

    expect(response).to have_http_status(:ok)
    expect(response.parsed_body).to eq("ok" => true)
  ensure
    ActionController::Base.allow_forgery_protection = original_forgery_protection
  end

  it "rejects a missing event id header" do
    deliver(completed_payload, event_id: nil)

    expect(response).to have_http_status(:bad_request)
  end

  it "rejects a missing body event id" do
    payload = completed_payload
    payload.delete("id")
    deliver(payload, event_id: "evt_123")

    expect(response).to have_http_status(:bad_request)
  end

  it "rejects mismatched header and body event ids" do
    deliver(completed_payload, event_id: "evt_different")

    expect(response).to have_http_status(:bad_request)
  end

  it "rejects non-JSON requests" do
    deliver(completed_payload, content_type: "text/plain")

    expect(response).to have_http_status(:unsupported_media_type)
  end

  it "updates a CallAttempt from the terminal CallTask id and completed result" do
    deliver(completed_payload)

    expect(response).to have_http_status(:ok)
    expect(call_attempt.reload).to be_completed
    expect(call_attempt).to be_promised_to_pay
    expect(call_attempt.reason).to eq("Payment is awaiting internal approval.")
    expect(call_attempt.promise_to_pay_on).to eq(Date.new(2026, 9, 15))
    expect(call_attempt.sentiment).to eq("neutral")
    expect(call_attempt.summary).to eq("The recipient promised to pay on September 15.")
    expect(call_attempt.transcript).to eq(
      "Bot: Hello, I'm calling about the invoice.\nUser: We can pay next Tuesday."
    )
    expect(call_attempt.started_at).to eq(Time.iso8601("2026-09-10T09:59:00Z"))
    expect(call_attempt.completed_at).to eq(Time.iso8601("2026-09-10T10:05:00Z"))
    expect(call_attempt.raw_result).to eq(completed_payload["data"])

    event = WebhookEvent.find_by!(provider: "calle", event_id: "evt_123")
    expect(event.processed_at).to be_present
  end

  it "maps an unsupported provider outcome to unknown" do
    deliver(completed_payload(event_id: "evt_unknown", outcome: "provider_added_value"))

    expect(response).to have_http_status(:ok)
    expect(call_attempt.reload).to be_unknown
  end

  it "ignores an invalid promise date and invalid timestamps" do
    payload = completed_payload(event_id: "evt_invalid_dates")
    payload["data"]["structured_result"]["promise_to_pay_on"] = "next someday"
    payload["data"]["completed_at"] = "not-a-time"
    payload["data"]["recipients"][0]["attempts"].each do |attempt|
      attempt["started_at"] = "invalid"
      attempt["completed_at"] = "invalid"
    end

    deliver(payload)

    expect(response).to have_http_status(:ok)
    expect(call_attempt.reload.promise_to_pay_on).to be_nil
    expect(call_attempt.started_at).to be_nil
    expect(call_attempt.completed_at).to be_nil
  end

  it "maps a failed event and preserves failure details" do
    payload = {
      "id" => "evt_failed",
      "data" => {
        "id" => call_attempt.provider_call_id,
        "status" => "failed",
        "summary" => "The call could not be connected.",
        "failure_code" => "provider_unavailable",
        "failure_message" => "Carrier rejected the call.",
        "completed_at" => "2026-09-10T10:05:00Z"
      }
    }

    deliver(payload)

    expect(response).to have_http_status(:ok)
    expect(call_attempt.reload).to be_failed
    expect(call_attempt.summary).to eq("The call could not be connected.")
    expect(call_attempt.completed_at).to eq(Time.iso8601("2026-09-10T10:05:00Z"))
    expect(call_attempt.raw_result).to include(
      "failure_code" => "provider_unavailable",
      "failure_message" => "Carrier rejected the call."
    )
  end

  it "maps a canceled event to failed" do
    payload = {
      "id" => "evt_canceled",
      "data" => {
        "id" => call_attempt.provider_call_id,
        "status" => "canceled",
        "summary" => "The call was canceled."
      }
    }

    deliver(payload)

    expect(response).to have_http_status(:ok)
    expect(call_attempt.reload).to be_failed
    expect(call_attempt.raw_result["status"]).to eq("canceled")
  end

  it "acknowledges a duplicate event without processing it twice" do
    payload = completed_payload(event_id: "evt_duplicate")
    deliver(payload)
    call_attempt.reload.update_column(:summary, "Reviewed locally")

    expect do
      deliver(payload)
    end.not_to change(WebhookEvent, :count)

    expect(response).to have_http_status(:ok)
    expect(response.parsed_body).to eq("ok" => true)
    expect(call_attempt.reload.summary).to eq("Reviewed locally")
  end

  it "acknowledges an unknown CallTask id without mutating another attempt" do
    payload = completed_payload(event_id: "evt_unknown_call", provider_call_id: "call_unknown")
    payload["data"]["metadata"] = { "call_attempt_id" => call_attempt.id.to_s }

    deliver(payload)

    expect(response).to have_http_status(:ok)
    expect(call_attempt.reload).to be_pending
    event = WebhookEvent.find_by!(provider: "calle", event_id: "evt_unknown_call")
    expect(event.processed_at).to be_present
  end

  it "does not use mismatched metadata to update a different provider call" do
    other_attempt = invoice.call_attempts.create!(contact: contact, provider_call_id: "call_other", status: :failed)
    payload = completed_payload(event_id: "evt_mismatch", provider_call_id: call_attempt.provider_call_id)
    payload["data"]["metadata"] = { "call_attempt_id" => other_attempt.id.to_s }

    deliver(payload)

    expect(response).to have_http_status(:ok)
    expect(call_attempt.reload).to be_pending
    expect(other_attempt.reload).to be_failed
  end

  it "fails cleanly for malformed JSON" do
    post webhooks_calle_path,
      params: "{not-json",
      headers: { "CONTENT_TYPE" => "application/json", "CALL-E-Event-Id" => "evt_bad" }

    expect(response).to have_http_status(:bad_request)
    expect(response.parsed_body).to eq("ok" => false)
  end
end
