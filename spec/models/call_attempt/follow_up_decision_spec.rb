require "rails_helper"

RSpec.describe CallAttempt::FollowUpDecision do
  include ActiveSupport::Testing::TimeHelpers

  let(:user) { User.create!(email_address: "owner@example.com", password: "password") }
  let(:customer) { user.customers.create!(name: "Acme") }
  let(:invoice) do
    customer.invoices.create!(number: "INV-001", amount_cents: 12_500, due_on: Date.new(2026, 9, 1))
  end
  let(:contact) { customer.contacts.create!(name: "Rina", phone_number: "+628123456789") }

  def completed_attempt(outcome:, promise_to_pay_on: nil)
    invoice.call_attempts.create!(
      contact:,
      status: :completed,
      outcome:,
      promise_to_pay_on:,
      completed_at: Time.current
    )
  end

  it "stops after the customer reports the invoice is already paid" do
    call_attempt = completed_attempt(outcome: :already_paid)

    call_attempt.decide_next_action!

    expect(call_attempt).to be_stop
    expect(call_attempt.next_action_on).to be_nil
  end

  it "retries one day after a stated payment promise" do
    call_attempt = completed_attempt(
      outcome: :promised_to_pay,
      promise_to_pay_on: Date.new(2026, 9, 18)
    )

    call_attempt.decide_next_action!

    expect(call_attempt).to be_retry_call
    expect(call_attempt.next_action_on).to eq(Date.new(2026, 9, 19))
  end

  it "requires human follow-up when a promised payment has no date" do
    call_attempt = completed_attempt(outcome: :promised_to_pay)

    call_attempt.decide_next_action!

    expect(call_attempt).to be_human_followup
    expect(call_attempt.next_action_on).to be_nil
  end

  it "retries a pending payment in two days" do
    travel_to(Time.zone.local(2026, 9, 14, 12)) do
      call_attempt = completed_attempt(outcome: :payment_pending)

      call_attempt.decide_next_action!

      expect(call_attempt).to be_retry_call
      expect(call_attempt.next_action_on).to eq(Date.new(2026, 9, 16))
    end
  end

  %i[
    wrong_contact
    disputed
    refused
    human_followup_required
    invoice_not_received
    missing_information
    unknown
  ].each do |outcome|
    it "requires human follow-up for #{outcome}" do
      call_attempt = completed_attempt(outcome:)

      call_attempt.decide_next_action!

      expect(call_attempt).to be_human_followup
      expect(call_attempt.next_action_on).to be_nil
    end
  end

  it "retries a no-answer call when fewer than three terminal attempts exist" do
    invoice.call_attempts.create!(contact:, status: :completed, outcome: :no_answer)
    call_attempt = completed_attempt(outcome: :no_answer)

    travel_to(Time.zone.local(2026, 9, 14, 12)) do
      call_attempt.decide_next_action!

      expect(call_attempt).to be_retry_call
      expect(call_attempt.next_action_on).to eq(Date.new(2026, 9, 15))
    end
  end

  it "requires human follow-up once the no-answer attempt reaches the three-attempt limit" do
    invoice.call_attempts.create!(contact:, status: :completed, outcome: :no_answer)
    invoice.call_attempts.create!(contact:, status: :failed)
    call_attempt = completed_attempt(outcome: :no_answer)

    call_attempt.decide_next_action!

    expect(call_attempt).to be_human_followup
    expect(call_attempt.next_action_on).to be_nil
  end

  it "only persists a decision without creating or submitting another call" do
    call_attempt = completed_attempt(outcome: :already_paid)
    expect(Calle::Client).not_to receive(:new)

    expect do
      call_attempt.decide_next_action!
    end.not_to change(CallAttempt, :count)

    expect(call_attempt).to be_stop
  end

  it "does not decide for a provider failure" do
    call_attempt = invoice.call_attempts.create!(contact:, status: :failed, completed_at: Time.current)

    call_attempt.decide_next_action!

    expect(call_attempt.next_action).to be_nil
    expect(call_attempt.next_action_on).to be_nil
  end
end
