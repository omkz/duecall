require "rails_helper"

RSpec.describe "Customers", type: :request do
  let!(:user) { User.create!(email_address: "owner@example.com", password: "password") }
  let!(:other_user) { User.create!(email_address: "other@example.com", password: "password") }

  before do
    post session_path, params: { email_address: user.email_address, password: "password" }
  end

  it "allows an authenticated user to CRUD their own customers" do
    get customers_path
    expect(response).to have_http_status(:ok)
    expect(response.body).to include("No customers yet")

    get new_customer_path
    expect(response).to have_http_status(:ok)

    expect do
      post customers_path, params: {
        customer: { name: "Acme", email: "hello@acme.test", external_id: "CRM-42", user_id: other_user.id }
      }
    end.to change(user.customers, :count).by(1)

    customer = user.customers.find_by!(name: "Acme")
    expect(customer.user).to eq(user)
    expect(response).to redirect_to(customer_path(customer))

    get customer_path(customer)
    expect(response).to have_http_status(:ok)
    expect(response.body).to include("hello@acme.test", "CRM-42")

    get edit_customer_path(customer)
    expect(response).to have_http_status(:ok)

    patch customer_path(customer), params: { customer: { name: "Acme Updated", user_id: other_user.id } }
    expect(response).to redirect_to(customer_path(customer))
    expect(customer.reload.name).to eq("Acme Updated")
    expect(customer.user).to eq(user)

    expect do
      delete customer_path(customer)
    end.to change(user.customers, :count).by(-1)
    expect(response).to redirect_to(customers_path)
  end

  it "does not allow access to or modification of another user's customer" do
    customer = other_user.customers.create!(name: "Private customer")

    get customers_path
    expect(response.body).not_to include("Private customer")

    get customer_path(customer)
    expect(response).to have_http_status(:not_found)

    get edit_customer_path(customer)
    expect(response).to have_http_status(:not_found)

    patch customer_path(customer), params: { customer: { name: "Compromised" } }
    expect(response).to have_http_status(:not_found)
    expect(customer.reload.name).to eq("Private customer")

    delete customer_path(customer)
    expect(response).to have_http_status(:not_found)
    expect(Customer.exists?(customer.id)).to be(true)
  end
end
