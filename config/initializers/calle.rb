Rails.application.configure do
  config.x.calle.api_key = ENV["CALLE_API_KEY"].presence || credentials.dig(:calle, :api_key)
  config.x.calle.overdue_invoice_goal_id = ENV["CALLE_OVERDUE_INVOICE_GOAL_ID"].presence ||
    credentials.dig(:calle, :overdue_invoice_goal_id)
  config.x.calle.calling_company_name = ENV["DUECALL_CALLING_COMPANY_NAME"].presence ||
    credentials.dig(:calle, :calling_company_name)
  config.x.calle.base_url = ENV.fetch("CALLE_BASE_URL", "https://api.heycall-e.com")
end
