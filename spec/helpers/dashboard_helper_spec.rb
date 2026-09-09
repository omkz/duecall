require "rails_helper"

RSpec.describe DashboardHelper, type: :helper do
  let(:user) { User.create!(email_address: "helper@example.com", password: "password") }
  let(:customer) { user.customers.create!(name: "Acme") }
  let(:contact) { customer.contacts.create!(name: "Rina", phone_number: "+628123456789") }
  let(:invoice) do
    customer.invoices.create!(number: "INV-HELPER", amount_cents: 10_000, due_on: Date.current - 1.day)
  end

  def call_attempt(status: :completed, outcome: nil, promise_to_pay_on: nil)
    invoice.call_attempts.build(
      contact: contact,
      status: status,
      outcome: outcome,
      promise_to_pay_on: promise_to_pay_on
    )
  end

  it "recommends starting a call when there is no previous call" do
    expect(helper.recommended_next_action(invoice, nil)).to eq("Start follow-up call")
  end

  it "recommends waiting or following up based on a payment promise date" do
    future_promise = call_attempt(outcome: :promised_to_pay, promise_to_pay_on: Date.current + 1.day)
    expired_promise = call_attempt(outcome: :promised_to_pay, promise_to_pay_on: Date.current - 1.day)

    expect(helper.recommended_next_action(invoice, future_promise)).to eq("Wait for promised payment")
    expect(helper.recommended_next_action(invoice, expired_promise)).to eq("Payment promise overdue — follow up")
  end

  it "prioritizes an active call over its current outcome" do
    active_call = call_attempt(status: :in_progress, outcome: :disputed)

    expect(helper.recommended_next_action(invoice, active_call)).to eq("Call in progress")
  end

  it "maps common completed outcomes to a next action" do
    expect(helper.recommended_next_action(invoice, call_attempt(outcome: :disputed))).to eq("Review dispute")
    expect(helper.recommended_next_action(invoice, call_attempt(outcome: :invoice_not_received))).to eq("Resend invoice")
    expect(helper.recommended_next_action(invoice, call_attempt(outcome: :already_paid))).to eq("Verify payment")
  end
end
