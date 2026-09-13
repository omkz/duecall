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

  it "supports status, outcome, and next action enums" do
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
    expect(described_class.next_actions).to eq(
      "stop" => 0,
      "retry_call" => 1,
      "human_followup" => 2
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

  describe "real-time broadcasts" do
    it "broadcasts a replace of its own details region to its own stream when updated" do
      call_attempt = described_class.create!(invoice: invoice, contact: contact, status: :in_progress)
      stream_name = call_attempt.to_gid_param

      expect do
        call_attempt.update!(status: :completed, outcome: :promised_to_pay, completed_at: Time.current)
      end.to have_broadcasted_to(stream_name)

      payload = ActiveSupport::JSON.decode(ActionCable.server.pubsub.broadcasts(stream_name).last)
      expect(payload).to include(
        "<turbo-stream action=\"replace\"",
        ActionView::RecordIdentifier.dom_id(call_attempt, :details),
        "Promised to pay"
      )
    end

    it "does not broadcast to another call attempt's stream" do
      call_attempt = described_class.create!(invoice: invoice, contact: contact, status: :in_progress)
      other_call_attempt = described_class.create!(invoice: invoice, contact: contact, status: :in_progress)

      expect do
        call_attempt.update!(status: :completed, completed_at: Time.current)
      end.not_to have_broadcasted_to(other_call_attempt.to_gid_param)
    end

    it "does not broadcast on create, only on updates to a persisted record" do
      call_attempt = described_class.create!(invoice: invoice, contact: contact, status: :pending)

      expect(ActionCable.server.pubsub.broadcasts(call_attempt.to_gid_param)).to be_empty
    end

    it "never includes the raw provider payload in a broadcast" do
      call_attempt = described_class.create!(invoice: invoice, contact: contact, status: :in_progress)
      stream_name = call_attempt.to_gid_param

      call_attempt.update!(
        status: :failed,
        raw_result: { "submission_error" => { "error_message" => "secret provider diagnostic" } }
      )

      payload = ActiveSupport::JSON.decode(ActionCable.server.pubsub.broadcasts(stream_name).last)
      expect(payload).not_to include("secret provider diagnostic", "submission_error")
    end
  end
end
