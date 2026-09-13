module CallAttempt::AutonomousFollowUp
  extend ActiveSupport::Concern

  def schedule_follow_up_execution!(now: Time.current)
    execution_at = nil

    with_lock do
      next unless completed? && retry_call? && next_action_on.present?

      invoice.reload
      contact.reload
      next unless invoice.autonomous_follow_up_enabled?

      execution_at = autonomous_execution_time(now:)
    end

    CallAttempt::ExecuteFollowUpJob.schedule(self, at: execution_at) if execution_at
    self
  end

  def execute_follow_up!(now: Time.current)
    result = nil

    with_lock do
      next unless completed? && retry_call?

      invoice.reload
      contact.reload
      invoice.with_lock do
        result = autonomous_execution_result(now:)
      end
    end

    case result
    when Time, ActiveSupport::TimeWithZone
      CallAttempt::ExecuteFollowUpJob.schedule(self, at: result)
    when CallAttempt
      result.run_calle_goal!
    end

    self
  rescue ActiveRecord::RecordNotUnique
    self
  end

  private
    def autonomous_execution_time(now:)
      if invoice.paid? || invoice.cancelled?
        stop_autonomous_follow_up!
      elsif contact.configured_time_zone.blank?
        require_human_follow_up!
      elsif !invoice_overdue_in_contact_time_zone?(now:)
        require_human_follow_up!
      elsif submitted_invoice_call_attempts_count >= Invoice::AUTOMATIC_CALL_LIMIT
        require_human_follow_up!
      elsif follow_up_call_attempt.present?
        nil
      else
        contact.next_business_opening(on_or_after: next_action_on, now:)
      end
    end

    def autonomous_execution_result(now:)
      return stop_autonomous_follow_up! if invoice.paid? || invoice.cancelled?
      return unless invoice.autonomous_follow_up_enabled?
      return require_human_follow_up! if next_action_on.blank? || contact.configured_time_zone.blank?
      return require_human_follow_up! unless invoice_overdue_in_contact_time_zone?(now:)
      return require_human_follow_up! if submitted_invoice_call_attempts_count >= Invoice::AUTOMATIC_CALL_LIMIT
      return if follow_up_call_attempt.present?
      return require_human_follow_up! if automatic_submission_pending?

      local_today = now.in_time_zone(contact.configured_time_zone).to_date
      return contact.next_business_opening(on_or_after: next_action_on, now:) if next_action_on > local_today

      execution_at = contact.next_business_opening(on_or_after: next_action_on, now:)
      return execution_at if execution_at > now

      invoice.call_attempts.create!(contact:, parent_call_attempt: self)
    end

    def invoice_overdue_in_contact_time_zone?(now:)
      invoice.open? && invoice.due_on < now.in_time_zone(contact.configured_time_zone).to_date
    end

    def submitted_invoice_call_attempts_count
      invoice.call_attempts.where.not(provider_goal_run_id: nil).count
    end

    def automatic_submission_pending?
      invoice.call_attempts.where.not(parent_call_attempt_id: nil)
        .where(provider_goal_run_id: nil, status: CallAttempt.statuses[:pending])
        .exists?
    end

    def stop_autonomous_follow_up!
      update!(next_action: :stop, next_action_on: nil)
      nil
    end

    def require_human_follow_up!
      update!(next_action: :human_followup, next_action_on: nil)
      nil
    end
end
