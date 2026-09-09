require "rails_helper"

RSpec.describe Customer, type: :model do
  let(:user) { User.create!(email_address: "owner@example.com", password: "password") }

  it "requires a name" do
    customer = described_class.new(user: user, name: "")

    expect(customer).not_to be_valid
    expect(customer.errors[:name]).to include("can't be blank")
  end

  it "belongs to a user" do
    customer = described_class.new(name: "Acme")

    expect(customer).not_to be_valid
    expect(customer.errors[:user]).to include("must exist")
  end

  it "allows a blank email" do
    customer = described_class.new(user: user, name: "Acme", email: "")

    expect(customer).to be_valid
  end

  it "rejects an invalid email" do
    customer = described_class.new(user: user, name: "Acme", email: "not-an-email")

    expect(customer).not_to be_valid
    expect(customer.errors[:email]).to include("is invalid")
  end

  it "destroys associated contacts" do
    customer = user.customers.create!(name: "Acme")
    contact = customer.contacts.create!(name: "Rina", phone_number: "+628123456789")

    customer.destroy!

    expect(Contact.exists?(contact.id)).to be(false)
  end

  it "destroys associated invoices" do
    customer = user.customers.create!(name: "Acme")
    invoice = customer.invoices.create!(number: "INV-001", amount_cents: 12_500, due_on: Date.current)

    customer.destroy!

    expect(Invoice.exists?(invoice.id)).to be(false)
  end

  it "destroys invoices and contacts when call history exists" do
    customer = user.customers.create!(name: "Acme")
    contact = customer.contacts.create!(name: "Rina", phone_number: "+628123456789")
    invoice = customer.invoices.create!(number: "INV-001", amount_cents: 12_500, due_on: Date.current)
    call_attempt = invoice.call_attempts.create!(contact: contact)

    expect { customer.destroy! }.to change(described_class, :count).by(-1)

    expect(Invoice.exists?(invoice.id)).to be(false)
    expect(CallAttempt.exists?(call_attempt.id)).to be(false)
    expect(Contact.exists?(contact.id)).to be(false)
  end
end
