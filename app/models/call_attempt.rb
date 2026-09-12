class CallAttempt < ApplicationRecord
  class InvalidTransitionError < StandardError; end

  include CalleGoal

  belongs_to :invoice
  belongs_to :contact

  enum :status, {
    pending: 0,
    in_progress: 1,
    completed: 2,
    failed: 3
  }

  enum :outcome, {
    promised_to_pay: 0,
    already_paid: 1,
    invoice_not_received: 2,
    payment_pending: 3,
    missing_information: 4,
    disputed: 5,
    refused: 6,
    no_answer: 7,
    wrong_contact: 8,
    human_followup_required: 9
  }

  validates :status, presence: true
  validate :contact_belongs_to_invoice_customer

  private
    def contact_belongs_to_invoice_customer
      return if invoice.blank? || contact.blank?
      return if invoice.customer == contact.customer

      errors.add(:contact, "must belong to the same customer as the invoice")
    end
end
