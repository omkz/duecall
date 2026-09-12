module Calle
  class RunGoal
    class InvalidStateError < Error; end

    def self.call(call_attempt:, **options)
      new(call_attempt:, **options).call
    end

    def initialize(call_attempt:, client: nil,
      goal_id: Rails.application.config.x.calle.overdue_invoice_goal_id)
      @call_attempt = call_attempt
      @client = client
      @goal_id = goal_id
    end

    def call
      call_attempt.with_lock do
        validate_submission!

        response = client.create_goal_run(
          goal_id: goal_id,
          phone: call_attempt.contact.phone_number,
          variables: goal_variables,
          idempotency_key: idempotency_key
        )

        call_attempt.update!(
          provider_goal_run_id: response.fetch("id"),
          status: :in_progress,
          raw_result: response,
          started_at: call_attempt.started_at || Time.current
        )
      end

      call_attempt
    rescue ConfigurationError, RequestError => error
      mark_failed!(error)
      call_attempt
    end

    private
      attr_reader :call_attempt, :goal_id

      def client
        @client ||= Client.new
      end

      def validate_submission!
        unless call_attempt.persisted? && call_attempt.pending?
          raise InvalidStateError, "CallAttempt must be persisted and pending"
        end

        if goal_id.blank?
          raise ConfigurationError, "CALL-E overdue invoice Goal ID is not configured"
        end
      end

      def goal_variables
        invoice = call_attempt.invoice

        {
          customer_name: invoice.customer.name,
          contact_name: call_attempt.contact.name,
          invoice_number: invoice.number,
          amount: invoice.amount_cents.fdiv(100),
          currency: invoice.currency,
          due_date: invoice.due_on.iso8601
        }
      end

      def idempotency_key
        "duecall:call_attempt:#{call_attempt.id}:overdue_invoice_goal:v1"
      end

      def mark_failed!(error)
        details = error.respond_to?(:details) ? error.details : {}
        failure = details.merge(
          "error_class" => error.class.name,
          "error_message" => error.message
        )

        call_attempt.update!(status: :failed, raw_result: { "submission_error" => failure })
      end
  end
end
