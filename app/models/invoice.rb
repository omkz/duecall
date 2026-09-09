class Invoice < ApplicationRecord
  belongs_to :customer

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
end
