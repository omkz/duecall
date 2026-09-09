class DashboardController < ApplicationController
  def show
    owned_invoices = Invoice.where(customer: Current.user.customers)
    overdue_invoices = owned_invoices.overdue

    @customer_count = Current.user.customers.count
    @overdue_count = overdue_invoices.count
    @overdue_totals = overdue_invoices.group(:currency).sum(:amount_cents)
    @active_call_count = CallAttempt.active.where(invoice: owned_invoices).count
    @latest_call_attempts = latest_call_attempts(owned_invoices)
    @payment_promise_count = @latest_call_attempts.values.count do |call_attempt|
      call_attempt.promised_to_pay? && call_attempt.promise_to_pay_on.present? &&
        call_attempt.promise_to_pay_on >= Date.current
    end

    @action_queue = overdue_invoices.includes(:customer).to_a.sort_by do |invoice|
      call_attempt = @latest_call_attempts[invoice.id]
      [ action_priority(invoice, call_attempt), -((Date.current - invoice.due_on).to_i), invoice.id ]
    end

    @recent_call_attempts = CallAttempt
      .where(invoice: owned_invoices)
      .includes(:contact, invoice: :customer)
      .order(created_at: :desc, id: :desc)
      .limit(10)
  end

  private
    def latest_call_attempts(owned_invoices)
      CallAttempt
        .where(invoice: owned_invoices)
        .select("DISTINCT ON (call_attempts.invoice_id) call_attempts.*")
        .order(:invoice_id, created_at: :desc, id: :desc)
        .index_by(&:invoice_id)
    end

    def action_priority(invoice, call_attempt)
      return 3 if call_attempt.blank?
      return 6 if call_attempt.pending? || call_attempt.in_progress?
      return 0 if call_attempt.disputed? || call_attempt.human_followup_required?
      return 1 if call_attempt.invoice_not_received? || call_attempt.missing_information? || call_attempt.wrong_contact?
      return 2 if call_attempt.already_paid? || call_attempt.unknown? || missed_promise?(invoice, call_attempt)
      return 4 if call_attempt.no_answer? || call_attempt.refused?

      5
    end

    def missed_promise?(invoice, call_attempt)
      invoice.open? && call_attempt.promised_to_pay? &&
        call_attempt.promise_to_pay_on.present? && call_attempt.promise_to_pay_on < Date.current
    end
end
