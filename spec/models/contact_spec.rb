require "rails_helper"

RSpec.describe Contact, type: :model do
  let(:user) { User.create!(email_address: "owner@example.com", password: "password") }
  let(:customer) { user.customers.create!(name: "Acme") }

  def build_contact(attributes = {})
    described_class.new({ customer: customer, name: "Rina", phone_number: "+628123456789" }.merge(attributes))
  end

  it "requires a name" do
    contact = build_contact(name: "")

    expect(contact).not_to be_valid
    expect(contact.errors[:name]).to include("can't be blank")
  end

  it "requires a phone number" do
    contact = build_contact(phone_number: "")

    expect(contact).not_to be_valid
    expect(contact.errors[:phone_number]).to include("can't be blank")
  end

  it "accepts a valid E.164 phone number" do
    expect(build_contact(phone_number: "+628123456789")).to be_valid
  end

  it "rejects an invalid phone number" do
    contact = build_contact(phone_number: "0812 3456 789")

    expect(contact).not_to be_valid
    expect(contact.errors[:phone_number]).to include("is invalid")
  end

  it "allows a blank email" do
    expect(build_contact(email: "")).to be_valid
  end

  it "rejects an invalid email" do
    contact = build_contact(email: "not-an-email")

    expect(contact).not_to be_valid
    expect(contact.errors[:email]).to include("is invalid")
  end

  it "belongs to a customer" do
    contact = build_contact(customer: nil)

    expect(contact).not_to be_valid
    expect(contact.errors[:customer]).to include("must exist")
  end
end
