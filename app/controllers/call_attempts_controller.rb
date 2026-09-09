class CallAttemptsController < ApplicationController
  before_action :set_call_attempt, only: :show
  before_action :set_invoice, only: :create

  def show
    @invoice = @call_attempt.invoice
    @customer = @invoice.customer
    @contact = @call_attempt.contact
  end

  def create
    unless @invoice.overdue?
      redirect_to @invoice, alert: "Only overdue open invoices can be followed up by phone."
      return
    end

    contact = @invoice.customer.contacts.find(params.require(:contact_id))

    unless Contact::E164_FORMAT.match?(contact.phone_number)
      redirect_to @invoice, alert: "The selected contact needs a valid international phone number."
      return
    end

    @call_attempt = @invoice.call_attempts.create!(contact: contact)
    response = Calle::Client.new.create_call(
      payload: call_payload(contact),
      idempotency_key: "duecall-call-attempt-#{@call_attempt.id}"
    )

    @call_attempt.update!(
      provider_call_id: response.fetch("id"),
      status: response["status"] == "in_progress" ? :in_progress : :pending,
      raw_result: response
    )

    redirect_to @call_attempt, notice: "The follow-up call was queued with CALL-E."
  rescue Calle::Error => error
    @call_attempt&.update!(status: :failed, raw_result: error.details)
    redirect_to @call_attempt || @invoice, alert: call_error_message(error)
  end

  private
    def set_call_attempt
      owned_invoices = Invoice.where(customer: Current.user.customers)
      @call_attempt = CallAttempt.where(invoice: owned_invoices).find(params[:id])
    end

    def set_invoice
      @invoice = Invoice.where(customer: Current.user.customers).find(params[:invoice_id])
    end

    def call_payload(contact)
      {
        task: call_task,
        recipients: [ { phones: [ contact.phone_number ] } ],
        result_schema: result_schema,
        metadata: {
          call_attempt_id: @call_attempt.id.to_s,
          invoice_id: @invoice.id.to_s
        }
      }
    end

    def call_task
      <<~TASK.squish
        You are an AI assistant calling on behalf of the business that issued invoice #{@invoice.number}
        for #{formatted_invoice_amount}, due #{@invoice.due_on.iso8601}. Identify yourself as an AI assistant,
        politely state the invoice details, and ask for the current payment status. When payment is delayed,
        determine the reason. If the recipient voluntarily gives a payment date, capture it. Identify whether
        payment was already sent, the invoice or PO information is missing, the invoice is disputed, or this is
        the wrong contact. Never threaten or pressure the recipient, make legal claims, request card or bank
        credentials, or make commitments for the business. Escalate ambiguous or sensitive situations for human follow-up.
      TASK
    end

    def formatted_invoice_amount
      major, minor = @invoice.amount_cents.divmod(100)
      "#{@invoice.currency} #{major}.#{minor.to_s.rjust(2, "0")}"
    end

    def result_schema
      {
        type: "object",
        properties: {
          outcome: {
            type: "string",
            enum: CallAttempt.outcomes.keys,
            description: "The clearest supported payment follow-up outcome from the call evidence. Use unknown when the evidence is insufficient."
          },
          reason: {
            type: "string",
            description: "Short explanation of why payment is delayed or what happened during the call."
          },
          promise_to_pay_on: {
            type: "string",
            description: "Payment date explicitly committed to by the recipient, preferably YYYY-MM-DD. Omit when no clear date was committed."
          },
          sentiment: {
            type: "string",
            enum: %w[ positive neutral negative unknown ],
            description: "Overall recipient sentiment during the payment discussion."
          }
        },
        required: [ "outcome" ],
        additionalProperties: false
      }
    end

    def call_error_message(error)
      if error.details["error"] == "missing_api_key"
        "Calling is unavailable because CALL-E is not configured."
      else
        "CALL-E could not start the call. No automatic retry was made."
      end
    end
end
