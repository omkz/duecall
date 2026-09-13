class CallAttempt::SyncCalleGoalJob < ApplicationJob
  POLL_INTERVAL = 10.seconds
  MAX_POLLS = 18

  def self.schedule(call_attempt, polls_remaining: MAX_POLLS)
    set(wait: POLL_INTERVAL).perform_later(call_attempt, polls_remaining:)
  end

  def perform(call_attempt, polls_remaining: MAX_POLLS)
    return unless call_attempt.reload.in_progress?

    call_attempt.sync_calle_goal!

    if call_attempt.reload.in_progress? && polls_remaining > 1
      self.class.schedule(call_attempt, polls_remaining: polls_remaining - 1)
    end
  rescue CallAttempt::InvalidTransitionError
    nil
  end
end
