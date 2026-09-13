require "rails_helper"

RSpec.describe "Call attempts", type: :request do
  let!(:user) { User.create!(email_address: "owner@example.com", password: "password") }
  let!(:other_user) { User.create!(email_address: "other@example.com", password: "password") }
  let!(:customer) { user.customers.create!(name: "Acme") }
  let!(:contact) { customer.contacts.create!(name: "Rina", phone_number: "+628123456789") }
  let!(:invoice) do
    customer.invoices.create!(number: "INV-001", amount_cents: 12_500, due_on: Date.current - 1.day)
  end

  before do
    post session_path, params: { email_address: user.email_address, password: "password" }
  end

  it "allows an authenticated user to view their call attempt and invoice history" do
    call_attempt = invoice.call_attempts.create!(
      contact: contact,
      status: :completed,
      outcome: :promised_to_pay,
      promise_to_pay_on: Date.current + 2.days,
      next_action: :retry_call,
      next_action_on: Date.current + 3.days,
      sentiment: "positive",
      reason: "Invoice reminder",
      summary: "Rina promised to pay this week.",
      transcript: "Agent: Hello\nRina: I will pay this week.",
      raw_result: { private_provider_payload: "do not display" },
      provider_goal_run_id: "rgrp_invoice_123",
      provider_call_id: "calling_call_invoice_123",
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
      "Invoice reminder",
      "Next action",
      "Retry call",
      (Date.current + 3.days).to_fs(:long),
      "Autonomous follow-up",
      "Disabled",
      "Retry is waiting because autonomous follow-up is disabled for this invoice.",
      "positive",
      "Agent: Hello",
      "rgrp_invoice_123",
      "calling_call_invoice_123"
    )
    expect(response.body).not_to include("do not display", "private_provider_payload")
  end

  it "prepares a pending call for an explicitly selected customer contact without calling CALL-E" do
    expect(Calle::Client).not_to receive(:new)

    get invoice_path(invoice)
    expect(response.body).to include("Manual follow-up", "Rina", "+628123456789", "Prepare call")

    expect do
      post invoice_call_attempts_path(invoice), params: { contact_id: contact.id }
    end.to change(invoice.call_attempts, :count).by(1)

    call_attempt = invoice.call_attempts.order(:created_at).last
    expect(call_attempt).to be_pending
    expect(call_attempt.contact).to eq(contact)
    expect(call_attempt.provider_goal_run_id).to be_nil
    expect(response).to redirect_to(call_attempt_path(call_attempt))
  end

  it "rejects a contact belonging to another customer" do
    another_customer = user.customers.create!(name: "Another customer")
    another_contact = another_customer.contacts.create!(name: "Wrong contact", phone_number: "+628111111111")

    expect do
      post invoice_call_attempts_path(invoice), params: { contact_id: another_contact.id }
    end.not_to change(CallAttempt, :count)

    expect(response).to have_http_status(:not_found)
  end

  it "shows the selected details without invoking CALL-E on GET" do
    call_attempt = invoice.call_attempts.create!(contact: contact)
    expect_any_instance_of(CallAttempt).not_to receive(:run_calle_goal!)

    get call_attempt_path(call_attempt)

    expect(response).to have_http_status(:ok)
    expect(response.body).to include(
      "Call Rina at +628123456789",
      "INV-001",
      "USD 125.00",
      invoice.due_on.to_fs(:long),
      "Place CALL-E call",
      "This will place a real phone call to Rina at +628123456789. Continue?"
    )
  end

  it "invokes the domain behavior only when an owned pending call is explicitly triggered" do
    call_attempt = invoice.call_attempts.create!(contact: contact)
    expect_any_instance_of(CallAttempt).to receive(:run_calle_goal!) do |attempt|
      attempt.update!(status: :in_progress, provider_goal_run_id: "rgrp_invoice_123")
    end

    post run_call_attempt_path(call_attempt)

    expect(response).to redirect_to(call_attempt_path(call_attempt))
    follow_redirect!
    expect(response.body).to include("CALL-E call was submitted.", "rgrp_invoice_123")
  end

  it "shows a safe failure notice when the domain records a submission failure" do
    call_attempt = invoice.call_attempts.create!(contact: contact)
    expect_any_instance_of(CallAttempt).to receive(:run_calle_goal!) do |attempt|
      attempt.update!(
        status: :failed,
        raw_result: { "submission_error" => { "error_message" => "secret provider diagnostic" } }
      )
    end

    post run_call_attempt_path(call_attempt)

    expect(response).to redirect_to(call_attempt_path(call_attempt))
    follow_redirect!
    expect(response.body).to include(
      "CALL-E call could not be submitted. Review the configuration and prepare a new call."
    )
    expect(response.body).not_to include("secret provider diagnostic")
  end

  it "does not allow another user's call attempt to be triggered" do
    other_customer = other_user.customers.create!(name: "Private customer")
    other_contact = other_customer.contacts.create!(name: "Private contact", phone_number: "+628111111111")
    other_invoice = other_customer.invoices.create!(
      number: "PRIVATE-INV",
      amount_cents: 20_000,
      due_on: Date.current - 1.day
    )
    call_attempt = other_invoice.call_attempts.create!(contact: other_contact)
    expect_any_instance_of(CallAttempt).not_to receive(:run_calle_goal!)

    post run_call_attempt_path(call_attempt)

    expect(response).to have_http_status(:not_found)
    expect(call_attempt.reload).to be_pending
  end

  it "does not offer or prepare calls for invoices that are not overdue and open" do
    paid_invoice = customer.invoices.create!(
      number: "PAID-INV",
      amount_cents: 12_500,
      due_on: Date.current - 1.day,
      status: :paid
    )

    get invoice_path(paid_invoice)
    expect(response.body).not_to include("Manual follow-up", "Prepare call")

    expect do
      post invoice_call_attempts_path(paid_invoice), params: { contact_id: contact.id }
    end.not_to change(CallAttempt, :count)
    expect(response).to redirect_to(invoice_path(paid_invoice))
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

  it "subscribes to a Turbo Stream scoped to this specific call attempt" do
    call_attempt = invoice.call_attempts.create!(contact: contact, status: :in_progress)
    other_call_attempt = invoice.call_attempts.create!(contact: contact, status: :in_progress)

    get call_attempt_path(call_attempt)
    expect(response.body).to include("<turbo-cable-stream-source", "signed-stream-name")
    first_signed_stream_name = response.body[/signed-stream-name="([^"]+)"/, 1]

    get call_attempt_path(other_call_attempt)
    second_signed_stream_name = response.body[/signed-stream-name="([^"]+)"/, 1]

    expect(first_signed_stream_name).to be_present
    expect(second_signed_stream_name).to be_present
    expect(first_signed_stream_name).not_to eq(second_signed_stream_name)
  end

  it "shows the automatic-update message only while a call is in progress" do
    in_progress_call = invoice.call_attempts.create!(
      contact: contact,
      status: :in_progress,
      provider_goal_run_id: "rgrp_polling_123"
    )

    get call_attempt_path(in_progress_call)

    expect(response.body).to include(
      ActionView::RecordIdentifier.dom_id(in_progress_call, :details),
      "Waiting for CALL-E result… This page will update automatically."
    )

    pending_call = invoice.call_attempts.create!(contact: contact, status: :pending)
    completed_call = invoice.call_attempts.create!(
      contact: contact, status: :completed, completed_at: Time.current
    )
    failed_call = invoice.call_attempts.create!(contact: contact, status: :failed)

    [ pending_call, completed_call, failed_call ].each do |call_attempt|
      get call_attempt_path(call_attempt)

      expect(response.body).not_to include("Waiting for CALL-E result")
    end
  end

  it "labels automatic follow-up lineage and numbers attempts on the invoice call history" do
    root_call_attempt = invoice.call_attempts.create!(
      contact: contact,
      status: :completed,
      outcome: :payment_pending,
      next_action: :retry_call,
      next_action_on: Date.current + 1.day
    )
    follow_up_call_attempt = invoice.call_attempts.create!(
      contact: contact,
      parent_call_attempt: root_call_attempt
    )

    get invoice_path(invoice)

    document = Nokogiri::HTML5.parse(response.body)
    list_items = document.css("li")
    root_item = list_items.find { |li| li.text.include?("Attempt 1") }
    follow_up_item = list_items.find { |li| li.text.include?("Attempt 2") }

    expect(root_item.text).not_to include("Automatic follow-up")
    expect(follow_up_item.text).to include("Automatic follow-up")

    expect(root_item.to_html).to include("View automatic follow-up", call_attempt_path(follow_up_call_attempt))
    expect(follow_up_item.to_html).to include("Follow-up to previous call", call_attempt_path(root_call_attempt))
  end

  it "does not show an automatic follow-up badge for a manually prepared root attempt" do
    manual_call_attempt = invoice.call_attempts.create!(contact: contact, summary: "Manual outreach")

    get invoice_path(invoice)

    expect(response.body).to include("Attempt 1", "Manual outreach")
    expect(response.body).not_to include("Automatic follow-up")
  end

  it "shows follow-up lineage and safe navigation on the CallAttempt details page" do
    root_call_attempt = invoice.call_attempts.create!(
      contact: contact,
      status: :completed,
      outcome: :payment_pending,
      next_action: :retry_call,
      next_action_on: Date.current + 1.day
    )
    follow_up_call_attempt = invoice.call_attempts.create!(
      contact: contact,
      parent_call_attempt: root_call_attempt
    )

    get call_attempt_path(root_call_attempt)
    expect(response.body).not_to include("Automatic follow-up")
    expect(response.body).to include("View automatic follow-up", call_attempt_path(follow_up_call_attempt))

    get call_attempt_path(follow_up_call_attempt)
    expect(response.body).to include("Automatic follow-up")
    expect(response.body).to include("Follow-up to previous call", call_attempt_path(root_call_attempt))
  end

  it "does not imply a follow-up call happened when only a retry is scheduled" do
    root_call_attempt = invoice.call_attempts.create!(
      contact: contact,
      status: :completed,
      outcome: :payment_pending,
      next_action: :retry_call,
      next_action_on: Date.current + 1.day
    )

    get invoice_path(invoice)
    expect(response.body).not_to include("View automatic follow-up")

    get call_attempt_path(root_call_attempt)
    expect(response.body).not_to include("View automatic follow-up")
  end

  it "explains when human follow-up is required" do
    call_attempt = invoice.call_attempts.create!(
      contact:,
      status: :completed,
      outcome: :wrong_contact,
      next_action: :human_followup,
      completed_at: Time.current
    )

    get call_attempt_path(call_attempt)

    expect(response.body).to include(
      "Human followup",
      "Human follow-up is required. DueCall will not place another automatic call."
    )
  end
end
