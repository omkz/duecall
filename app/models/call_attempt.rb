class CallAttempt < ApplicationRecord
  class InvalidTransitionError < StandardError; end

  include CalleGoal
  include FollowUpDecision
  include AutonomousFollowUp

  belongs_to :invoice
  belongs_to :contact
  belongs_to :parent_call_attempt, class_name: "CallAttempt", optional: true,
    inverse_of: :follow_up_call_attempt
  has_one :follow_up_call_attempt, class_name: "CallAttempt", foreign_key: :parent_call_attempt_id,
    inverse_of: :parent_call_attempt, dependent: :nullify

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
    human_followup_required: 9,
    unknown: 10
  }

  enum :next_action, {
    stop: 0,
    retry_call: 1,
    human_followup: 2
  }

  validates :status, presence: true
  validate :contact_belongs_to_invoice_customer
  validate :parent_call_attempt_matches

  private
    def contact_belongs_to_invoice_customer
      return if invoice.blank? || contact.blank?
      return if invoice.customer == contact.customer

      errors.add(:contact, "must belong to the same customer as the invoice")
    end

    def parent_call_attempt_matches
      return if parent_call_attempt.blank?
      return if parent_call_attempt.invoice == invoice && parent_call_attempt.contact == contact

      errors.add(:parent_call_attempt, "must use the same invoice and contact")
    end
end
