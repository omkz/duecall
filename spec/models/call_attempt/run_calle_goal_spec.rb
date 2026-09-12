require "rails_helper"

RSpec.describe CallAttempt::CalleGoal do
  let(:user) { User.create!(email_address: "owner@example.com", password: "password") }
  let(:customer) { user.customers.create!(name: "Acme") }
  let(:invoice) do
    customer.invoices.create!(
      number: "INV-001",
      amount_cents: 12_500,
      currency: "usd",
      due_on: Date.new(2026, 9, 1)
    )
  end
  let(:contact) { customer.contacts.create!(name: "Rina", phone_number: "+628123456789") }
  let(:call_attempt) { CallAttempt.create!(invoice:, contact:) }
  let(:client) { instance_double(Calle::Client) }

  it "creates a Goal Run and moves the attempt to in progress" do
    provider_response = {
      "object" => "goal_run",
      "id" => "rgrp_invoice_123",
      "goal_id" => "goal_overdue",
      "run_id" => "run_invoice_123",
      "call_id" => nil,
      "status" => "queued",
      "result" => nil,
      "error" => nil
    }
    expect(client).to receive(:create_goal_run).with(
      goal_id: "goal_overdue",
      phone: "+628123456789",
      variables: {
        customer_name: "Acme",
        contact_name: "Rina",
        invoice_number: "INV-001",
        amount: 125.0,
        currency: "USD",
        due_date: "2026-09-01"
      },
      idempotency_key: "duecall:call_attempt:#{call_attempt.id}:overdue_invoice_goal:v1"
    ).and_return(provider_response)

    result = call_attempt.run_calle_goal!(client:, goal_id: "goal_overdue")

    expect(result).to eq(call_attempt)
    expect(call_attempt).to be_in_progress
    expect(call_attempt.provider_goal_run_id).to eq("rgrp_invoice_123")
    expect(call_attempt.raw_result).to eq(provider_response)
    expect(call_attempt.started_at).to be_present
    expect(call_attempt.provider_call_id).to be_nil
  end

  it "marks the attempt failed and saves provider error details when submission fails" do
    error = Calle::RequestError.new(
      "CALL-E rejected the Goal Run submission with HTTP 422",
      details: {
        "http_status" => 422,
        "response" => { "error" => { "code" => "invalid_variables" } }
      }
    )
    allow(client).to receive(:create_goal_run).and_raise(error)

    call_attempt.run_calle_goal!(client:, goal_id: "goal_overdue")

    expect(call_attempt).to be_failed
    expect(call_attempt.provider_goal_run_id).to be_nil
    expect(call_attempt.raw_result).to include(
      "submission_error" => include(
        "http_status" => 422,
        "response" => { "error" => { "code" => "invalid_variables" } },
        "error_class" => "Calle::RequestError"
      )
    )
  end

  it "does not submit an attempt that is no longer pending" do
    call_attempt.update!(status: :in_progress)
    expect(client).not_to receive(:create_goal_run)

    expect do
      call_attempt.run_calle_goal!(client:, goal_id: "goal_overdue")
    end.to raise_error(CallAttempt::InvalidTransitionError)
  end

  it "marks the attempt failed when configuration is missing" do
    call_attempt.run_calle_goal!(client:, goal_id: nil)

    expect(call_attempt).to be_failed
    expect(call_attempt.raw_result.dig("submission_error", "error_message")).to eq(
      "CALL-E overdue invoice Goal ID is not configured"
    )
  end
end
