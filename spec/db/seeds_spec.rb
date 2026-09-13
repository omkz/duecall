require "rails_helper"

RSpec.describe "db/seeds.rb" do
  around do |example|
    original_phone = ENV["DUECALL_DEMO_PHONE"]
    original_password = ENV["DUECALL_DEMO_PASSWORD"]
    ENV["DUECALL_DEMO_PHONE"] = "+628123456789"
    ENV["DUECALL_DEMO_PASSWORD"] = "demo-test-password"
    example.run
  ensure
    original_phone ? ENV["DUECALL_DEMO_PHONE"] = original_phone : ENV.delete("DUECALL_DEMO_PHONE")
    original_password ? ENV["DUECALL_DEMO_PASSWORD"] = original_password : ENV.delete("DUECALL_DEMO_PASSWORD")
  end

  it "creates the demo dataset idempotently without contacting CALL-E" do
    expect(Calle::Client).not_to receive(:new)
    call_attempt_count = CallAttempt.count

    expect { load Rails.root.join("db/seeds.rb") }.to output(/DueCall demo data ready:/).to_stdout

    user = User.find_by!(email_address: "demo@duecall.local")
    customer = user.customers.find_by!(name: "Acme Corporation")
    contact = customer.contacts.find_by!(name: "Kurnia")
    invoice = customer.invoices.find_by!(number: "INV-DEMO-001")
    record_ids = [ user.id, customer.id, contact.id, invoice.id ]
    counts = [ User.count, Customer.count, Contact.count, Invoice.count ]

    expect { load Rails.root.join("db/seeds.rb") }.to output(/DueCall demo data ready:/).to_stdout

    expect([ User.count, Customer.count, Contact.count, Invoice.count ]).to eq(counts)
    expect(
      [
        User.find_by!(email_address: "demo@duecall.local").id,
        user.customers.find_by!(name: "Acme Corporation").id,
        customer.contacts.find_by!(name: "Kurnia").id,
        customer.invoices.find_by!(number: "INV-DEMO-001").id
      ]
    ).to eq(record_ids)
    expect(contact.reload).to have_attributes(
      phone_number: "+628123456789",
      time_zone: "Eastern Time (US & Canada)"
    )
    expect(invoice.reload).to have_attributes(
      amount_cents: 125_000,
      currency: "USD",
      due_on: Date.new(2026, 9, 1),
      status: "open",
      autonomous_follow_up_enabled: false
    )
    expect(CallAttempt.count).to eq(call_attempt_count)
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

  it "does not reset the password of an existing demo user" do
    expect { load Rails.root.join("db/seeds.rb") }.to output.to_stdout
    user = User.find_by!(email_address: "demo@duecall.local")
    user.update!(password: "preserved-password")
    ENV["DUECALL_DEMO_PASSWORD"] = "replacement-password"

    expect { load Rails.root.join("db/seeds.rb") }.to output.to_stdout

    expect(user.reload.authenticate("preserved-password")).to eq(user)
    expect(user.authenticate("replacement-password")).to be(false)
  end

  it "requires an explicit password when creating the demo user in production" do
    User.find_by(email_address: "demo@duecall.local")&.destroy!
    ENV.delete("DUECALL_DEMO_PASSWORD")
    allow(Rails.env).to receive(:production?).and_return(true)

    expect do
      load Rails.root.join("db/seeds.rb")
    end.to raise_error(
      RuntimeError,
      "DUECALL_DEMO_PASSWORD is required when creating the demo user in production"
    )

    expect(User.exists?(email_address: "demo@duecall.local")).to be(false)
  end
end
