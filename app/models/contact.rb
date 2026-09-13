class Contact < ApplicationRecord
  E164_FORMAT = /\A\+[1-9]\d{1,14}\z/

  belongs_to :customer
  has_many :call_attempts, dependent: :restrict_with_error

  validates :name, presence: true
  validates :phone_number, presence: true
  validates :phone_number, format: { with: E164_FORMAT, allow_blank: true }
  validates :email, format: { with: URI::MailTo::EMAIL_REGEXP }, allow_blank: true
  validate :time_zone_must_be_recognized

  def configured_time_zone
    ActiveSupport::TimeZone[time_zone] if time_zone.present?
  rescue TZInfo::InvalidTimezoneIdentifier
    nil
  end

  def next_business_opening(on_or_after:, now: Time.current)
    zone = configured_time_zone
    return unless zone

    local_now = now.in_time_zone(zone)
    date = [ on_or_after, local_now.to_date ].max
    date = next_weekday(date)
    opening = zone.local(date.year, date.month, date.day, 9)

    if date == local_now.to_date
      return opening if local_now < opening
      return local_now if local_now.hour < 17

      date = next_weekday(date + 1.day)
      opening = zone.local(date.year, date.month, date.day, 9)
    end

    opening
  end

  private
    def time_zone_must_be_recognized
      return if time_zone.blank? || configured_time_zone.present?

      errors.add(:time_zone, "is not recognized")
    end

    def next_weekday(date)
      date += 1.day while date.saturday? || date.sunday?
      date
    end
end
