require "rails_helper"

RSpec.describe "Dashboard", type: :request do
  let!(:user) { User.create!(email_address: "owner@example.com", password: "password") }

  it "redirects an unauthenticated visitor to sign in" do
    get root_path

    expect(response).to redirect_to(new_session_path)
  end

  context "when authenticated" do
    before do
      post session_path, params: { email_address: user.email_address, password: "password" }
    end

    it "shows a useful empty state for a brand new account" do
      get root_path

      expect(response).to have_http_status(:ok)
      expect(response.body).to include("Accounts receivable", "Add your first customer")
    end

    it "shows the all-caught-up state when the user has customers but no overdue invoices" do
      user.customers.create!(name: "Acme")

      get root_path

      expect(response.body).to include("No overdue invoices", "You're all caught up.")
    end

    it "calculates owned metrics, uses the latest call, and isolates recent activity" do
      customer = user.customers.create!(name: "Visible customer")
      contact = customer.contacts.create!(name: "Visible contact", phone_number: "+628123456789")
      usd_invoice = customer.invoices.create!(
        number: "VISIBLE-USD",
        amount_cents: 1_250_000,
        currency: "USD",
        due_on: Date.current - 10.days
      )
      customer.invoices.create!(
        number: "VISIBLE-EUR",
        amount_cents: 420_000,
        currency: "EUR",
        due_on: Date.current - 2.days
      )
      customer.invoices.create!(
        number: "PAID-OLD",
        amount_cents: 99_900,
        due_on: Date.current - 20.days,
        status: :paid
      )
      customer.invoices.create!(
        number: "CANCELLED-OLD",
        amount_cents: 88_800,
        due_on: Date.current - 20.days,
        status: :cancelled
      )
      future_invoice = customer.invoices.create!(
        number: "NOT-DUE",
        amount_cents: 77_700,
        due_on: Date.current + 2.days
      )

      usd_invoice.call_attempts.create!(
        contact: contact,
        status: :completed,
        outcome: :disputed,
        summary: "Older dispute",
        created_at: 2.hours.ago
      )
      latest_attempt = usd_invoice.call_attempts.create!(
        contact: contact,
        status: :completed,
        outcome: :invoice_not_received,
        summary: "Newest visible activity",
        created_at: 1.hour.ago
      )
      future_invoice.call_attempts.create!(contact: contact, status: :pending, created_at: 4.hours.ago)
      future_invoice.call_attempts.create!(
        contact: contact,
        status: :completed,
        outcome: :promised_to_pay,
        promise_to_pay_on: Date.current + 3.days,
        summary: "Future promise activity",
        created_at: 3.hours.ago
      )
      customer.invoices.create!(
        number: "ACTIVE-INVOICE",
        amount_cents: 5_000,
        due_on: Date.current + 5.days
      ).call_attempts.create!(contact: contact, status: :in_progress)

      other_user = User.create!(email_address: "private@example.com", password: "password")
      other_customer = other_user.customers.create!(name: "Private customer")
      other_contact = other_customer.contacts.create!(name: "Private contact", phone_number: "+628111111111")
      other_invoice = other_customer.invoices.create!(
        number: "PRIVATE-INVOICE",
        amount_cents: 9_999_900,
        currency: "USD",
        due_on: Date.current - 30.days
      )
      other_invoice.call_attempts.create!(
        contact: other_contact,
        status: :pending,
        summary: "Private activity"
      )

      get root_path

      expect(response).to have_http_status(:ok)
      expect(response.parsed_body.at_css("#overdue-count").text).to eq("2")
      expect(response.parsed_body.at_css("#active-call-count").text).to eq("2")
      expect(response.parsed_body.at_css("#payment-promise-count").text).to eq("1")
      expect(response.body).to include("USD 12,500.00", "EUR 4,200.00")
      expect(response.body).to include("VISIBLE-USD", "VISIBLE-EUR", "Newest visible activity", "Resend invoice")
      expect(response.body).not_to include("Review dispute")
      action_queue = response.parsed_body.at_css("#action-queue").text
      expect(action_queue).not_to include("PAID-OLD", "CANCELLED-OLD", "NOT-DUE")
      expect(response.body).not_to include("Private customer", "PRIVATE-INVOICE", "Private activity", "USD 99,999.00")
      expect(response.body.index(latest_attempt.summary)).to be < response.body.index("Future promise activity")
    end

    it "highlights an expired payment promise without changing the invoice status" do
      customer = user.customers.create!(name: "Acme")
      contact = customer.contacts.create!(name: "Rina", phone_number: "+628123456789")
      invoice = customer.invoices.create!(number: "MISSED", amount_cents: 10_000, due_on: Date.current - 5.days)
      invoice.call_attempts.create!(
        contact: contact,
        status: :completed,
        outcome: :promised_to_pay,
        promise_to_pay_on: Date.current - 1.day
      )

      get root_path

      expect(response.body).to include("Missed promise", "Payment promise overdue — follow up")
      expect(invoice.reload).to be_open
    end
  end
end
