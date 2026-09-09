require "rails_helper"

RSpec.describe "Contacts", type: :request do
  let!(:user) { User.create!(email_address: "owner@example.com", password: "password") }
  let!(:other_user) { User.create!(email_address: "other@example.com", password: "password") }
  let!(:customer) { user.customers.create!(name: "Acme") }
  let!(:other_customer) { other_user.customers.create!(name: "Private customer") }

  before do
    post session_path, params: { email_address: user.email_address, password: "password" }
  end

  it "allows an authenticated user to CRUD contacts for their customer" do
    get customer_path(customer)
    expect(response).to have_http_status(:ok)
    expect(response.body).to include("No contacts yet")

    get new_customer_contact_path(customer)
    expect(response).to have_http_status(:ok)

    expect do
      post customer_contacts_path(customer), params: {
        contact: {
          name: "Rina",
          role: "Finance",
          phone_number: "+628123456789",
          email: "rina@acme.test",
          customer_id: other_customer.id
        }
      }
    end.to change(customer.contacts, :count).by(1)

    contact = customer.contacts.find_by!(name: "Rina")
    expect(contact.customer).to eq(customer)
    expect(response).to redirect_to(contact_path(contact))

    get customer_path(customer)
    expect(response.body).to include("Rina", "Finance", "+628123456789", "rina@acme.test")

    get contact_path(contact)
    expect(response).to have_http_status(:ok)
    expect(response.body).to include("Rina", "Finance", "+628123456789", "rina@acme.test")

    get edit_contact_path(contact)
    expect(response).to have_http_status(:ok)

    patch contact_path(contact), params: {
      contact: { name: "Rina Updated", role: "Operations", customer_id: other_customer.id }
    }
    expect(response).to redirect_to(contact_path(contact))
    expect(contact.reload.name).to eq("Rina Updated")
    expect(contact.role).to eq("Operations")
    expect(contact.customer).to eq(customer)

    expect do
      delete contact_path(contact)
    end.to change(customer.contacts, :count).by(-1)
    expect(response).to redirect_to(customer_path(customer))
  end

  it "does not allow access to or modification of another user's contact" do
    contact = other_customer.contacts.create!(name: "Private contact", phone_number: "+628111111111")

    get contact_path(contact)
    expect(response).to have_http_status(:not_found)

    get edit_contact_path(contact)
    expect(response).to have_http_status(:not_found)

    patch contact_path(contact), params: { contact: { name: "Compromised" } }
    expect(response).to have_http_status(:not_found)
    expect(contact.reload.name).to eq("Private contact")

    delete contact_path(contact)
    expect(response).to have_http_status(:not_found)
    expect(Contact.exists?(contact.id)).to be(true)
  end

  it "does not allow creating a contact under another user's customer" do
    expect do
      post customer_contacts_path(other_customer), params: {
        contact: { name: "Intruder", phone_number: "+628122222222" }
      }
    end.not_to change(Contact, :count)

    expect(response).to have_http_status(:not_found)
  end
end
