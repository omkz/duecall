module DashboardHelper
  def recommended_next_action(invoice, call_attempt)
    return "Start follow-up call" if call_attempt.blank?
    return "Call in progress" if call_attempt.pending? || call_attempt.in_progress?

    case call_attempt.outcome
    when "promised_to_pay"
      if missed_payment_promise?(invoice, call_attempt)
        "Payment promise overdue — follow up"
      elsif call_attempt.promise_to_pay_on.present?
        "Wait for promised payment"
      else
        "Review call"
      end
    when "already_paid" then "Verify payment"
    when "invoice_not_received" then "Resend invoice"
    when "payment_pending" then "Monitor payment"
    when "missing_information" then "Resolve missing information"
    when "disputed" then "Review dispute"
    when "refused", "human_followup_required" then "Human follow-up"
    when "no_answer" then "Retry call"
    when "wrong_contact" then "Update contact"
    else "Review call"
    end
  end

  def missed_payment_promise?(invoice, call_attempt)
    invoice.open? && call_attempt&.promised_to_pay? &&
      call_attempt.promise_to_pay_on.present? && call_attempt.promise_to_pay_on < Date.current
  end
end
