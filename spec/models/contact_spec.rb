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

  it "accepts a recognized time zone" do
    expect(build_contact(time_zone: "Asia/Jakarta")).to be_valid
  end

  it "rejects an unrecognized time zone" do
    contact = build_contact(time_zone: "Moon/Sea_of_Tranquility")

    expect(contact).not_to be_valid
    expect(contact.errors[:time_zone]).to include("is not recognized")
  end

  it "moves a weekend opening to Monday at 09:00 local time" do
    contact = build_contact(time_zone: "Asia/Jakarta")
    zone = contact.configured_time_zone
    saturday = zone.local(2026, 9, 12, 11)

    expect(contact.next_business_opening(on_or_after: Date.new(2026, 9, 12), now: saturday))
      .to eq(zone.local(2026, 9, 14, 9))
  end

  it "uses 09:00 local time when execution is due before business hours" do
    contact = build_contact(time_zone: "Asia/Jakarta")
    zone = contact.configured_time_zone
    before_opening = zone.local(2026, 9, 14, 8)

    expect(contact.next_business_opening(on_or_after: Date.new(2026, 9, 14), now: before_opening))
      .to eq(zone.local(2026, 9, 14, 9))
  end

  it "uses the next business day at 09:00 after business hours" do
    contact = build_contact(time_zone: "Asia/Jakarta")
    zone = contact.configured_time_zone
    after_closing = zone.local(2026, 9, 14, 17)

    expect(contact.next_business_opening(on_or_after: Date.new(2026, 9, 14), now: after_closing))
      .to eq(zone.local(2026, 9, 15, 9))
  end
end
