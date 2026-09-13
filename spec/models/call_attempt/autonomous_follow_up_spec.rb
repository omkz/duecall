require "rails_helper"

RSpec.describe CallAttempt::AutonomousFollowUp do
  include ActiveJob::TestHelper

  let(:user) { User.create!(email_address: "owner@example.com", password: "password") }
  let(:customer) { user.customers.create!(name: "Acme") }
  let(:invoice) do
    customer.invoices.create!(
      number: "INV-001",
      amount_cents: 12_500,
      due_on: Date.new(2026, 9, 1),
      autonomous_follow_up_enabled: true
    )
  end
  let(:contact) do
    customer.contacts.create!(
      name: "Rina",
      phone_number: "+628123456789",
      time_zone: "Asia/Jakarta"
    )
  end
  let(:source_attempt) do
    invoice.call_attempts.create!(
      contact:,
      status: :completed,
      outcome: :payment_pending,
      next_action: :retry_call,
      next_action_on: Date.new(2026, 9, 14),
      provider_goal_run_id: "rgrp_source",
      completed_at: Time.current
    )
  end
  let(:zone) { contact.configured_time_zone }

  before do
    ActiveJob::Base.queue_adapter = :test
    clear_enqueued_jobs
  end

  after { clear_enqueued_jobs }

  it "does not enqueue or call when autonomy is disabled" do
    invoice.update!(autonomous_follow_up_enabled: false)
    expect(Calle::Client).not_to receive(:new)

    expect do
      source_attempt.schedule_follow_up_execution!(now: zone.local(2026, 9, 14, 10))
      source_attempt.execute_follow_up!(now: zone.local(2026, 9, 14, 10))
    end.not_to have_enqueued_job(CallAttempt::ExecuteFollowUpJob)

    expect(source_attempt.follow_up_call_attempt).to be_nil
  end

  it "persists a new retry decision without scheduling execution when autonomy is disabled" do
    invoice.update!(autonomous_follow_up_enabled: false)
    source_attempt.update!(next_action: nil, next_action_on: nil)

    expect do
      source_attempt.decide_next_action!
    end.not_to have_enqueued_job(CallAttempt::ExecuteFollowUpJob)

    expect(source_attempt).to be_retry_call
    expect(source_attempt.next_action_on).to eq(Date.current + 2.days)
  end

  it "schedules an existing retry when autonomy is explicitly enabled" do
    invoice.update!(autonomous_follow_up_enabled: false)
    now = zone.local(2026, 9, 14, 8)

    expect do
      invoice.configure_autonomous_follow_up!(enabled: true, now:)
    end.to have_enqueued_job(CallAttempt::ExecuteFollowUpJob)
      .with(source_attempt)
      .at(zone.local(2026, 9, 14, 9))

    expect(invoice).to be_autonomous_follow_up_enabled
  end

  it "requires human follow-up instead of calling when the timezone is missing" do
    contact.update!(time_zone: nil)
    source_attempt
    expect(Calle::Client).not_to receive(:new)

    expect do
      source_attempt.execute_follow_up!(now: Time.utc(2026, 9, 14, 3))
    end.not_to change(CallAttempt, :count)

    expect(source_attempt.reload).to be_human_followup
    expect(source_attempt.next_action_on).to be_nil
  end

  it "reschedules weekend execution to Monday at 09:00 local time" do
    saturday = zone.local(2026, 9, 12, 11)
    source_attempt.update!(next_action_on: Date.new(2026, 9, 12))
    expect(Calle::Client).not_to receive(:new)

    expect do
      source_attempt.execute_follow_up!(now: saturday)
    end.to have_enqueued_job(CallAttempt::ExecuteFollowUpJob)
      .with(source_attempt)
      .at(zone.local(2026, 9, 14, 9))

    expect(source_attempt.follow_up_call_attempt).to be_nil
  end

  it "reschedules execution before business hours to 09:00 local time" do
    before_opening = zone.local(2026, 9, 14, 8)
    expect(Calle::Client).not_to receive(:new)

    expect do
      source_attempt.execute_follow_up!(now: before_opening)
    end.to have_enqueued_job(CallAttempt::ExecuteFollowUpJob)
      .with(source_attempt)
      .at(zone.local(2026, 9, 14, 9))
  end

  it "reschedules execution after business hours to the next business opening" do
    after_closing = zone.local(2026, 9, 14, 17)
    expect(Calle::Client).not_to receive(:new)

    expect do
      source_attempt.execute_follow_up!(now: after_closing)
    end.to have_enqueued_job(CallAttempt::ExecuteFollowUpJob)
      .with(source_attempt)
      .at(zone.local(2026, 9, 15, 9))
  end

  it "stops without calling when the invoice has been paid" do
    invoice.update!(status: :paid)
    source_attempt
    expect(Calle::Client).not_to receive(:new)

    expect { source_attempt.execute_follow_up!(now: zone.local(2026, 9, 14, 10)) }
      .not_to change(CallAttempt, :count)

    expect(source_attempt.reload).to be_stop
    expect(source_attempt.next_action_on).to be_nil
  end

  it "stops without calling when the invoice has been cancelled" do
    invoice.update!(status: :cancelled)
    expect(Calle::Client).not_to receive(:new)

    source_attempt.execute_follow_up!(now: zone.local(2026, 9, 14, 10))

    expect(source_attempt.reload).to be_stop
    expect(source_attempt.follow_up_call_attempt).to be_nil
  end

  it "requires human follow-up when the invoice is no longer overdue" do
    invoice.update!(due_on: Date.new(2026, 9, 14))
    expect(Calle::Client).not_to receive(:new)

    source_attempt.execute_follow_up!(now: zone.local(2026, 9, 14, 10))

    expect(source_attempt.reload).to be_human_followup
    expect(source_attempt.next_action_on).to be_nil
  end

  it "requires human follow-up after three submitted attempts" do
    2.times do |index|
      invoice.call_attempts.create!(
        contact:,
        status: :failed,
        provider_goal_run_id: "rgrp_prior_#{index}"
      )
    end
    expect(Calle::Client).not_to receive(:new)

    source_attempt.execute_follow_up!(now: zone.local(2026, 9, 14, 10))

    expect(source_attempt.reload).to be_human_followup
    expect(source_attempt.follow_up_call_attempt).to be_nil
  end

  it "creates and submits exactly one correctly linked child during business hours" do
    client = stub_successful_goal_submission
    expect(source_attempt).not_to receive(:run_calle_goal!)

    expect do
      source_attempt.execute_follow_up!(now: zone.local(2026, 9, 14, 10))
    end.to change(CallAttempt, :count).by(1)
      .and have_enqueued_job(CallAttempt::SyncCalleGoalJob)

    child = source_attempt.reload.follow_up_call_attempt
    expect(child.parent_call_attempt).to eq(source_attempt)
    expect(child.invoice).to eq(invoice)
    expect(child.contact).to eq(contact)
    expect(child).to be_in_progress
    expect(child.provider_goal_run_id).to eq("rgrp_child")
    expect(client).to have_received(:create_goal_run).once
  end

  it "is idempotent when the execution runs more than once" do
    client = stub_successful_goal_submission

    allow(Time).to receive(:current).and_return(zone.local(2026, 9, 14, 10))
    2.times { CallAttempt::ExecuteFollowUpJob.perform_now(source_attempt) }

    expect(source_attempt.reload.follow_up_call_attempt).to be_present
    expect(invoice.call_attempts.where(parent_call_attempt: source_attempt).count).to eq(1)
    expect(client).to have_received(:create_goal_run).once
  end

  it "does not count prepared attempts toward the submitted-call limit" do
    2.times { invoice.call_attempts.create!(contact:) }
    client = stub_successful_goal_submission

    source_attempt.execute_follow_up!(now: zone.local(2026, 9, 14, 10))

    expect(source_attempt.reload.follow_up_call_attempt).to be_in_progress
    expect(client).to have_received(:create_goal_run).once
  end

  private
    def stub_successful_goal_submission
      client = instance_double(Calle::Client)
      allow(Rails.application.config.x.calle).to receive(:overdue_invoice_goal_id).and_return("goal_overdue")
      allow(Rails.application.config.x.calle).to receive(:calling_company_name).and_return("DueCall Ltd")
      allow(Calle::Client).to receive(:new).and_return(client)
      allow(client).to receive(:create_goal_run).and_return(
        "id" => "rgrp_child",
        "status" => "queued",
        "result" => nil,
        "error" => nil
      )
      client
    end
end
