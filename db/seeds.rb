demo_email = ENV.fetch("DUECALL_DEMO_EMAIL", "demo@duecall.test")
demo_password = ENV["DUECALL_DEMO_PASSWORD"].presence

if demo_password.blank? && Rails.env.production?
  raise "DUECALL_DEMO_PASSWORD is required when seeding the demo user in production"
end

demo_phone = ENV["DUECALL_DEMO_PHONE"].to_s.strip

unless Contact::E164_FORMAT.match?(demo_phone)
  raise "DUECALL_DEMO_PHONE must be a valid E.164 phone number, e.g. +628123456789"
end

ApplicationRecord.transaction do
  user = User.find_by(email_address: demo_email) ||
    User.find_by(email_address: "demo@duecall.local") ||
    User.new
  user.email_address = demo_email
  user.password = demo_password || "password123"
  user.save!

  acme = user.customers.find_or_initialize_by(name: "Acme Corporation")
  acme.save!

  acme_contact = acme.contacts.find_or_initialize_by(name: "Kurnia")
  acme_contact.update!(
    phone_number: demo_phone,
    time_zone: "Eastern Time (US & Canada)",
    business_hours_start: "09:00",
    business_hours_end: "17:00"
  )

  acme_invoice = acme.invoices.find_or_initialize_by(number: "INV-DEMO-001")
  acme_invoice.update!(
    amount_cents: 125_000,
    currency: "USD",
    due_on: Date.current - 14.days,
    status: :open,
    autonomous_follow_up_enabled: false
  )

  northwind = user.customers.find_or_initialize_by(name: "Northwind Logistics")
  northwind.save!

  northwind_contact = northwind.contacts.find_or_initialize_by(name: "Demo Contact")
  northwind_contact.update!(
    phone_number: demo_phone,
    time_zone: "London",
    business_hours_start: "09:00",
    business_hours_end: "17:00"
  )

  autonomous_invoice = northwind.invoices.find_or_initialize_by(number: "INV-DEMO-002")
  autonomous_invoice.update!(
    amount_cents: 248_000,
    currency: "USD",
    due_on: Date.current - 10.days,
    status: :open,
    autonomous_follow_up_enabled: false
  )

  attention_invoice = northwind.invoices.find_or_initialize_by(number: "INV-DEMO-003")
  attention_invoice.update!(
    amount_cents: 87_500,
    currency: "USD",
    due_on: Date.current - 7.days,
    status: :open,
    autonomous_follow_up_enabled: false
  )

  disputed_attempt = attention_invoice.call_attempts
    .where("raw_result ->> 'demo_seed_key' = ?", "inv-demo-003-disputed")
    .first_or_initialize
  disputed_attempt.assign_attributes(
    contact: northwind_contact,
    status: :completed,
    outcome: :disputed,
    completed_at: disputed_attempt.completed_at || 2.days.ago,
    summary: "Customer disputes the invoice and requests human review.",
    raw_result: { "demo_seed_key" => "inv-demo-003-disputed" }
  )
  disputed_attempt.save!
  disputed_attempt.decide_next_action!

  puts <<~SUMMARY
    DueCall demo data ready:
      User: #{user.email_address}
      #{acme.name}: #{acme_invoice.number}
      #{northwind.name}: #{autonomous_invoice.number}, #{attention_invoice.number}
      Representative outcome: #{attention_invoice.number} — #{disputed_attempt.outcome} / #{disputed_attempt.next_action}
  SUMMARY
end
