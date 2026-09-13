class CallAttempt::ExecuteFollowUpJob < ApplicationJob
  def self.schedule(call_attempt, at:)
    set(wait_until: at).perform_later(call_attempt)
  end

  def perform(call_attempt)
    call_attempt.execute_follow_up!
  end
end
