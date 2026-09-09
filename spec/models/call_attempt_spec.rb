require "rails_helper"

RSpec.describe CallAttempt, type: :model do
  let(:user) { User.create!(email_address: "owner@example.com", password: "password") }
  let(:customer) { user.customers.create!(name: "Acme") }
  let(:invoice) do
    customer.invoices.create!(number: "INV-001", amount_cents: 12_500, due_on: Date.current)
  end
  let(:contact) do
    customer.contacts.create!(name: "Rina", phone_number: "+628123456789")
  end

  it "requires an invoice" do
    call_attempt = described_class.new(contact: contact)

    expect(call_attempt).not_to be_valid
    expect(call_attempt.errors[:invoice]).to include("must exist")
  end

  it "requires a contact" do
    call_attempt = described_class.new(invoice: invoice)

    expect(call_attempt).not_to be_valid
    expect(call_attempt.errors[:contact]).to include("must exist")
  end

  it "rejects a contact belonging to a different customer" do
    other_customer = user.customers.create!(name: "Globex")
    other_contact = other_customer.contacts.create!(name: "Budi", phone_number: "+628111111111")
    call_attempt = described_class.new(invoice: invoice, contact: other_contact)

    expect(call_attempt).not_to be_valid
    expect(call_attempt.errors[:contact]).to include("must belong to the same customer as the invoice")
  end

  it "accepts a contact belonging to the invoice customer" do
    expect(described_class.new(invoice: invoice, contact: contact)).to be_valid
  end

  it "defaults to pending" do
    call_attempt = described_class.new(invoice: invoice, contact: contact)

    expect(call_attempt).to be_pending
    expect(call_attempt.raw_result).to eq({})
  end

  it "allows a blank outcome" do
    expect(described_class.new(invoice: invoice, contact: contact, outcome: nil)).to be_valid
  end

  it "supports status and outcome enums" do
    expect(described_class.statuses).to eq(
      "pending" => 0,
      "in_progress" => 1,
      "completed" => 2,
      "failed" => 3
    )
    expect(described_class.outcomes).to eq(
      "promised_to_pay" => 0,
      "already_paid" => 1,
      "invoice_not_received" => 2,
      "payment_pending" => 3,
      "missing_information" => 4,
      "disputed" => 5,
      "refused" => 6,
      "no_answer" => 7,
      "wrong_contact" => 8,
      "human_followup_required" => 9,
      "unknown" => 10
    )

    call_attempt = described_class.create!(invoice: invoice, contact: contact)

    call_attempt.update!(status: :in_progress, outcome: :promised_to_pay)

    expect(call_attempt).to be_in_progress
    expect(call_attempt).to be_promised_to_pay
  end

  it "is destroyed with its invoice" do
    call_attempt = described_class.create!(invoice: invoice, contact: contact)

    invoice.destroy!

    expect(described_class.exists?(call_attempt.id)).to be(false)
  end

  it "prevents deleting a contact with call attempts" do
    described_class.create!(invoice: invoice, contact: contact)

    expect(contact.destroy).to be(false)
    expect(contact.errors[:base]).to be_present
  end
end
