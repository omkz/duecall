class WebhookEvent < ApplicationRecord
  validates :provider, presence: true
  validates :event_id, presence: true
end
