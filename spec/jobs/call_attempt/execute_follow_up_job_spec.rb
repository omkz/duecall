require "rails_helper"

RSpec.describe CallAttempt::ExecuteFollowUpJob do
  let(:user) { User.create!(email_address: "owner@example.com", password: "password") }
  let(:customer) { user.customers.create!(name: "Acme") }
  let(:invoice) do
    customer.invoices.create!(number: "INV-001", amount_cents: 12_500, due_on: Date.current - 1.day)
  end
  let(:contact) do
    customer.contacts.create!(
      name: "Rina",
      phone_number: "+628123456789",
      time_zone: "Asia/Jakarta"
    )
  end
  let(:call_attempt) do
    invoice.call_attempts.create!(
      contact:,
      status: :completed,
      outcome: :payment_pending,
      next_action: :retry_call,
      next_action_on: Date.current
    )
  end

  it "delegates execution to the source CallAttempt" do
    expect(call_attempt).to receive(:execute_follow_up!)

    described_class.perform_now(call_attempt)
  end
end
