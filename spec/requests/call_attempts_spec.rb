require "rails_helper"

RSpec.describe "Call attempts", type: :request do
  let!(:user) { User.create!(email_address: "owner@example.com", password: "password") }
  let!(:other_user) { User.create!(email_address: "other@example.com", password: "password") }
  let!(:customer) { user.customers.create!(name: "Acme") }
  let!(:contact) { customer.contacts.create!(name: "Rina", phone_number: "+628123456789") }
  let!(:invoice) do
    customer.invoices.create!(number: "INV-001", amount_cents: 12_500, due_on: Date.current)
  end

  before do
    post session_path, params: { email_address: user.email_address, password: "password" }
  end

  it "prominently presents a completed call result and readable transcript" do
    call_attempt = invoice.call_attempts.create!(
      contact: contact,
      status: :completed,
      outcome: :promised_to_pay,
      promise_to_pay_on: Date.current + 2.days,
      sentiment: "positive",
      reason: "Invoice reminder",
      summary: "Rina promised to pay this week.",
      transcript: "Agent: Hello\nRecipient: I will pay this week.",
      raw_result: { private_provider_payload: "do not display" },
      started_at: Time.current - 5.minutes,
      completed_at: Time.current
    )

    get invoice_path(invoice)
    expect(response).to have_http_status(:ok)
    expect(response.body).to include(
      "Call history",
      "Rina",
      "+628123456789",
      "Completed",
      "Promised to pay",
      "Rina promised to pay this week."
    )

    get call_attempt_path(call_attempt)
    expect(response).to have_http_status(:ok)
    expect(response.body).to include(
      "INV-001",
      "Acme",
      "Rina",
      "USD 125.00",
      "Call completed",
      "Outcome",
      "Promised to pay",
      "Invoice reminder",
      "Rina promised to pay this week.",
      "Promised payment",
      call_attempt.promise_to_pay_on.to_fs(:long),
      "Positive",
      "DueCall",
      "Customer",
      "Hello",
      "I will pay this week."
    )
    expect(response.body).not_to include("Payment promise missed", "Agent: Hello", "Recipient: I will pay")
    expect(response.body).not_to include("do not display", "private_provider_payload")
  end

  it "warns only when a promised payment date has passed on an open invoice" do
    missed_call = invoice.call_attempts.create!(
      contact: contact,
      status: :completed,
      outcome: :promised_to_pay,
      promise_to_pay_on: Date.current - 1.day
    )

    get call_attempt_path(missed_call)

    expect(response.body).to include("Payment promise missed")

    invoice.update!(status: :paid)
    get call_attempt_path(missed_call)

    expect(response.body).to include("Promised payment")
    expect(response.body).not_to include("Payment promise missed")
  end

  it "shows useful waiting copy for pending and in-progress calls" do
    [ :pending, :in_progress ].each do |status|
      call_attempt = invoice.call_attempts.create!(contact: contact, status: status)

      get call_attempt_path(call_attempt)

      expect(response.body).to include(
        status.to_s.humanize,
        "Call in progress",
        "DueCall is waiting for CALL-E to complete the conversation",
        "USD 125.00"
      )
      expect(response.body).not_to include("Outcome", "Not available", "Reason", "Not provided")
    end
  end

  it "shows a safe failed state without provider details" do
    call_attempt = invoice.call_attempts.create!(
      contact: contact,
      status: :failed,
      summary: "The recipient could not be reached.",
      raw_result: { failure_message: "private provider diagnostic" }
    )

    get call_attempt_path(call_attempt)

    expect(response.body).to include("Call failed", "The call could not be completed", call_attempt.summary)
    expect(response.body).not_to include("private provider diagnostic", "failure_message")
  end

  it "escapes transcript content while mapping known speakers" do
    call_attempt = invoice.call_attempts.create!(
      contact: contact,
      status: :completed,
      outcome: :unknown,
      transcript: "Bot: <script>alert('unsafe')</script>\nUser: Safe response"
    )

    get call_attempt_path(call_attempt)

    expect(response.body).to include("DueCall", "Customer", "&lt;script&gt;alert")
    expect(response.body).not_to include("<script>alert('unsafe')</script>")
  end

  it "shows call history only on the correct invoice" do
    call_attempt = invoice.call_attempts.create!(contact: contact, summary: "Correct invoice call")
    another_invoice = customer.invoices.create!(
      number: "INV-002",
      amount_cents: 8_000,
      due_on: Date.current
    )

    get invoice_path(invoice)
    expect(response.body).to include(call_attempt.summary)

    get invoice_path(another_invoice)
    expect(response.body).to include("No calls yet")
    expect(response.body).not_to include(call_attempt.summary)
  end

  it "does not expose another user's call attempt or call history" do
    other_customer = other_user.customers.create!(name: "Private customer")
    other_contact = other_customer.contacts.create!(name: "Private contact", phone_number: "+628111111111")
    other_invoice = other_customer.invoices.create!(
      number: "PRIVATE-INV",
      amount_cents: 20_000,
      due_on: Date.current
    )
    call_attempt = other_invoice.call_attempts.create!(
      contact: other_contact,
      summary: "Private call history"
    )

    get call_attempt_path(call_attempt)
    expect(response).to have_http_status(:not_found)

    get invoice_path(other_invoice)
    expect(response).to have_http_status(:not_found)

    get invoice_path(invoice)
    expect(response.body).not_to include("Private call history", "Private contact", "PRIVATE-INV")
  end

  describe "POST /invoices/:invoice_id/call_attempts" do
    let(:calle_client) { instance_double(Calle::Client) }
    let(:accepted_response) { { "id" => "call_task_123", "status" => "queued", "object" => "call_task" } }

    before do
      invoice.update!(due_on: Date.current - 1.day, status: :open)
      allow(Calle::Client).to receive(:new).and_return(calle_client)
    end

    it "starts a provider-backed call with the expected payload" do
      allow(calle_client).to receive(:create_call) do |payload:, idempotency_key:|
        expect(payload[:recipients]).to eq([ { phones: [ contact.phone_number ] } ])
        expect(payload[:task]).to include(
          "AI assistant",
          invoice.number,
          "USD 125.00",
          invoice.due_on.iso8601,
          "payment status",
          "human follow-up"
        )
        expect(payload[:result_schema]).to eq(
          type: "object",
          properties: {
            outcome: {
              type: "string",
              enum: CallAttempt.outcomes.keys,
              description: "The clearest supported payment follow-up outcome from the call evidence. Use unknown when the evidence is insufficient."
            },
            reason: {
              type: "string",
              description: "Short explanation of why payment is delayed or what happened during the call."
            },
            promise_to_pay_on: {
              type: "string",
              description: "Payment date explicitly committed to by the recipient, preferably YYYY-MM-DD. Omit when no clear date was committed."
            },
            sentiment: {
              type: "string",
              enum: %w[ positive neutral negative unknown ],
              description: "Overall recipient sentiment during the payment discussion."
            }
          },
          required: [ "outcome" ],
          additionalProperties: false
        )
        expect(payload[:metadata]).to eq(
          call_attempt_id: CallAttempt.last.id.to_s,
          invoice_id: invoice.id.to_s
        )
        expect(payload[:metadata].to_json).not_to include(customer.name, contact.phone_number)
        expect(idempotency_key).to eq("duecall-call-attempt-#{CallAttempt.last.id}")

        { "id" => "call_task_123", "status" => "queued", "object" => "call_task" }
      end

      get invoice_path(invoice)
      expect(response.body).to include("Follow up by phone", contact.name, contact.phone_number, "Start follow-up call")

      expect do
        post invoice_call_attempts_path(invoice), params: { contact_id: contact.id }
      end.to change(invoice.call_attempts, :count).by(1)

      call_attempt = invoice.call_attempts.last
      expect(call_attempt.contact).to eq(contact)
      expect(call_attempt.provider_call_id).to eq("call_task_123")
      expect(call_attempt).to be_pending
      expect(call_attempt.raw_result).to include("id" => "call_task_123")
      expect(response).to redirect_to(call_attempt_path(call_attempt))
    end

    it "includes the configured terminal webhook URL" do
      original_webhook_url = ENV["CALLE_WEBHOOK_URL"]
      ENV["CALLE_WEBHOOK_URL"] = "https://duecall.example/webhooks/calle"

      expect(calle_client).to receive(:create_call) do |payload:, **|
        expect(payload[:webhook_url]).to eq("https://duecall.example/webhooks/calle")
        accepted_response
      end

      post invoice_call_attempts_path(invoice), params: { contact_id: contact.id }

      expect(response).to have_http_status(:redirect)
    ensure
      ENV["CALLE_WEBHOOK_URL"] = original_webhook_url
    end

    it "rejects another user's invoice" do
      other_customer = other_user.customers.create!(name: "Private customer")
      other_contact = other_customer.contacts.create!(name: "Private contact", phone_number: "+628111111111")
      other_invoice = other_customer.invoices.create!(
        number: "PRIVATE-INV",
        amount_cents: 20_000,
        due_on: Date.current - 1.day
      )

      expect(calle_client).not_to receive(:create_call)

      expect do
        post invoice_call_attempts_path(other_invoice), params: { contact_id: other_contact.id }
      end.not_to change(CallAttempt, :count)

      expect(response).to have_http_status(:not_found)
    end

    it "does not create or dispatch a second call while one is pending" do
      expect(calle_client).to receive(:create_call).once.and_return(accepted_response)

      expect do
        post invoice_call_attempts_path(invoice), params: { contact_id: contact.id }
        post invoice_call_attempts_path(invoice), params: { contact_id: contact.id }
      end.to change(invoice.call_attempts, :count).by(1)

      active_call_attempt = invoice.call_attempts.active.first
      expect(response).to redirect_to(call_attempt_path(active_call_attempt))

      follow_redirect!
      expect(response.body).to include("A follow-up call is already in progress for this invoice")
    end

    it "does not create or dispatch another call while one is in progress" do
      active_call_attempt = invoice.call_attempts.create!(contact: contact, status: :in_progress)
      expect(calle_client).not_to receive(:create_call)

      expect do
        post invoice_call_attempts_path(invoice), params: { contact_id: contact.id }
      end.not_to change(CallAttempt, :count)

      expect(response).to redirect_to(call_attempt_path(active_call_attempt))
    end

    it "allows a retry after a failed call" do
      invoice.call_attempts.create!(contact: contact, status: :failed)
      expect(calle_client).to receive(:create_call).once.and_return(accepted_response)

      expect do
        post invoice_call_attempts_path(invoice), params: { contact_id: contact.id }
      end.to change(invoice.call_attempts, :count).by(1)

      expect(invoice.call_attempts.order(:id).last).to be_pending
    end

    it "allows another follow-up after a completed call" do
      invoice.call_attempts.create!(contact: contact, status: :completed)
      expect(calle_client).to receive(:create_call).once.and_return(accepted_response)

      expect do
        post invoice_call_attempts_path(invoice), params: { contact_id: contact.id }
      end.to change(invoice.call_attempts, :count).by(1)

      expect(invoice.call_attempts.order(:id).last).to be_pending
    end

    it "rejects a contact from another customer" do
      other_customer = user.customers.create!(name: "Another customer")
      other_contact = other_customer.contacts.create!(name: "Budi", phone_number: "+628111111111")
      expect(calle_client).not_to receive(:create_call)

      expect do
        post invoice_call_attempts_path(invoice), params: { contact_id: other_contact.id }
      end.not_to change(CallAttempt, :count)

      expect(response).to have_http_status(:not_found)
    end

    it "rejects a non-overdue invoice" do
      invoice.update!(due_on: Date.current + 1.day)
      expect(calle_client).not_to receive(:create_call)

      get invoice_path(invoice)
      expect(response.body).not_to include("Start follow-up call")

      expect do
        post invoice_call_attempts_path(invoice), params: { contact_id: contact.id }
      end.not_to change(CallAttempt, :count)

      expect(response).to redirect_to(invoice_path(invoice))
    end

    it "explains that an overdue invoice needs a contact" do
      contact.destroy!

      get invoice_path(invoice)

      expect(response.body).to include("Add a contact with a valid phone number", "Add contact")
      expect(response.body).not_to include("Start follow-up call")
    end

    it "rejects a contact whose stored phone number is invalid" do
      contact.update_column(:phone_number, "0812 3456 789")
      expect(calle_client).not_to receive(:create_call)

      expect do
        post invoice_call_attempts_path(invoice), params: { contact_id: contact.id }
      end.not_to change(CallAttempt, :count)

      expect(response).to redirect_to(invoice_path(invoice))
    end

    it "rejects a paid invoice" do
      invoice.update!(status: :paid)
      expect(calle_client).not_to receive(:create_call)

      expect do
        post invoice_call_attempts_path(invoice), params: { contact_id: contact.id }
      end.not_to change(CallAttempt, :count)

      expect(response).to redirect_to(invoice_path(invoice))
    end

    it "marks the CallAttempt failed when CALL-E rejects the request" do
      allow(calle_client).to receive(:create_call).and_raise(
        Calle::Error.new(
          "CALL-E request failed.",
          details: { "error" => "api_error", "http_status" => 422 }
        )
      )

      expect do
        post invoice_call_attempts_path(invoice), params: { contact_id: contact.id }
      end.to change(invoice.call_attempts, :count).by(1)

      call_attempt = invoice.call_attempts.last
      expect(call_attempt).to be_failed
      expect(call_attempt.raw_result).to eq("error" => "api_error", "http_status" => 422)

      follow_redirect!
      expect(response.body).to include("CALL-E could not start the call")
    end

    it "fails safely without making a request when the API key is missing" do
      original_api_key = ENV.delete("CALLE_API_KEY")
      allow(Calle::Client).to receive(:new).and_call_original
      expect(Net::HTTP).not_to receive(:start)

      post invoice_call_attempts_path(invoice), params: { contact_id: contact.id }

      call_attempt = invoice.call_attempts.last
      expect(call_attempt).to be_failed
      expect(call_attempt.raw_result).to eq("error" => "missing_api_key")

      follow_redirect!
      expect(response.body).to include("CALL-E is not configured")
      expect(response.body).not_to include("CALLE_API_KEY", "Authorization", "Bearer")
    ensure
      ENV["CALLE_API_KEY"] = original_api_key if original_api_key
    end
  end
end
