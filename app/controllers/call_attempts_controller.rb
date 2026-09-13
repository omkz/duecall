class CallAttemptsController < ApplicationController
  before_action :set_call_attempt, only: %i[ show run ]

  def create
    invoice = Invoice.where(customer: Current.user.customers).find(params[:invoice_id])
    unless invoice.overdue?
      redirect_to invoice,
        alert: "Calls can only be prepared for overdue open invoices.",
        status: :see_other
      return
    end

    contact = invoice.customer.contacts.find(params.require(:contact_id))
    call_attempt = invoice.call_attempts.create!(contact:, status: :pending)

    redirect_to call_attempt,
      notice: "Call prepared. Review the details before placing the call.",
      status: :see_other
  end

  def show
    @invoice = @call_attempt.invoice
    @customer = @invoice.customer
    @contact = @call_attempt.contact
  end

  def run
    unless @call_attempt.pending?
      redirect_to @call_attempt, alert: "Only pending calls can be submitted.", status: :see_other
      return
    end

    @call_attempt.run_calle_goal!

    if @call_attempt.in_progress?
      redirect_to @call_attempt, notice: "CALL-E call was submitted.", status: :see_other
    else
      redirect_to @call_attempt,
        alert: "CALL-E call could not be submitted. Review the configuration and prepare a new call.",
        status: :see_other
    end
  end

  private
    def set_call_attempt
      owned_invoices = Invoice.where(customer: Current.user.customers)
      @call_attempt = CallAttempt.where(invoice: owned_invoices).find(params[:id])
    end
end
