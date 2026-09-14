class Contact < ApplicationRecord
  E164_FORMAT = /\A\+[1-9]\d{1,14}\z/

  belongs_to :customer
  has_many :call_attempts, dependent: :restrict_with_error

  validates :name, presence: true
  validates :phone_number, presence: true
  validates :phone_number, format: { with: E164_FORMAT, allow_blank: true }
  validates :email, format: { with: URI::MailTo::EMAIL_REGEXP }, allow_blank: true
  validates :business_hours_start, :business_hours_end, presence: true
  validate :time_zone_must_be_recognized
  validate :business_hours_end_must_be_after_start

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
    opening = local_business_time(zone, date, business_hours_start)

    if date == local_now.to_date
      return opening if local_now < opening

      closing = local_business_time(zone, date, business_hours_end)
      return local_now if local_now < closing

      date = next_weekday(date + 1.day)
      opening = local_business_time(zone, date, business_hours_start)
    end

    opening
  end

  private
    def time_zone_must_be_recognized
      return if time_zone.blank? || configured_time_zone.present?

      errors.add(:time_zone, "is not recognized")
    end

    def business_hours_end_must_be_after_start
      return if business_hours_start.blank? || business_hours_end.blank?
      return if business_hours_end.seconds_since_midnight > business_hours_start.seconds_since_midnight

      errors.add(:business_hours_end, "must be after business hours start")
    end

    def local_business_time(zone, date, time)
      zone.local(date.year, date.month, date.day, time.hour, time.min, time.sec)
    end

    def next_weekday(date)
      date += 1.day while date.saturday? || date.sunday?
      date
    end
end
