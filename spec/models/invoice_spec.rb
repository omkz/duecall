require "rails_helper"

RSpec.describe Invoice, type: :model do
  let(:user) { User.create!(email_address: "owner@example.com", password: "password") }
  let(:customer) { user.customers.create!(name: "Acme") }

  def build_invoice(attributes = {})
    described_class.new({
      customer: customer,
      number: "INV-001",
      amount_cents: 12_500,
      due_on: Date.current + 7.days
    }.merge(attributes))
  end

  it "requires an invoice number" do
    invoice = build_invoice(number: "")

    expect(invoice).not_to be_valid
    expect(invoice.errors[:number]).to include("can't be blank")
  end

  it "requires a positive amount in cents" do
    invoice = build_invoice(amount_cents: 0)

    expect(invoice).not_to be_valid
    expect(invoice.errors[:amount_cents]).to include("must be greater than 0")
  end

  it "requires a due date" do
    invoice = build_invoice(due_on: nil)

    expect(invoice).not_to be_valid
    expect(invoice.errors[:due_on]).to include("can't be blank")
  end

  it "requires a currency" do
    invoice = build_invoice(currency: "")

    expect(invoice).not_to be_valid
    expect(invoice.errors[:currency]).to include("can't be blank")
  end

  it "belongs to a customer" do
    invoice = build_invoice(customer: nil)

    expect(invoice).not_to be_valid
    expect(invoice.errors[:customer]).to include("must exist")
  end

  it "defaults to USD and open" do
    invoice = build_invoice

    expect(invoice.currency).to eq("USD")
    expect(invoice).to be_open
  end

  it "requires invoice numbers to be unique per customer" do
    customer.invoices.create!(number: "INV-001", amount_cents: 12_500, due_on: Date.current)

    expect(build_invoice).not_to be_valid
  end

  it "allows the same invoice number for different customers" do
    customer.invoices.create!(number: "INV-001", amount_cents: 12_500, due_on: Date.current)
    another_customer = user.customers.create!(name: "Beta")

    expect(build_invoice(customer: another_customer)).to be_valid
  end

  it "detects an overdue open invoice" do
    invoice = customer.invoices.create!(
      number: "INV-LATE",
      amount_cents: 12_500,
      due_on: Date.current - 1.day,
      status: :open
    )

    expect(invoice).to be_overdue
    expect(described_class.overdue).to include(invoice)
  end

  it "does not consider a paid invoice overdue" do
    invoice = build_invoice(due_on: Date.current - 1.day, status: :paid)

    expect(invoice).not_to be_overdue
  end

  it "normalizes currency to uppercase" do
    invoice = build_invoice(currency: " idr ")

    expect(invoice.currency).to eq("IDR")
  end
end
