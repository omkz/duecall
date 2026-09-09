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

  it "allows an authenticated user to view their call attempt and invoice history" do
    call_attempt = invoice.call_attempts.create!(
      contact: contact,
      status: :completed,
      outcome: :promised_to_pay,
      promise_to_pay_on: Date.current + 2.days,
      sentiment: "positive",
      reason: "Invoice reminder",
      summary: "Rina promised to pay this week.",
      transcript: "Agent: Hello\nRina: I will pay this week.",
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
      "Invoice reminder",
      "positive",
      "Agent: Hello"
    )
    expect(response.body).not_to include("do not display", "private_provider_payload")
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
end
