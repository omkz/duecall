module CallAttemptsHelper
  def call_attempt_status_classes(call_attempt)
    case call_attempt.status
    when "completed" then "bg-emerald-100 text-emerald-700"
    when "failed" then "bg-red-100 text-red-700"
    when "in_progress" then "bg-blue-100 text-blue-700"
    else "bg-amber-100 text-amber-700"
    end
  end

  def payment_promise_missed?(call_attempt, invoice)
    call_attempt.promised_to_pay? && call_attempt.promise_to_pay_on.present? &&
      call_attempt.promise_to_pay_on < Date.current && invoice.open?
  end

  def call_attempt_duration(call_attempt)
    return if call_attempt.started_at.blank? || call_attempt.completed_at.blank?

    seconds = (call_attempt.completed_at - call_attempt.started_at).to_i
    return if seconds.negative?

    minutes, remaining_seconds = seconds.divmod(60)
    return "#{seconds}s" if minutes.zero?
    return "#{minutes}m" if remaining_seconds.zero?

    "#{minutes}m #{remaining_seconds}s"
  end

  def transcript_turns(transcript)
    transcript.to_s.lines.filter_map do |line|
      text = line.strip
      next if text.blank?

      prefix, message = text.split(":", 2)
      label = transcript_speaker_label(prefix) if message.present?

      if label
        { label: label, text: message.strip, speaker: label.parameterize }
      else
        { label: "Transcript", text: text, speaker: "neutral" }
      end
    end
  end

  private
    def transcript_speaker_label(prefix)
      case prefix.downcase
      when "bot", "agent" then "DueCall"
      when "user", "recipient" then "Customer"
      end
    end
end
