require "rails_helper"

RSpec.describe WebhookEvent, type: :model do
  it "requires a provider and event id" do
    event = described_class.new

    expect(event).not_to be_valid
    expect(event.errors[:provider]).to include("can't be blank")
    expect(event.errors[:event_id]).to include("can't be blank")
  end

  it "defaults payload to an empty object" do
    event = described_class.new(provider: "calle", event_id: "evt_123")

    expect(event.payload).to eq({})
  end

  it "enforces provider and event id uniqueness in the database" do
    described_class.create!(provider: "calle", event_id: "evt_123")

    expect do
      described_class.create!(provider: "calle", event_id: "evt_123")
    end.to raise_error(ActiveRecord::RecordNotUnique)
  end
end
