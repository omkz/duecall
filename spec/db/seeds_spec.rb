require "rails_helper"

RSpec.describe "db/seeds.rb" do
  include ActiveJob::TestHelper

  before do
    ActiveJob::Base.queue_adapter = :test
    clear_enqueued_jobs
  end

  after { clear_enqueued_jobs }

  around do |example|
    original_email = ENV["DUECALL_DEMO_EMAIL"]
    original_phone = ENV["DUECALL_DEMO_PHONE"]
    original_password = ENV["DUECALL_DEMO_PASSWORD"]
    ENV["DUECALL_DEMO_EMAIL"] = "demo@duecall.test"
    ENV["DUECALL_DEMO_PHONE"] = "+628123456789"
    ENV["DUECALL_DEMO_PASSWORD"] = "demo-test-password"
    example.run
  ensure
    original_email ? ENV["DUECALL_DEMO_EMAIL"] = original_email : ENV.delete("DUECALL_DEMO_EMAIL")
    original_phone ? ENV["DUECALL_DEMO_PHONE"] = original_phone : ENV.delete("DUECALL_DEMO_PHONE")
    original_password ? ENV["DUECALL_DEMO_PASSWORD"] = original_password : ENV.delete("DUECALL_DEMO_PASSWORD")
  end

  it "creates the demo dataset idempotently without contacting CALL-E" do
    expect(Calle::Client).not_to receive(:new)

    expect do
      expect { load Rails.root.join("db/seeds.rb") }.to output(/DueCall demo data ready:/).to_stdout
    end.not_to have_enqueued_job

    user = User.find_by!(email_address: "demo@duecall.test")
    acme = user.customers.find_by!(name: "Acme Corporation")
    acme_contact = acme.contacts.find_by!(name: "Kurnia")
    acme_invoice = acme.invoices.find_by!(number: "INV-DEMO-001")
    northwind = user.customers.find_by!(name: "Northwind Logistics")
    northwind_contact = northwind.contacts.find_by!(name: "Demo Contact")
    autonomous_invoice = northwind.invoices.find_by!(number: "INV-DEMO-002")
    attention_invoice = northwind.invoices.find_by!(number: "INV-DEMO-003")
    disputed_attempt = attention_invoice.call_attempts.find_by!(
      "raw_result ->> 'demo_seed_key' = ?", "inv-demo-003-disputed"
    )
    records = [
      user, acme, acme_contact, acme_invoice, northwind, northwind_contact,
      autonomous_invoice, attention_invoice, disputed_attempt
    ]
    record_ids = records.map(&:id)
    counts = [ User.count, Customer.count, Contact.count, Invoice.count, CallAttempt.count ]

    expect do
      expect { load Rails.root.join("db/seeds.rb") }.to output(/DueCall demo data ready:/).to_stdout
    end.not_to have_enqueued_job

    expect([ User.count, Customer.count, Contact.count, Invoice.count, CallAttempt.count ]).to eq(counts)
    expect(records.map { |record| record.class.find(record.id).id }).to eq(record_ids)
    expect(user.customers.count).to eq(2)
    expect(user.customers.joins(:invoices).count).to eq(3)
    expect(acme_contact.reload).to have_attributes(
      phone_number: "+628123456789",
      time_zone: "Eastern Time (US & Canada)"
    )
    expect(northwind_contact.reload).to have_attributes(
      phone_number: "+628123456789",
      time_zone: "London"
    )
    expect(acme_contact.business_hours_start.strftime("%H:%M")).to eq("09:00")
    expect(acme_contact.business_hours_end.strftime("%H:%M")).to eq("17:00")
    expect(northwind_contact.business_hours_start.strftime("%H:%M")).to eq("09:00")
    expect(northwind_contact.business_hours_end.strftime("%H:%M")).to eq("17:00")
    expect(acme_invoice.reload).to have_attributes(
      amount_cents: 125_000,
      currency: "USD",
      status: "open",
      autonomous_follow_up_enabled: false
    )
    expect([ acme_invoice, autonomous_invoice, attention_invoice ]).to all(be_overdue)
    expect([ autonomous_invoice, attention_invoice ]).to all(
      have_attributes(status: "open", autonomous_follow_up_enabled: false)
    )
    expect(autonomous_invoice.call_attempts).to be_empty
    expect(disputed_attempt.reload).to have_attributes(
      status: "completed",
      outcome: "disputed",
      next_action: "human_followup",
      next_action_on: nil,
      parent_call_attempt_id: nil,
      provider_goal_run_id: nil,
      provider_call_id: nil
    )
  end

  it "migrates the legacy demo email while preserving an existing protected CALL-E attempt" do
    user = User.create!(email_address: "demo@duecall.local", password: "legacy-password")
    customer = user.customers.create!(name: "Acme Corporation")
    contact = customer.contacts.create!(
      name: "Kurnia",
      phone_number: "+628123456789",
      time_zone: "Eastern Time (US & Canada)"
    )
    invoice = customer.invoices.create!(
      number: "INV-DEMO-001",
      amount_cents: 125_000,
      due_on: Date.current - 14.days,
      status: :open
    )
    protected_attempt = invoice.call_attempts.create!(
      contact:,
      status: :completed,
      outcome: :payment_pending,
      next_action: :retry_call,
      next_action_on: Date.current,
      provider_goal_run_id: "rgrp_p3yzjb0qjl17"
    )
    protected_attributes = protected_attempt.attributes

    expect { load Rails.root.join("db/seeds.rb") }.to output.to_stdout

    expect(user.reload.email_address).to eq("demo@duecall.test")
    expect(protected_attempt.reload.attributes).to eq(protected_attributes)
  end

  it "rejects an invalid phone before modifying an existing demo contact" do
    expect { load Rails.root.join("db/seeds.rb") }.to output.to_stdout
    contact = Contact.find_by!(name: "Kurnia")
    original_phone = contact.phone_number
    ENV["DUECALL_DEMO_PHONE"] = "08123456789"

    expect do
      load Rails.root.join("db/seeds.rb")
    end.to raise_error(
      RuntimeError,
      "DUECALL_DEMO_PHONE must be a valid E.164 phone number, e.g. +628123456789"
    )

    expect(contact.reload.phone_number).to eq(original_phone)
  end

  it "uses the configured email and synchronizes the password of an existing demo user" do
    ENV["DUECALL_DEMO_EMAIL"] = "configured-demo@duecall.test"
    expect { load Rails.root.join("db/seeds.rb") }.to output.to_stdout
    user = User.find_by!(email_address: "configured-demo@duecall.test")
    user.update!(password: "preserved-password")
    ENV["DUECALL_DEMO_PASSWORD"] = "replacement-password"

    expect { load Rails.root.join("db/seeds.rb") }.to output.to_stdout

    expect(user.reload.authenticate("preserved-password")).to be(false)
    expect(user.authenticate("replacement-password")).to eq(user)
  end

  it "requires an explicit password when seeding the demo user in production" do
    user = User.create!(email_address: "demo@duecall.test", password: "existing-password")
    ENV.delete("DUECALL_DEMO_PASSWORD")
    allow(Rails.env).to receive(:production?).and_return(true)

    expect do
      load Rails.root.join("db/seeds.rb")
    end.to raise_error(
      RuntimeError,
      "DUECALL_DEMO_PASSWORD is required when seeding the demo user in production"
    )

    expect(user.reload.authenticate("existing-password")).to eq(user)
  end
end
