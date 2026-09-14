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
    expect(response.body).to include(
      "Calling hours",
      "Allowed from",
      "Allowed until",
      "Preferred call time (optional)",
      "Automatic retries target this time in the contact's local time zone. Leave blank to call as soon as an eligible retry falls within the allowed calling hours."
    )

    expect do
      post customer_contacts_path(customer), params: {
        contact: {
          name: "Rina",
          role: "Finance",
          phone_number: "+628123456789",
          email: "rina@acme.test",
          time_zone: "Asia/Jakarta",
          business_hours_start: "08:30",
          business_hours_end: "16:30",
          preferred_call_time: "14:00",
          customer_id: other_customer.id
        }
      }
    end.to change(customer.contacts, :count).by(1)

    contact = customer.contacts.find_by!(name: "Rina")
    expect(contact.customer).to eq(customer)
    expect(contact.business_hours_start.strftime("%H:%M")).to eq("08:30")
    expect(contact.business_hours_end.strftime("%H:%M")).to eq("16:30")
    expect(contact.preferred_call_time.strftime("%H:%M")).to eq("14:00")
    expect(response).to redirect_to(contact_path(contact))

    get customer_path(customer)
    expect(response.body).to include("Rina", "Finance", "+628123456789", "rina@acme.test")

    get contact_path(contact)
    expect(response).to have_http_status(:ok)
    expect(response.body).to include(
      "Rina",
      "Finance",
      "+628123456789",
      "rina@acme.test",
      "Asia/Jakarta",
      "Allowed calling hours",
      "08:30–16:30",
      "Preferred call time",
      "14:00"
    )

    get edit_contact_path(contact)
    expect(response).to have_http_status(:ok)

    patch contact_path(contact), params: {
      contact: {
        name: "Rina Updated",
        role: "Operations",
        time_zone: "Singapore",
        business_hours_start: "09:15",
        business_hours_end: "17:15",
        preferred_call_time: "15:00",
        customer_id: other_customer.id
      }
    }
    expect(response).to redirect_to(contact_path(contact))
    expect(contact.reload.name).to eq("Rina Updated")
    expect(contact.role).to eq("Operations")
    expect(contact.time_zone).to eq("Singapore")
    expect(contact.business_hours_start.strftime("%H:%M")).to eq("09:15")
    expect(contact.business_hours_end.strftime("%H:%M")).to eq("17:15")
    expect(contact.preferred_call_time.strftime("%H:%M")).to eq("15:00")
    expect(contact.customer).to eq(customer)

    expect do
      delete contact_path(contact)
    end.to change(customer.contacts, :count).by(-1)
    expect(response).to redirect_to(customer_path(customer))
  end

  it "shows when a preferred call time is not configured" do
    contact = customer.contacts.create!(
      name: "No preference",
      phone_number: "+628123456789",
      time_zone: "Asia/Jakarta"
    )

    get contact_path(contact)

    expect(response).to have_http_status(:ok)
    expect(response.body).to include("Preferred call time", "Not configured")
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
