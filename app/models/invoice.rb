require "bigdecimal"

class Invoice < ApplicationRecord
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
  validate :amount_input_has_valid_precision

  scope :overdue, -> { open.where(due_on: ...Date.current) }

  def amount
    return @amount_input if @amount_input_invalid
    return if amount_cents.blank?

    major, minor = amount_cents.divmod(100)
    "#{major}.#{minor.to_s.rjust(2, "0")}"
  end

  def amount=(value)
    @amount_input = value
    @amount_input_invalid = false

    if value.blank?
      self.amount_cents = nil
      return
    end

    normalized_value = value.to_s.strip
    unless normalized_value.match?(/\A\d+(?:\.\d{1,2})?\z/)
      @amount_input_invalid = true
      self.amount_cents = nil
      return
    end

    self.amount_cents = (BigDecimal(normalized_value) * 100).to_i
  rescue ArgumentError, TypeError
    @amount_input_invalid = true
    self.amount_cents = nil
  end

  def overdue?
    open? && due_on < Date.current
  end

  private
    def amount_input_has_valid_precision
      return unless @amount_input_invalid

      errors.add(:amount, "must be a valid amount with no more than 2 decimal places")
    end
end
