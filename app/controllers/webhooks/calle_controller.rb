module Webhooks
  class CalleController < ApplicationController
    allow_unauthenticated_access
    skip_forgery_protection
    wrap_parameters false

    before_action :require_json

    def create
      payload = JSON.parse(request.raw_post)
      event_id = request.headers["CALL-E-Event-Id"]
      body_event_id = payload["id"] if payload.is_a?(Hash)

      unless event_id.present? && body_event_id.present? && event_id == body_event_id
        render json: { ok: false }, status: :bad_request
        return
      end

      process_once(payload, event_id)
      render json: { ok: true }
    rescue JSON::ParserError
      render json: { ok: false }, status: :bad_request
    rescue ActiveRecord::RecordNotUnique
      render json: { ok: true }
    rescue StandardError
      render json: { ok: false }, status: :internal_server_error
    end

    private
      def require_json
        return if request.media_type == "application/json"

        render json: { ok: false }, status: :unsupported_media_type
      end

      def process_once(payload, event_id)
        WebhookEvent.transaction do
          webhook_event = WebhookEvent.create!(
            provider: "calle",
            event_id: event_id,
            payload: payload
          )

          process_call_attempt(payload["data"])
          webhook_event.update!(processed_at: Time.current)
        end
      end

      def process_call_attempt(data)
        return unless data.is_a?(Hash)

        call_attempt = CallAttempt.find_by(provider_call_id: data["id"])
        return unless call_attempt
        return unless metadata_consistent?(data, call_attempt)

        case data["status"]
        when "completed"
          complete_call_attempt(call_attempt, data)
        when "failed", "canceled"
          fail_call_attempt(call_attempt, data)
        end
      end

      def metadata_consistent?(data, call_attempt)
        metadata = data["metadata"]
        return true unless metadata.is_a?(Hash)

        metadata_call_attempt_id = metadata["call_attempt_id"]
        metadata_call_attempt_id.blank? || metadata_call_attempt_id.to_s == call_attempt.id.to_s
      end

      def complete_call_attempt(call_attempt, data)
        structured_result = data["structured_result"].is_a?(Hash) ? data["structured_result"] : {}
        provider_outcome = structured_result["outcome"].to_s

        call_attempt.update!(
          status: :completed,
          outcome: CallAttempt.outcomes.key?(provider_outcome) ? provider_outcome : :unknown,
          reason: string_value(structured_result["reason"]),
          promise_to_pay_on: parse_date(structured_result["promise_to_pay_on"]),
          sentiment: string_value(structured_result["sentiment"]),
          summary: string_value(data["summary"]),
          transcript: flattened_transcript(data),
          started_at: earliest_started_at(data),
          completed_at: terminal_completed_at(data),
          raw_result: data
        )
      end

      def fail_call_attempt(call_attempt, data)
        call_attempt.update!(
          status: :failed,
          summary: string_value(data["summary"]),
          started_at: earliest_started_at(data),
          completed_at: terminal_completed_at(data),
          raw_result: data
        )
      end

      def flattened_transcript(data)
        lines = call_attempts(data).flat_map do |attempt|
          array_value(attempt["transcript_turns"]).filter_map do |turn|
            next unless turn.is_a?(Hash)

            text = string_value(turn["text"])
            speaker = transcript_speaker(turn["speaker"])
            "#{speaker}: #{text}" if speaker && text
          end
        end

        lines.join("\n").presence
      end

      def transcript_speaker(value)
        case value.to_s.downcase
        when "bot", "assistant", "agent" then "Bot"
        when "user", "recipient", "human" then "User"
        end
      end

      def earliest_started_at(data)
        call_attempts(data).filter_map { |attempt| parse_time(attempt["started_at"]) }.min
      end

      def terminal_completed_at(data)
        parse_time(data["completed_at"]) ||
          call_attempts(data).filter_map { |attempt| parse_time(attempt["completed_at"]) }.max
      end

      def call_attempts(data)
        array_value(data["recipients"]).flat_map do |recipient|
          recipient.is_a?(Hash) ? array_value(recipient["attempts"]).select { |attempt| attempt.is_a?(Hash) } : []
        end
      end

      def array_value(value)
        value.is_a?(Array) ? value : []
      end

      def string_value(value)
        value.is_a?(String) ? value.presence : nil
      end

      def parse_date(value)
        Date.iso8601(value) if value.is_a?(String)
      rescue Date::Error
        nil
      end

      def parse_time(value)
        Time.iso8601(value).in_time_zone if value.is_a?(String)
      rescue ArgumentError
        nil
      end
  end
end
