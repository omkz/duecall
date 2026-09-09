require "rails_helper"

RSpec.describe User, type: :model do
  it "destroys associated customers" do
    user = described_class.create!(email_address: "owner@example.com", password: "password")
    customer = user.customers.create!(name: "Acme")

    user.destroy!

    expect(Customer.exists?(customer.id)).to be(false)
  end
end
