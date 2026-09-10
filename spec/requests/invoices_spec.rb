require "rails_helper"

RSpec.describe "Invoices", type: :request do
  let!(:user) { User.create!(email_address: "owner@example.com", password: "password") }
  let!(:other_user) { User.create!(email_address: "other@example.com", password: "password") }
  let!(:customer) { user.customers.create!(name: "Acme") }
  let!(:other_customer) { other_user.customers.create!(name: "Private customer") }

  before do
    post session_path, params: { email_address: user.email_address, password: "password" }
  end

  it "allows an authenticated user to CRUD invoices for their customer" do
    get invoices_path
    expect(response).to have_http_status(:ok)
    expect(response.body).to include("No invoices yet")

    get customer_path(customer)
    expect(response.body).to include("No invoices yet")

    get new_customer_invoice_path(customer)
    expect(response).to have_http_status(:ok)

    expect do
      post customer_invoices_path(customer), params: {
        invoice: {
          number: "INV-001",
          amount: "125.00",
          amount_cents: 999_999,
          currency: "usd",
          issued_on: Date.current,
          due_on: Date.current + 7.days,
          status: "open",
          external_id: "ERP-42",
          customer_id: other_customer.id
        }
      }
    end.to change(customer.invoices, :count).by(1)

    invoice = customer.invoices.find_by!(number: "INV-001")
    expect(invoice.customer).to eq(customer)
    expect(invoice.amount_cents).to eq(12_500)
    expect(invoice.currency).to eq("USD")
    expect(response).to redirect_to(invoice_path(invoice))

    get customer_path(customer)
    expect(response.body).to include("INV-001", "USD 125.00")

    get invoices_path
    expect(response.body).to include("INV-001", "Acme", "USD 125.00")

    get invoice_path(invoice)
    expect(response).to have_http_status(:ok)
    expect(response.body).to include("INV-001", "USD 125.00", "ERP-42")

    invoice.update!(amount_cents: 480_000)
    get edit_invoice_path(invoice)
    expect(response).to have_http_status(:ok)
    expect(response.body).to include('value="4800.00"')

    patch invoice_path(invoice), params: {
      invoice: { number: "INV-UPDATED", amount: "4800.50", status: "paid", customer_id: other_customer.id }
    }
    expect(response).to redirect_to(invoice_path(invoice))
    expect(invoice.reload.number).to eq("INV-UPDATED")
    expect(invoice.amount_cents).to eq(480_050)
    expect(invoice).to be_paid
    expect(invoice.customer).to eq(customer)

    expect do
      delete invoice_path(invoice)
    end.to change(customer.invoices, :count).by(-1)
    expect(response).to redirect_to(customer_path(customer))
  end

  it "stores decimal major-unit amounts as integer cents" do
    post customer_invoices_path(customer), params: {
      invoice: { number: "INV-DECIMAL", amount: "4800.50", due_on: Date.current }
    }

    expect(customer.invoices.find_by!(number: "INV-DECIMAL").amount_cents).to eq(480_050)

    post customer_invoices_path(customer), params: {
      invoice: { number: "INV-PENNY", amount: "0.01", due_on: Date.current }
    }

    expect(customer.invoices.find_by!(number: "INV-PENNY").amount_cents).to eq(1)
  end

  it "rejects malformed amounts and amounts more precise than cents" do
    [ "abc", "12.345", "0", "-5" ].each do |amount|
      expect do
        post customer_invoices_path(customer), params: {
          invoice: { number: "INVALID-#{amount}", amount: amount, due_on: Date.current }
        }
      end.not_to change(Invoice, :count)

      expect(response).to have_http_status(:unprocessable_content)
      expect(response.body).to include("Please fix the following")
    end
  end

  it "ignores direct amount_cents assignment from public params" do
    expect do
      post customer_invoices_path(customer), params: {
        invoice: { number: "CENTS-ONLY", amount_cents: 50_000, due_on: Date.current }
      }
    end.not_to change(Invoice, :count)

    expect(response).to have_http_status(:unprocessable_content)
  end

  it "isolates invoices belonging to another user" do
    own_invoice = customer.invoices.create!(
      number: "VISIBLE",
      amount_cents: 10_000,
      due_on: Date.current
    )
    invoice = other_customer.invoices.create!(
      number: "PRIVATE",
      amount_cents: 20_000,
      due_on: Date.current
    )

    get invoices_path
    expect(response.body).to include(own_invoice.number)
    expect(response.body).not_to include(invoice.number, other_customer.name)

    get invoice_path(invoice)
    expect(response).to have_http_status(:not_found)

    get edit_invoice_path(invoice)
    expect(response).to have_http_status(:not_found)

    patch invoice_path(invoice), params: { invoice: { number: "COMPROMISED" } }
    expect(response).to have_http_status(:not_found)
    expect(invoice.reload.number).to eq("PRIVATE")

    delete invoice_path(invoice)
    expect(response).to have_http_status(:not_found)
    expect(Invoice.exists?(invoice.id)).to be(true)
  end

  it "rejects creation under another user's customer" do
    expect do
      post customer_invoices_path(other_customer), params: {
        invoice: { number: "INTRUDER", amount_cents: 10_000, due_on: Date.current }
      }
    end.not_to change(Invoice, :count)

    expect(response).to have_http_status(:not_found)
  end
end
