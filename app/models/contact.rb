class Contact < ApplicationRecord
  E164_FORMAT = /\A\+[1-9]\d{1,14}\z/

  belongs_to :customer

  validates :name, presence: true
  validates :phone_number, presence: true
  validates :phone_number, format: { with: E164_FORMAT, allow_blank: true }
  validates :email, format: { with: URI::MailTo::EMAIL_REGEXP }, allow_blank: true
end
