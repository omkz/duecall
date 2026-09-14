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
  validate :preferred_call_time_must_be_within_business_hours

  def configured_time_zone
    ActiveSupport::TimeZone[time_zone] if time_zone.present?
  rescue TZInfo::InvalidTimezoneIdentifier
    nil
  end

  def next_business_opening(on_or_after:, now: Time.current)
    zone = configured_time_zone
    return unless zone

    return next_preferred_call_time(zone, on_or_after:, now:) if preferred_call_time.present?

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

    def preferred_call_time_must_be_within_business_hours
      return if preferred_call_time.blank? || business_hours_start.blank? || business_hours_end.blank?

      preferred_seconds = preferred_call_time.seconds_since_midnight
      return if preferred_seconds >= business_hours_start.seconds_since_midnight &&
        preferred_seconds < business_hours_end.seconds_since_midnight

      errors.add(
        :preferred_call_time,
        "must be at or after business hours start and before business hours end"
      )
    end

    def next_preferred_call_time(zone, on_or_after:, now:)
      local_now = now.in_time_zone(zone)
      date = next_weekday([ on_or_after, local_now.to_date ].max)
      preferred_time = local_business_time(zone, date, preferred_call_time)

      return preferred_time if date > local_now.to_date || local_now < preferred_time

      date = next_weekday(date + 1.day)
      local_business_time(zone, date, preferred_call_time)
    end

    def local_business_time(zone, date, time)
      zone.local(date.year, date.month, date.day, time.hour, time.min, time.sec)
    end

    def next_weekday(date)
      date += 1.day while date.saturday? || date.sunday?
      date
    end
end
