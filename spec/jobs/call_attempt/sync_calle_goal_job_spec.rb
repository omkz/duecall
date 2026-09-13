require "rails_helper"

RSpec.describe CallAttempt::SyncCalleGoalJob do
  include ActiveJob::TestHelper
  include ActiveSupport::Testing::TimeHelpers

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
      provider_goal_run_id: "rgrp_invoice_123"
    )
  end

  before do
    ActiveJob::Base.queue_adapter = :test
    clear_enqueued_jobs
  end

  after { clear_enqueued_jobs }

  it "synchronizes and schedules the next poll while the attempt remains in progress" do
    allow(call_attempt).to receive(:sync_calle_goal!)

    travel_to(Time.zone.local(2026, 9, 14, 12)) do
      expect do
        described_class.perform_now(call_attempt, polls_remaining: 2)
      end.to have_enqueued_job(described_class)
        .with(call_attempt, polls_remaining: 1)
        .at(10.seconds.from_now)
    end

    expect(call_attempt).to have_received(:sync_calle_goal!).once
  end

  it "schedules the next poll after a temporary Goal Run fetch failure" do
    client = instance_double(Calle::Client)
    allow(Rails.application.config.x.calle).to receive(:overdue_invoice_goal_id)
      .and_return("goal_overdue")
    allow(Calle::Client).to receive(:new).and_return(client)
    allow(client).to receive(:get_goal_run).and_raise(
      Calle::RequestError.new("CALL-E is temporarily unavailable")
    )

    expect do
      described_class.perform_now(call_attempt, polls_remaining: 2)
    end.to have_enqueued_job(described_class).with(call_attempt, polls_remaining: 1)

    expect(call_attempt.reload).to be_in_progress
    expect(call_attempt.raw_result).to include(
      "sync_error" => include("error_class" => "Calle::RequestError")
    )
  end

  it "does not schedule another poll after synchronization completes the attempt" do
    allow(call_attempt).to receive(:sync_calle_goal!) do
      call_attempt.update!(status: :completed, completed_at: Time.current)
    end

    expect do
      described_class.perform_now(call_attempt, polls_remaining: 2)
    end.not_to have_enqueued_job(described_class)

    expect(call_attempt.reload).to be_completed
  end

  it "does not schedule another poll after synchronization fails the attempt" do
    allow(call_attempt).to receive(:sync_calle_goal!) do
      call_attempt.update!(status: :failed, completed_at: Time.current)
    end

    expect do
      described_class.perform_now(call_attempt, polls_remaining: 2)
    end.not_to have_enqueued_job(described_class)

    expect(call_attempt.reload).to be_failed
  end

  it "does nothing for an already terminal attempt" do
    call_attempt.update!(status: :completed, completed_at: Time.current)
    expect(call_attempt).not_to receive(:sync_calle_goal!)
    expect(Calle::Client).not_to receive(:new)

    expect do
      described_class.perform_now(call_attempt)
    end.not_to have_enqueued_job(described_class)
  end

  it "stops polling when the bounded poll count is exhausted" do
    allow(call_attempt).to receive(:sync_calle_goal!)

    expect do
      described_class.perform_now(call_attempt, polls_remaining: 1)
    end.not_to have_enqueued_job(described_class)

    expect(call_attempt).to have_received(:sync_calle_goal!).once
    expect(call_attempt.reload).to be_in_progress
  end

  it "only fetches the existing Goal Run and never submits another real call" do
    client = instance_double(Calle::Client)
    allow(Rails.application.config.x.calle).to receive(:overdue_invoice_goal_id)
      .and_return("goal_overdue")
    allow(Calle::Client).to receive(:new).and_return(client)
    expect(client).not_to receive(:create_goal_run)
    expect(client).to receive(:get_goal_run).with(
      goal_id: "goal_overdue",
      goal_run_id: "rgrp_invoice_123"
    ).and_return(
      "id" => "rgrp_invoice_123",
      "status" => "in_progress",
      "result" => nil,
      "error" => nil
    )

    expect do
      described_class.perform_now(call_attempt, polls_remaining: 2)
    end.to have_enqueued_job(described_class).with(call_attempt, polls_remaining: 1)
  end
end
