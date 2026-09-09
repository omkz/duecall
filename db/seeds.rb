seed_demo = Rails.env.development? || ENV["DUECALL_DEMO_SEED"] == "1"

unless seed_demo
  puts "Skipping DueCall demo data. Set DUECALL_DEMO_SEED=1 to seed this environment."
end

if seed_demo
  demo_email = ENV.fetch("DUECALL_DEMO_EMAIL", "demo@duecall.test").strip.downcase
  demo_password = if Rails.env.development?
    ENV.fetch("DUECALL_DEMO_PASSWORD", "password")
  else
    ENV["DUECALL_DEMO_PASSWORD"].presence ||
      raise("DUECALL_DEMO_PASSWORD is required when seeding demo data outside development")
  end

  today = Date.current
  now = Time.current

  demo_user = ApplicationRecord.transaction do
    demo_user = User.find_by(email_address: demo_email)

    if demo_user
      seed_owned = demo_user.customers
        .joins(:invoices)
        .where(
          name: "Northstar Supplies",
          invoices: { external_id: "demo_inv_1042" }
        )
        .exists?

      unless seed_owned
        raise(
          "DUECALL_DEMO_EMAIL belongs to an existing non-demo account; " \
          "refusing to change its password or data"
        )
      end

      demo_user.update!(password: demo_password)
    else
      demo_user = User.create!(email_address: demo_email, password: demo_password)
    end

    # Only the dedicated demo user's domain data is rebuilt. Other users are untouched.
    demo_user.customers.destroy_all

    customers = [
      {
        name: "Atlas Components",
        contact: {
          name: "Maya Chen", role: "Accounts Payable Manager",
          phone_number: "+12025550101", email: "maya@example.test"
        },
        invoice: { number: "INV-1048", amount_cents: 725_000, currency: "USD", days_overdue: 21 },
        call: {
          provider_call_id: "demo_call_inv_1048", outcome: :disputed,
          reason: "Quantity on the invoice does not match the receiving record.",
          summary: "Maya confirmed the invoice is blocked by a quantity discrepancy and asked the vendor to review the shipment record.",
          sentiment: "neutral",
          transcript: <<~TRANSCRIPT.strip,
            Bot: Hello, I'm calling about invoice INV-1048.
            User: Our receiving record shows fewer units than the invoice.
            Bot: I understand. I'll flag the quantity discrepancy for review.
          TRANSCRIPT
          hours_ago: 6
        }
      },
      {
        name: "Northstar Supplies",
        contact: {
          name: "Daniel Brooks", role: "Accounts Payable",
          phone_number: "+12025550102", email: "daniel@example.test"
        },
        invoice: { number: "INV-1042", amount_cents: 480_000, currency: "USD", days_overdue: 14 },
        call: {
          provider_call_id: "demo_call_inv_1042", outcome: :missing_information,
          reason: "Purchase order number is missing from the invoice.",
          summary: "Daniel said AP cannot process the invoice until PO-9912 is included on the corrected invoice.",
          sentiment: "positive",
          transcript: <<~TRANSCRIPT.strip,
            Bot: I'm calling about overdue invoice INV-1042.
            User: We have it, but it is missing purchase order PO-9912.
            Bot: Thank you. I'll ask the billing team to send a corrected invoice.
          TRANSCRIPT
          hours_ago: 1
        }
      },
      {
        name: "Brightline Retail",
        contact: {
          name: "Sarah Miller", role: "Finance Manager",
          phone_number: "+12025550103", email: "sarah@example.test"
        },
        invoice: { number: "INV-1037", amount_cents: 240_000, currency: "USD", days_overdue: 10 },
        call: {
          provider_call_id: "demo_call_inv_1037", outcome: :promised_to_pay,
          promise_to_pay_on: today - 2.days,
          reason: "Payment had been scheduled after internal approval.",
          summary: "Sarah committed to payment, but the promised payment date has now passed.",
          sentiment: "positive",
          transcript: <<~TRANSCRIPT.strip,
            Bot: When do you expect payment for invoice INV-1037?
            User: It is approved. We can send payment by Friday.
            Bot: Thank you, I've noted that payment date.
          TRANSCRIPT
          hours_ago: 30
        }
      },
      {
        name: "Oak & Co.",
        contact: {
          name: "Emma Wilson", role: "Bookkeeper",
          phone_number: "+12025550104", email: "emma@example.test"
        },
        invoice: { number: "INV-1051", amount_cents: 195_000, currency: "USD", days_overdue: 7 }
      },
      {
        name: "Meridian Labs",
        contact: {
          name: "James Carter", role: "Accounts Payable",
          phone_number: "+12025550105", email: "james@example.test"
        },
        invoice: { number: "INV-1046", amount_cents: 360_000, currency: "USD", days_overdue: 5 },
        call: {
          provider_call_id: "demo_call_inv_1046", outcome: :no_answer,
          summary: "No one answered after the call rang through.", hours_ago: 8
        }
      },
      {
        name: "Harbor Foods",
        contact: {
          name: "Olivia Martin", role: "Finance Operations",
          phone_number: "+12025550106", email: "olivia@example.test"
        },
        invoice: { number: "INV-1039", amount_cents: 510_000, currency: "USD", days_overdue: 12 },
        call: {
          provider_call_id: "demo_call_inv_1039", outcome: :promised_to_pay,
          promise_to_pay_on: today + 3.days,
          reason: "Payment is approved and scheduled in the next payment run.",
          summary: "Olivia confirmed the invoice is approved and committed to payment in three days.",
          sentiment: "positive",
          transcript: <<~TRANSCRIPT.strip,
            Bot: I'm following up on invoice INV-1039.
            User: It is approved and will be paid in our next run, three days from now.
            Bot: Thank you, I've recorded the promised payment date.
          TRANSCRIPT
          hours_ago: 4
        }
      },
      {
        name: "Nordwerk GmbH",
        contact: {
          name: "Lena Fischer", role: "Accounts Payable",
          phone_number: "+12025550107", email: "lena@example.test"
        },
        invoice: { number: "INV-EU-204", amount_cents: 320_000, currency: "EUR", days_overdue: 9 },
        call: {
          provider_call_id: "demo_call_inv_eu_204", outcome: :invoice_not_received,
          reason: "Accounts payable does not have a copy of the invoice.",
          summary: "Lena requested that the invoice be resent to the AP mailbox.",
          sentiment: "neutral", hours_ago: 5
        }
      },
      {
        name: "BluePeak Media",
        contact: {
          name: "Alex Morgan", role: "Finance Lead",
          phone_number: "+12025550108", email: "alex@example.test"
        },
        invoice: { number: "INV-1053", amount_cents: 180_000, currency: "USD", days_overdue: 3 },
        call: {
          provider_call_id: "demo_call_inv_1053", status: :in_progress,
          started_at: now - 2.minutes
        }
      }
    ]

    seeded = {}

    customers.each do |attributes|
      customer = demo_user.customers.create!(name: attributes.fetch(:name))
      contact = customer.contacts.create!(attributes.fetch(:contact))
      invoice_attributes = attributes.fetch(:invoice)
      invoice = customer.invoices.create!(
        number: invoice_attributes.fetch(:number),
        amount_cents: invoice_attributes.fetch(:amount_cents),
        currency: invoice_attributes.fetch(:currency),
        issued_on: today - invoice_attributes.fetch(:days_overdue) - 30.days,
        due_on: today - invoice_attributes.fetch(:days_overdue),
        status: :open,
        external_id: "demo_#{invoice_attributes.fetch(:number).downcase.tr("-", "_")}"
      )

      if attributes[:call]
        call_attributes = attributes.fetch(:call).dup
        status = call_attributes.delete(:status) || :completed
        hours_ago = call_attributes.delete(:hours_ago)
        started_at = call_attributes.delete(:started_at) || now - hours_ago.hours
        completed_at = status == :completed ? started_at + 4.minutes : nil

        invoice.call_attempts.create!(
          {
            contact: contact, status: status, started_at: started_at,
            completed_at: completed_at, created_at: started_at, raw_result: {}
          }.merge(call_attributes)
        )
      end

      seeded[customer.name] = { customer: customer, contact: contact, invoice: invoice }
    end

    seeded.fetch("Atlas Components").fetch(:customer).invoices.create!(
      number: "INV-1060", amount_cents: 285_000, currency: "USD",
      issued_on: today, due_on: today + 30.days, status: :open,
      external_id: "demo_inv_1060"
    )

    seeded.fetch("Northstar Supplies").fetch(:customer).invoices.create!(
      number: "INV-1028", amount_cents: 125_000, currency: "USD",
      issued_on: today - 40.days, due_on: today - 10.days, status: :paid,
      external_id: "demo_inv_1028"
    )

    demo_user
  end

  owned_invoices = Invoice.where(customer: demo_user.customers)
  overdue_invoices = owned_invoices.overdue
  overdue_totals = overdue_invoices.group(:currency).sum(:amount_cents)
  latest_attempts = CallAttempt
    .where(invoice: owned_invoices)
    .select("DISTINCT ON (call_attempts.invoice_id) call_attempts.*")
    .order(:invoice_id, created_at: :desc, id: :desc)
    .index_by(&:invoice_id)
  overdue_ids = overdue_invoices.ids.index_with(true)
  payment_promises = latest_attempts.values.count do |call_attempt|
    overdue_ids.key?(call_attempt.invoice_id) && call_attempt.promised_to_pay? &&
      call_attempt.promise_to_pay_on.present? && call_attempt.promise_to_pay_on >= today
  end
  formatted_totals = overdue_totals.sort.map do |currency, cents|
    major, minor = cents.divmod(100)
    delimited_major = major.to_s.reverse.scan(/.{1,3}/).join(",").reverse
    "#{currency} #{delimited_major}.#{minor.to_s.rjust(2, "0")}"
  end

  puts "DueCall demo data is ready."
  puts "Email: #{demo_user.email_address}"
  puts "Password: #{demo_password}" if Rails.env.development?
  puts "Customers: #{demo_user.customers.count}"
  puts "Invoices: #{owned_invoices.count} (#{overdue_invoices.count} overdue)"
  puts "Call attempts: #{CallAttempt.where(invoice: owned_invoices).count}"
  puts "Overdue totals: #{formatted_totals.join(", ")}"
  puts "Active calls: #{CallAttempt.active.where(invoice: owned_invoices).count}"
  puts "Payment promises: #{payment_promises}"
end
