require "rails_helper"

RSpec.describe "Invoices", type: :request do
  include ActiveJob::TestHelper

  let!(:user) { User.create!(email_address: "owner@example.com", password: "password") }
  let!(:other_user) { User.create!(email_address: "other@example.com", password: "password") }
  let!(:customer) { user.customers.create!(name: "Acme") }
  let!(:other_customer) { other_user.customers.create!(name: "Private customer") }

  before do
    ActiveJob::Base.queue_adapter = :test
    clear_enqueued_jobs
    post session_path, params: { email_address: user.email_address, password: "password" }
  end

  after { clear_enqueued_jobs }

  it "allows an authenticated user to CRUD invoices for their customer" do
    get invoices_path
    expect(response).to have_http_status(:ok)
    expect(response.body).to include("No invoices yet")

    get customer_path(customer)
    expect(response.body).to include("No invoices yet")

    get new_customer_invoice_path(customer)
    expect(response).to have_http_status(:ok)

    expect do
      post customer_invoices_path(customer), params: {
        invoice: {
          number: "INV-001",
          amount_cents: 12_500,
          currency: "usd",
          issued_on: Date.current,
          due_on: Date.current + 7.days,
          status: "open",
          external_id: "ERP-42",
          customer_id: other_customer.id
        }
      }
    end.to change(customer.invoices, :count).by(1)

    invoice = customer.invoices.find_by!(number: "INV-001")
    expect(invoice.customer).to eq(customer)
    expect(invoice.currency).to eq("USD")
    expect(response).to redirect_to(invoice_path(invoice))

    get customer_path(customer)
    expect(response.body).to include("INV-001", "USD 125.00")

    get invoices_path
    expect(response.body).to include("INV-001", "Acme", "USD 125.00")

    get invoice_path(invoice)
    expect(response).to have_http_status(:ok)
    expect(response.body).to include("INV-001", "USD 125.00", "ERP-42")

    get edit_invoice_path(invoice)
    expect(response).to have_http_status(:ok)

    patch invoice_path(invoice), params: {
      invoice: { number: "INV-UPDATED", status: "paid", customer_id: other_customer.id }
    }
    expect(response).to redirect_to(invoice_path(invoice))
    expect(invoice.reload.number).to eq("INV-UPDATED")
    expect(invoice).to be_paid
    expect(invoice.customer).to eq(customer)

    expect do
      delete invoice_path(invoice)
    end.to change(customer.invoices, :count).by(-1)
    expect(response).to redirect_to(customer_path(customer))
  end

  it "isolates invoices belonging to another user" do
    own_invoice = customer.invoices.create!(
      number: "VISIBLE",
      amount_cents: 10_000,
      due_on: Date.current
    )
    invoice = other_customer.invoices.create!(
      number: "PRIVATE",
      amount_cents: 20_000,
      due_on: Date.current
    )

    get invoices_path
    expect(response.body).to include(own_invoice.number)
    expect(response.body).not_to include(invoice.number, other_customer.name)

    get invoice_path(invoice)
    expect(response).to have_http_status(:not_found)

    get edit_invoice_path(invoice)
    expect(response).to have_http_status(:not_found)

    patch invoice_path(invoice), params: { invoice: { number: "COMPROMISED" } }
    expect(response).to have_http_status(:not_found)
    expect(invoice.reload.number).to eq("PRIVATE")

    delete invoice_path(invoice)
    expect(response).to have_http_status(:not_found)
    expect(Invoice.exists?(invoice.id)).to be(true)
  end

  it "rejects creation under another user's customer" do
    expect do
      post customer_invoices_path(other_customer), params: {
        invoice: { number: "INTRUDER", amount_cents: 10_000, due_on: Date.current }
      }
    end.not_to change(Invoice, :count)

    expect(response).to have_http_status(:not_found)
  end

  it "explicitly enables and disables autonomy and schedules an existing retry" do
    invoice = customer.invoices.create!(
      number: "AUTO-INV",
      amount_cents: 10_000,
      due_on: Date.current - 1.day
    )
    contact = customer.contacts.create!(
      name: "Rina",
      phone_number: "+628123456789",
      time_zone: "Asia/Jakarta"
    )
    call_attempt = invoice.call_attempts.create!(
      contact:,
      status: :completed,
      outcome: :payment_pending,
      next_action: :retry_call,
      next_action_on: Date.current + 1.day
    )

    get invoice_path(invoice)
    expect(response.body).to include("Autonomous follow-up", "disabled", "Enable autonomous follow-up")

    expect do
      patch autonomous_follow_up_invoice_path(invoice), params: { enabled: true }
    end.to have_enqueued_job(CallAttempt::ExecuteFollowUpJob).with(call_attempt)

    expect(response).to redirect_to(invoice_path(invoice))
    expect(invoice.reload).to be_autonomous_follow_up_enabled

    patch autonomous_follow_up_invoice_path(invoice), params: { enabled: false }

    expect(invoice.reload).not_to be_autonomous_follow_up_enabled
  end

  it "does not allow autonomy changes on another user's invoice" do
    invoice = other_customer.invoices.create!(
      number: "PRIVATE-AUTO",
      amount_cents: 10_000,
      due_on: Date.current - 1.day
    )

    patch autonomous_follow_up_invoice_path(invoice), params: { enabled: true }

    expect(response).to have_http_status(:not_found)
    expect(invoice.reload).not_to be_autonomous_follow_up_enabled
  end

  describe "dashboard metrics" do
    def metric_value_for(document, label)
      label_node = document.css("p").find { |p| p.text.strip == label }
      label_node.parent.css("p")[1].text.strip
    end

    it "shows zero-state metrics and no recent call attempts when there is no data" do
      get invoices_path

      expect(response).to have_http_status(:ok)
      document = Nokogiri::HTML5.parse(response.body)

      [
        "Overdue invoices",
        "Calls awaiting result",
        "Autonomous retries",
        "Promises to pay",
        "Human attention required"
      ].each do |label|
        expect(metric_value_for(document, label)).to eq("0")
      end

      expect(response.body).not_to include("Recent call attempts")
    end

    it "counts each metric independently and lists recent call attempts, scoped to the current user" do
      contact = customer.contacts.create!(
        name: "Dana", phone_number: "+15555550100", time_zone: "America/New_York"
      )
      overdue_invoice = customer.invoices.create!(
        number: "M-1", amount_cents: 10_000, due_on: Date.current - 3,
        autonomous_follow_up_enabled: true
      )
      future_invoice = customer.invoices.create!(
        number: "M-2", amount_cents: 20_000, due_on: Date.current + 10
      )

      overdue_invoice.call_attempts.create!(contact: contact, status: :in_progress)
      overdue_invoice.call_attempts.create!(
        contact: contact, status: :completed, outcome: :payment_pending,
        next_action: :retry_call, next_action_on: Date.current + 1
      )
      future_invoice.call_attempts.create!(
        contact: contact, status: :completed, outcome: :promised_to_pay,
        promise_to_pay_on: Date.current + 2
      )
      overdue_invoice.call_attempts.create!(
        contact: contact, status: :completed, outcome: :wrong_contact, next_action: :human_followup
      )
      # Not counted as an autonomous retry: autonomous follow-up is disabled on this invoice.
      future_invoice.call_attempts.create!(
        contact: contact, status: :completed, outcome: :payment_pending,
        next_action: :retry_call, next_action_on: Date.current + 1
      )

      other_contact = other_customer.contacts.create!(
        name: "Other contact", phone_number: "+15555550199"
      )
      other_invoice = other_customer.invoices.create!(
        number: "PRIVATE-M-1", amount_cents: 5_000, due_on: Date.current - 1
      )
      other_invoice.call_attempts.create!(contact: other_contact, status: :in_progress)

      get invoices_path
      expect(response).to have_http_status(:ok)
      document = Nokogiri::HTML5.parse(response.body)

      expect(metric_value_for(document, "Overdue invoices")).to eq("1")
      expect(metric_value_for(document, "Calls awaiting result")).to eq("1")
      expect(metric_value_for(document, "Autonomous retries")).to eq("1")
      expect(metric_value_for(document, "Promises to pay")).to eq("1")
      expect(metric_value_for(document, "Human attention required")).to eq("1")

      expect(response.body).to include("Recent call attempts", "Dana", "M-1", "M-2")
      expect(response.body).not_to include("Other contact", "PRIVATE-M-1")
    end
  end
end
