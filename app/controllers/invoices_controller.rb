class InvoicesController < ApplicationController
  before_action :set_customer, only: %i[ new create ]
  before_action :set_invoice, only: %i[ show edit update destroy autonomous_follow_up ]

  def index
    @invoices = visible_invoices.includes(:customer).order(:due_on, :number)
    @dashboard_metrics = dashboard_metrics
    @recent_call_attempts = CallAttempt.where(invoice: visible_invoices)
      .includes(:contact, invoice: :customer)
      .order(created_at: :desc)
      .limit(5)
  end

  def show
    @call_attempts = @invoice.call_attempts.includes(:contact).order(created_at: :desc)
    @contacts = @customer.contacts.order(:name)
  end

  def new
    @invoice = @customer.invoices.build
  end

  def create
    @invoice = @customer.invoices.build(invoice_params)

    if @invoice.save
      redirect_to @invoice, notice: "Invoice was added."
    else
      render :new, status: :unprocessable_entity
    end
  end

  def edit
  end

  def update
    if @invoice.update(invoice_params)
      redirect_to @invoice, notice: "Invoice was updated."
    else
      render :edit, status: :unprocessable_entity
    end
  end

  def destroy
    customer = @invoice.customer
    @invoice.destroy!
    redirect_to customer, notice: "Invoice was deleted.", status: :see_other
  end

  def autonomous_follow_up
    @invoice.configure_autonomous_follow_up!(enabled: params[:enabled])

    redirect_to @invoice,
      notice: "Autonomous follow-up was #{@invoice.autonomous_follow_up_enabled? ? "enabled" : "disabled"}.",
      status: :see_other
  end

  private
    def visible_invoices
      Invoice.where(customer: Current.user.customers)
    end

    def dashboard_metrics
      call_attempts = CallAttempt.where(invoice: visible_invoices)

      {
        overdue_invoices: visible_invoices.overdue.count,
        calls_awaiting_result: call_attempts.in_progress.count,
        autonomous_retries: call_attempts.completed.retry_call
          .where.not(next_action_on: nil)
          .joins(:invoice)
          .where(invoices: { autonomous_follow_up_enabled: true })
          .count,
        promises_to_pay: call_attempts.completed.promised_to_pay.count,
        human_attention_required: call_attempts.human_followup.count
      }
    end

    def set_customer
      @customer = Current.user.customers.find(params[:customer_id])
    end

    def set_invoice
      @invoice = Invoice.where(customer: Current.user.customers).find(params[:id])
      @customer = @invoice.customer
    end

    def invoice_params
      params.require(:invoice).permit(
        :number,
        :amount_cents,
        :currency,
        :issued_on,
        :due_on,
        :status,
        :external_id
      )
    end
end
