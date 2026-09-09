class CustomersController < ApplicationController
  before_action :set_customer, only: %i[ show edit update destroy ]

  def index
    @customers = Current.user.customers.order(:name)
  end

  def show
    @contacts = @customer.contacts.order(:name)
    @invoices = @customer.invoices.order(:due_on, :number)
  end

  def new
    @customer = Current.user.customers.build
  end

  def create
    @customer = Current.user.customers.build(customer_params)

    if @customer.save
      redirect_to @customer, notice: "Customer was added."
    else
      render :new, status: :unprocessable_entity
    end
  end

  def edit
  end

  def update
    if @customer.update(customer_params)
      redirect_to @customer, notice: "Customer was updated."
    else
      render :edit, status: :unprocessable_entity
    end
  end

  def destroy
    @customer.destroy!
    redirect_to customers_path, notice: "Customer was deleted.", status: :see_other
  end

  private
    def set_customer
      @customer = Current.user.customers.find(params[:id])
    end

    def customer_params
      params.require(:customer).permit(:name, :email, :external_id)
    end
end
