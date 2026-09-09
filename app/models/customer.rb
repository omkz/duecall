class Customer < ApplicationRecord
  belongs_to :user
  has_many :contacts, dependent: :destroy

  validates :name, presence: true
  validates :email, format: { with: URI::MailTo::EMAIL_REGEXP }, allow_blank: true
end
