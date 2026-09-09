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
end
