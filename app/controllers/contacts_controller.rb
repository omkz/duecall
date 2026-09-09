class ContactsController < ApplicationController
  before_action :set_customer, only: %i[ new create ]
  before_action :set_contact, only: %i[ show edit update destroy ]

  def show
  end

  def new
    @contact = @customer.contacts.build
  end

  def create
    @contact = @customer.contacts.build(contact_params)

    if @contact.save
      redirect_to @contact, notice: "Contact was added."
    else
      render :new, status: :unprocessable_entity
    end
  end

  def edit
  end

  def update
    if @contact.update(contact_params)
      redirect_to @contact, notice: "Contact was updated."
    else
      render :edit, status: :unprocessable_entity
    end
  end

  def destroy
    customer = @contact.customer
    @contact.destroy!
    redirect_to customer, notice: "Contact was deleted.", status: :see_other
  end

  private
    def set_customer
      @customer = Current.user.customers.find(params[:customer_id])
    end

    def set_contact
      @contact = Contact.where(customer: Current.user.customers).find(params[:id])
      @customer = @contact.customer
    end

    def contact_params
      params.require(:contact).permit(:name, :phone_number, :email, :role)
    end
end
