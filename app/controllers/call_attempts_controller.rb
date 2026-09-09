class CallAttemptsController < ApplicationController
  before_action :set_call_attempt

  def show
    @invoice = @call_attempt.invoice
    @customer = @invoice.customer
    @contact = @call_attempt.contact
  end

  private
    def set_call_attempt
      owned_invoices = Invoice.where(customer: Current.user.customers)
      @call_attempt = CallAttempt.where(invoice: owned_invoices).find(params[:id])
    end
end
