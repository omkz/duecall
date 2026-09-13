demo_email = "demo@duecall.local"
customer_name = "Acme Corporation"
contact_name = "Kurnia"
invoice_number = "INV-DEMO-001"

demo_phone = ENV["DUECALL_DEMO_PHONE"].presence ||
  Rails.application.credentials.dig(:duecall, :demo_phone)
demo_phone = demo_phone.to_s.strip

unless Contact::E164_FORMAT.match?(demo_phone)
  raise "DUECALL_DEMO_PHONE must be a valid E.164 phone number, e.g. +628123456789"
end

ApplicationRecord.transaction do
  user = User.find_or_initialize_by(email_address: demo_email)
  if user.new_record?
    demo_password = ENV["DUECALL_DEMO_PASSWORD"].presence
    if demo_password.blank? && Rails.env.production?
      raise "DUECALL_DEMO_PASSWORD is required when creating the demo user in production"
    end

    user.password = demo_password || "password123"
    user.save!
  end

  customer = user.customers.find_or_initialize_by(name: customer_name)
  customer.update!(name: customer_name)

  contact = customer.contacts.find_or_initialize_by(name: contact_name)
  contact.update!(name: contact_name, phone_number: demo_phone, time_zone: "Eastern Time (US & Canada)")

  invoice = customer.invoices.find_or_initialize_by(number: invoice_number)
  invoice.update!(
    number: invoice_number,
    amount_cents: 125_000,
    currency: "USD",
    due_on: Date.new(2026, 9, 1),
    status: :open,
    autonomous_follow_up_enabled: false
  )

  puts <<~SUMMARY
    DueCall demo data ready:
      User: #{user.email_address}
      Customer: #{customer.name}
      Contact: #{contact.name} (#{contact.phone_number}, #{contact.time_zone})
      Invoice: #{invoice.number} — #{invoice.currency} #{format("%.2f", invoice.amount_cents.fdiv(100))}
      Due date: #{invoice.due_on.iso8601}
  SUMMARY
end
