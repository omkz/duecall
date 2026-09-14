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

  it "defaults business hours to 09:00–17:00" do
    contact = build_contact
    contact.save!

    expect(contact.business_hours_start.strftime("%H:%M")).to eq("09:00")
    expect(contact.business_hours_end.strftime("%H:%M")).to eq("17:00")
  end

  it "requires both business-hours values" do
    contact = build_contact(business_hours_start: nil, business_hours_end: nil)

    expect(contact).not_to be_valid
    expect(contact.errors[:business_hours_start]).to include("can't be blank")
    expect(contact.errors[:business_hours_end]).to include("can't be blank")
  end

  it "requires business hours to end after they start" do
    reversed = build_contact(business_hours_start: "17:00", business_hours_end: "09:00")
    equal = build_contact(business_hours_start: "09:00", business_hours_end: "09:00")

    expect(reversed).not_to be_valid
    expect(reversed.errors[:business_hours_end]).to include("must be after business hours start")
    expect(equal).not_to be_valid
    expect(equal.errors[:business_hours_end]).to include("must be after business hours start")
  end

  it "allows a blank preferred call time" do
    expect(build_contact(preferred_call_time: nil)).to be_valid
  end

  it "rejects a preferred call time before opening" do
    contact = build_contact(preferred_call_time: "08:59")

    expect(contact).not_to be_valid
    expect(contact.errors[:preferred_call_time]).to include(
      "must be at or after business hours start and before business hours end"
    )
  end

  it "rejects a preferred call time at or after closing" do
    at_closing = build_contact(preferred_call_time: "17:00")
    after_closing = build_contact(preferred_call_time: "18:00")

    expect(at_closing).not_to be_valid
    expect(at_closing.errors[:preferred_call_time]).to include(
      "must be at or after business hours start and before business hours end"
    )
    expect(after_closing).not_to be_valid
    expect(after_closing.errors[:preferred_call_time]).to include(
      "must be at or after business hours start and before business hours end"
    )
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
    before_opening = zone.local(2026, 9, 14, 8, 59)

    expect(contact.next_business_opening(on_or_after: Date.new(2026, 9, 14), now: before_opening))
      .to eq(zone.local(2026, 9, 14, 9))
  end

  it "is eligible immediately within business hours when preferred call time is blank" do
    contact = build_contact(time_zone: "Asia/Jakarta")
    zone = contact.configured_time_zone
    during_business_hours = zone.local(2026, 9, 14, 13, 15)

    expect(contact.next_business_opening(
      on_or_after: Date.new(2026, 9, 14), now: during_business_hours
    )).to eq(during_business_hours)
  end

  it "uses the next business day opening at closing time" do
    contact = build_contact(time_zone: "Asia/Jakarta")
    zone = contact.configured_time_zone
    at_closing = zone.local(2026, 9, 14, 17)

    expect(contact.next_business_opening(on_or_after: Date.new(2026, 9, 14), now: at_closing))
      .to eq(zone.local(2026, 9, 15, 9))
  end

  it "uses the next business day opening after closing time" do
    contact = build_contact(time_zone: "Asia/Jakarta")
    zone = contact.configured_time_zone
    after_closing = zone.local(2026, 9, 14, 19)

    expect(contact.next_business_opening(on_or_after: Date.new(2026, 9, 14), now: after_closing))
      .to eq(zone.local(2026, 9, 15, 9))
  end

  it "uses custom business hours" do
    contact = build_contact(
      time_zone: "Asia/Jakarta",
      business_hours_start: "08:30",
      business_hours_end: "16:30"
    )
    zone = contact.configured_time_zone

    expect(contact.next_business_opening(
      on_or_after: Date.new(2026, 9, 14), now: zone.local(2026, 9, 14, 8)
    )).to eq(zone.local(2026, 9, 14, 8, 30))
    expect(contact.next_business_opening(
      on_or_after: Date.new(2026, 9, 14), now: zone.local(2026, 9, 14, 16, 29)
    )).to eq(zone.local(2026, 9, 14, 16, 29))
    expect(contact.next_business_opening(
      on_or_after: Date.new(2026, 9, 14), now: zone.local(2026, 9, 14, 16, 30)
    )).to eq(zone.local(2026, 9, 15, 8, 30))
  end

  it "interprets business hours in the contact's time zone" do
    contact = build_contact(time_zone: "America/New_York")
    zone = contact.configured_time_zone
    now = Time.utc(2026, 9, 14, 12, 30)

    expect(contact.next_business_opening(on_or_after: Date.new(2026, 9, 14), now:))
      .to eq(zone.local(2026, 9, 14, 9))
  end

  it "schedules at the preferred time when it is still in the future" do
    contact = build_contact(time_zone: "Asia/Jakarta", preferred_call_time: "14:00")
    zone = contact.configured_time_zone

    expect(contact.next_business_opening(
      on_or_after: Date.new(2026, 9, 14), now: zone.local(2026, 9, 14, 8)
    )).to eq(zone.local(2026, 9, 14, 14))
    expect(contact.next_business_opening(
      on_or_after: Date.new(2026, 9, 14), now: zone.local(2026, 9, 14, 13, 59)
    )).to eq(zone.local(2026, 9, 14, 14))
  end

  it "uses the next weekday when the preferred time is reached or has passed" do
    contact = build_contact(time_zone: "Asia/Jakarta", preferred_call_time: "14:00")
    zone = contact.configured_time_zone

    expect(contact.next_business_opening(
      on_or_after: Date.new(2026, 9, 14), now: zone.local(2026, 9, 14, 14)
    )).to eq(zone.local(2026, 9, 15, 14))
    expect(contact.next_business_opening(
      on_or_after: Date.new(2026, 9, 14), now: zone.local(2026, 9, 14, 15)
    )).to eq(zone.local(2026, 9, 15, 14))
  end

  it "uses the next weekday preferred time after allowed closing" do
    contact = build_contact(time_zone: "Asia/Jakarta", preferred_call_time: "14:00")
    zone = contact.configured_time_zone

    expect(contact.next_business_opening(
      on_or_after: Date.new(2026, 9, 14), now: zone.local(2026, 9, 14, 18)
    )).to eq(zone.local(2026, 9, 15, 14))
  end

  it "rolls a Friday after the preferred time to Monday" do
    contact = build_contact(time_zone: "Asia/Jakarta", preferred_call_time: "14:00")
    zone = contact.configured_time_zone

    expect(contact.next_business_opening(
      on_or_after: Date.new(2026, 9, 18), now: zone.local(2026, 9, 18, 15)
    )).to eq(zone.local(2026, 9, 21, 14))
  end

  it "rolls a weekend to Monday at the preferred time" do
    contact = build_contact(time_zone: "Asia/Jakarta", preferred_call_time: "14:00")
    zone = contact.configured_time_zone

    expect(contact.next_business_opening(
      on_or_after: Date.new(2026, 9, 19), now: zone.local(2026, 9, 19, 10)
    )).to eq(zone.local(2026, 9, 21, 14))
  end

  it "uses a preferred time within custom allowed hours" do
    contact = build_contact(
      time_zone: "Asia/Jakarta",
      business_hours_start: "08:30",
      business_hours_end: "16:30",
      preferred_call_time: "16:00"
    )
    zone = contact.configured_time_zone

    expect(contact).to be_valid
    expect(contact.next_business_opening(
      on_or_after: Date.new(2026, 9, 14), now: zone.local(2026, 9, 14, 15)
    )).to eq(zone.local(2026, 9, 14, 16))
  end

  it "interprets the preferred call time in the contact's time zone" do
    contact = build_contact(time_zone: "America/New_York", preferred_call_time: "14:00")
    zone = contact.configured_time_zone
    now = Time.utc(2026, 9, 14, 17)

    expect(contact.next_business_opening(on_or_after: Date.new(2026, 9, 14), now:))
      .to eq(zone.local(2026, 9, 14, 14))
  end
end
