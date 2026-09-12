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

  it "completes the attempt when a result is available without guessing field mappings" do
    response = provider_response(
      status: "completed",
      result: { "collection_outcome" => "custom_provider_value", "provider_notes" => "Call back Friday" },
      completed_at: "2026-09-12T02:15:00Z"
    )

    sync_with(response)

    expect(call_attempt).to be_completed
    expect(call_attempt.raw_result).to eq(response)
    expect(call_attempt.completed_at).to eq(Time.iso8601("2026-09-12T02:15:00Z"))
    expect(call_attempt.outcome).to be_nil
    expect(call_attempt.summary).to be_nil
  end

  it "fails the attempt when the Goal Run returns an error" do
    response = provider_response(
      status: "failed",
      error: { "code" => "call_failed", "message" => "Recipient could not be reached" },
      completed_at: "2026-09-12T02:16:00Z"
    )

    sync_with(response)

    expect(call_attempt).to be_failed
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
end
