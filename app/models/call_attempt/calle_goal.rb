module CallAttempt::CalleGoal
  extend ActiveSupport::Concern

  def run_calle_goal!(client: nil, goal_id: default_calle_goal_id)
    with_lock do
      ensure_goal_status!(:pending)
      ensure_goal_id!(goal_id)

      response = (client || Calle::Client.new).create_goal_run(
        goal_id:,
        phone: contact.phone_number,
        variables: calle_goal_variables,
        idempotency_key: calle_idempotency_key
      )

      update!(
        provider_goal_run_id: response.fetch("id"),
        status: :in_progress,
        raw_result: response,
        started_at: started_at || Time.current
      )
    end

    self
  rescue Calle::ConfigurationError, Calle::RequestError => error
    update!(status: :failed, raw_result: { "submission_error" => calle_error_details(error) })
    self
  end

  def sync_calle_goal!(client: nil, goal_id: default_calle_goal_id)
    ensure_goal_status!(:in_progress)
    ensure_goal_run_id!
    ensure_goal_id!(goal_id)

    response = (client || Calle::Client.new).get_goal_run(
      goal_id:,
      goal_run_id: provider_goal_run_id
    )

    with_lock do
      return self unless in_progress?

      apply_calle_goal_run!(response)
    end

    self
  rescue Calle::ConfigurationError, Calle::RequestError => error
    with_lock do
      return self unless in_progress?

      update!(raw_result: raw_result.merge("sync_error" => calle_error_details(error)))
    end
    self
  end

  private
    def apply_calle_goal_run!(response)
      attributes = { raw_result: response }
      attributes[:provider_call_id] = response["call_id"] if response["call_id"].present?

      if !response["result"].nil?
        attributes.merge!(status: :completed, completed_at: calle_completion_time(response))
      elsif !response["error"].nil?
        attributes.merge!(status: :failed, completed_at: calle_completion_time(response))
      end

      update!(attributes)
    end

    def calle_goal_variables
      {
        customer_name: invoice.customer.name,
        contact_name: contact.name,
        invoice_number: invoice.number,
        amount: invoice.amount_cents.fdiv(100),
        currency: invoice.currency,
        due_date: invoice.due_on.iso8601
      }
    end

    def calle_idempotency_key
      "duecall:call_attempt:#{id}:overdue_invoice_goal:v1"
    end

    def calle_error_details(error)
      details = error.respond_to?(:details) ? error.details : {}
      details.merge("error_class" => error.class.name, "error_message" => error.message)
    end

    def calle_completion_time(response)
      return Time.current if response["completed_at"].blank?

      Time.zone.iso8601(response["completed_at"])
    rescue ArgumentError
      Time.current
    end

    def default_calle_goal_id
      Rails.application.config.x.calle.overdue_invoice_goal_id
    end

    def ensure_goal_status!(expected_status)
      return if public_send("#{expected_status}?")

      raise CallAttempt::InvalidTransitionError, "CallAttempt must be #{expected_status}"
    end

    def ensure_goal_id!(goal_id)
      return if goal_id.present?

      raise Calle::ConfigurationError, "CALL-E overdue invoice Goal ID is not configured"
    end

    def ensure_goal_run_id!
      return if provider_goal_run_id.present?

      raise CallAttempt::InvalidTransitionError, "CallAttempt must have a provider Goal Run ID"
    end
end
