require "rails_helper"

RSpec.describe CallAttemptsHelper, type: :helper do
  it "maps provider transcript speakers to user-facing labels" do
    turns = helper.transcript_turns(<<~TRANSCRIPT)
      Bot: Hello from the bot.
      Agent: Hello from the agent.
      User: Hello from the user.
      Recipient: Hello from the recipient.
      System note without a known prefix
    TRANSCRIPT

    expect(turns.pluck(:label)).to eq([ "DueCall", "DueCall", "Customer", "Customer", "Transcript" ])
    expect(turns.last[:text]).to eq("System note without a known prefix")
  end

  it "derives a readable duration without persisting it" do
    call_attempt = CallAttempt.new(
      started_at: Time.zone.parse("2026-09-10 10:00:00"),
      completed_at: Time.zone.parse("2026-09-10 10:05:12")
    )

    expect(helper.call_attempt_duration(call_attempt)).to eq("5m 12s")
  end
end
