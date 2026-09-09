module ApplicationHelper
  def format_money(amount_cents, currency)
    major, minor = amount_cents.divmod(100)
    "#{currency} #{number_with_delimiter(major)}.#{minor.to_s.rjust(2, "0")}"
  end
end
