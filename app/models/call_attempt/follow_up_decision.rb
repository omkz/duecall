module CallAttempt::FollowUpDecision
  extend ActiveSupport::Concern

  NO_ANSWER_MAX_ATTEMPTS = 3

  def decide_next_action!
    return self unless completed? && outcome.present?

    update!(follow_up_decision_attributes)
    schedule_follow_up_execution! if retry_call?
    self
  end

  private
    def follow_up_decision_attributes
      case outcome
      when "already_paid"
        { next_action: :stop, next_action_on: nil }
      when "promised_to_pay"
        promised_to_pay_decision
      when "payment_pending"
        { next_action: :retry_call, next_action_on: Date.current + 2.days }
      when "no_answer"
        no_answer_decision
      else
        { next_action: :human_followup, next_action_on: nil }
      end
    end

    def promised_to_pay_decision
      if promise_to_pay_on.present?
        { next_action: :retry_call, next_action_on: promise_to_pay_on + 1.day }
      else
        { next_action: :human_followup, next_action_on: nil }
      end
    end

    def no_answer_decision
      if terminal_invoice_call_attempts_count < NO_ANSWER_MAX_ATTEMPTS
        { next_action: :retry_call, next_action_on: Date.current + 1.day }
      else
        { next_action: :human_followup, next_action_on: nil }
      end
    end

    def terminal_invoice_call_attempts_count
      invoice.call_attempts.where(status: %i[ completed failed ]).count
    end
end
