require "rails_helper"

RSpec.describe CallAttempt::CalleGoal do
  let(:user) { User.create!(email_address: "owner@example.com", password: "password") }
  let(:customer) { user.customers.create!(name: "Acme") }
  let(:invoice) do
    customer.invoices.create!(number: "INV-001", amount_cents: 12_500, due_on: Date.new(2026, 9, 1))
  end
  let(:contact) { customer.contacts.create!(name: "Rina", phone_number: "+628123456789") }
  let(:call_attempt) do
    CallAttempt.create!(
      invoice:,
      contact:,
      status: :in_progress,
      provider_goal_run_id: "rgrp_invoice_123",
      raw_result: { "status" => "queued" }
    )
  end
  let(:client) { instance_double(Calle::Client) }

  def provider_response(status:, result: nil, error: nil, call_id: nil, completed_at: nil)
    {
      "object" => "goal_run",
      "id" => "rgrp_invoice_123",
      "goal_id" => "goal_overdue",
      "run_id" => "run_invoice_123",
      "call_id" => call_id,
      "status" => status,
      "result" => result,
      "error" => error,
      "completed_at" => completed_at
    }
  end

  def sync_with(response)
    expect(client).to receive(:get_goal_run).with(
      goal_id: "goal_overdue",
      goal_run_id: "rgrp_invoice_123"
    ).and_return(response)

    call_attempt.sync_calle_goal!(client:, goal_id: "goal_overdue")
  end

  %w[queued in_progress].each do |provider_status|
    it "keeps the attempt in progress when the Goal Run is #{provider_status}" do
      response = provider_response(status: provider_status)

      sync_with(response)

      expect(call_attempt).to be_in_progress
      expect(call_attempt.raw_result).to eq(response)
      expect(call_attempt.completed_at).to be_nil
    end
  end

  it "keeps a completed Goal Run in progress while result materialization is pending" do
    response = provider_response(status: "completed", result: nil, error: nil)

    sync_with(response)

    expect(call_attempt).to be_in_progress
    expect(call_attempt.raw_result).to eq(response)
    expect(call_attempt.completed_at).to be_nil
  end

  it "maps a wrong contact result with a blank payment promise" do
    result = {
      "reason" => "The respondent was not available as a verified authorized contact.",
      "outcome" => "wrong_contact",
      "customer_summary" => "The hotline respondent could not verify or discuss the invoice.",
      "promise_to_pay_on" => ""
    }
    response = provider_response(
      status: "completed",
      result:,
      completed_at: "2026-09-12T02:15:00Z"
    )

    sync_with(response)

    expect(call_attempt).to be_completed
    expect(call_attempt).to be_wrong_contact
    expect(call_attempt.reason).to eq("The respondent was not available as a verified authorized contact.")
    expect(call_attempt.summary).to eq("The hotline respondent could not verify or discuss the invoice.")
    expect(call_attempt.promise_to_pay_on).to be_nil
    expect(call_attempt).to be_human_followup
    expect(call_attempt.next_action_on).to be_nil
    expect(call_attempt.raw_result).to eq(response)
    expect(call_attempt.completed_at).to eq(Time.iso8601("2026-09-12T02:15:00Z"))
  end

  it "maps a promised payment with a valid date" do
    response = provider_response(
      status: "completed",
      result: {
        "outcome" => "promised_to_pay",
        "promise_to_pay_on" => "2026-09-18",
        "reason" => "",
        "customer_summary" => "The customer committed to payment on September 18."
      }
    )

    sync_with(response)

    expect(call_attempt).to be_promised_to_pay
    expect(call_attempt.promise_to_pay_on).to eq(Date.new(2026, 9, 18))
    expect(call_attempt).to be_retry_call
    expect(call_attempt.next_action_on).to eq(Date.new(2026, 9, 19))
    expect(call_attempt.reason).to be_nil
    expect(call_attempt.summary).to eq("The customer committed to payment on September 18.")
    expect(call_attempt.raw_result).to eq(response)
  end

  it "maps the published unknown outcome" do
    response = provider_response(
      status: "completed",
      result: {
        "outcome" => "unknown",
        "promise_to_pay_on" => nil,
        "reason" => "Insufficient information",
        "customer_summary" => "The payment situation could not be determined."
      }
    )

    sync_with(response)

    expect(call_attempt).to be_unknown
    expect(call_attempt).to be_human_followup
    expect(call_attempt.next_action_on).to be_nil
    expect(call_attempt.raw_result).to eq(response)
  end

  it "maps an unexpected future outcome to unknown without changing the raw result" do
    response = provider_response(
      status: "completed",
      result: {
        "outcome" => "future_provider_outcome",
        "promise_to_pay_on" => "",
        "reason" => "New provider category",
        "customer_summary" => "Provider returned a category DueCall does not know yet."
      }
    )

    sync_with(response)

    expect(call_attempt).to be_completed
    expect(call_attempt).to be_unknown
    expect(call_attempt).to be_human_followup
    expect(call_attempt.raw_result).to eq(response)
    expect(call_attempt.raw_result.dig("result", "outcome")).to eq("future_provider_outcome")
  end

  it "ignores a malformed payment date and blank result text without breaking synchronization" do
    response = provider_response(
      status: "completed",
      result: {
        "outcome" => "payment_pending",
        "promise_to_pay_on" => "next week",
        "reason" => "  ",
        "customer_summary" => ""
      }
    )

    sync_with(response)

    expect(call_attempt).to be_completed
    expect(call_attempt).to be_payment_pending
    expect(call_attempt.promise_to_pay_on).to be_nil
    expect(call_attempt).to be_retry_call
    expect(call_attempt.next_action_on).to eq(Date.current + 2.days)
    expect(call_attempt.reason).to be_nil
    expect(call_attempt.summary).to be_nil
    expect(call_attempt.raw_result).to eq(response)
  end

  it "fails the attempt when the Goal Run returns an error" do
    response = provider_response(
      status: "failed",
      error: { "code" => "call_failed", "message" => "Recipient could not be reached" },
      completed_at: "2026-09-12T02:16:00Z"
    )

    sync_with(response)

    expect(call_attempt).to be_failed
    expect(call_attempt.outcome).to be_nil
    expect(call_attempt.next_action).to be_nil
    expect(call_attempt.next_action_on).to be_nil
    expect(call_attempt.raw_result).to eq(response)
    expect(call_attempt.completed_at).to eq(Time.iso8601("2026-09-12T02:16:00Z"))
  end

  it "preserves CALL-E call_id in provider_call_id" do
    response = provider_response(
      status: "in_progress",
      call_id: "calling_call_invoice_123"
    )

    sync_with(response)

    expect(call_attempt.provider_call_id).to eq("calling_call_invoice_123")
    expect(call_attempt.provider_goal_run_id).to eq("rgrp_invoice_123")
  end

  it "records an API request failure without treating the remote Goal Run as failed" do
    error = Calle::RequestError.new(
      "CALL-E rejected the Goal Run fetch with HTTP 503",
      details: {
        "http_status" => 503,
        "response" => { "error" => { "code" => "service_unavailable" } }
      }
    )
    allow(client).to receive(:get_goal_run).and_raise(error)

    call_attempt.sync_calle_goal!(client:, goal_id: "goal_overdue")

    expect(call_attempt).to be_in_progress
    expect(call_attempt.next_action).to be_nil
    expect(call_attempt.completed_at).to be_nil
    expect(call_attempt.raw_result).to include(
      "status" => "queued",
      "sync_error" => include(
        "http_status" => 503,
        "error_class" => "Calle::RequestError",
        "error_message" => "CALL-E rejected the Goal Run fetch with HTTP 503"
      )
    )
  end

  it "does not change a persisted decision when synchronization is rerun on a terminal attempt" do
    response = provider_response(
      status: "completed",
      result: {
        "outcome" => "already_paid",
        "promise_to_pay_on" => "",
        "reason" => "",
        "customer_summary" => "The invoice has been paid."
      }
    )
    sync_with(response)
    expect(call_attempt).to be_stop
    expect(call_attempt.next_action_on).to be_nil
    original_decision = call_attempt.attributes.slice("next_action", "next_action_on")
    expect(client).not_to receive(:get_goal_run)

    expect do
      call_attempt.sync_calle_goal!(client:, goal_id: "goal_overdue")
    end.to raise_error(CallAttempt::InvalidTransitionError)

    expect(call_attempt.reload.attributes.slice("next_action", "next_action_on")).to eq(original_decision)
  end
end
