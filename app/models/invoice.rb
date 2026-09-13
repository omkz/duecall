class Invoice < ApplicationRecord
  AUTOMATIC_CALL_LIMIT = 3

  belongs_to :customer
  has_many :call_attempts, dependent: :destroy

  enum :status, {
    open: 0,
    paid: 1,
    cancelled: 2
  }

  normalizes :currency, with: ->(currency) { currency.strip.upcase }

  validates :number, presence: true, uniqueness: { scope: :customer_id }
  validates :amount_cents, numericality: { only_integer: true, greater_than: 0 }
  validates :currency, presence: true
  validates :due_on, presence: true
  validates :status, presence: true

  scope :overdue, -> { open.where(due_on: ...Date.current) }

  def overdue?
    open? && due_on < Date.current
  end

  def configure_autonomous_follow_up!(enabled:, now: Time.current)
    enabled = ActiveModel::Type::Boolean.new.cast(enabled)
    update!(autonomous_follow_up_enabled: enabled)

    schedule_pending_autonomous_follow_ups!(now:) if enabled
    self
  end

  private
    def schedule_pending_autonomous_follow_ups!(now:)
      call_attempts.where(
        status: CallAttempt.statuses[:completed],
        next_action: CallAttempt.next_actions[:retry_call]
      ).where.not(next_action_on: nil).find_each do |call_attempt|
        call_attempt.schedule_follow_up_execution!(now:)
      end
    end
end
