class InvoicesController < ApplicationController
  before_action :set_customer, only: %i[ new create ]
  before_action :set_invoice, only: %i[ show edit update destroy ]

  def index
    @invoices = Invoice.where(customer: Current.user.customers)
      .includes(:customer)
      .order(:due_on, :number)
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

  private
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
