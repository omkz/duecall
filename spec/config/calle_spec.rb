require "rails_helper"

RSpec.describe "CALL-E configuration" do
  it "loads the overdue invoice Goal ID from CALLE_OVERDUE_INVOICE_GOAL_ID" do
    original_environment_value = ENV["CALLE_OVERDUE_INVOICE_GOAL_ID"]
    original_config_value = Rails.application.config.x.calle.overdue_invoice_goal_id
    ENV["CALLE_OVERDUE_INVOICE_GOAL_ID"] = "goal_from_environment"

    load Rails.root.join("config/initializers/calle.rb")

    expect(Rails.application.config.x.calle.overdue_invoice_goal_id).to eq("goal_from_environment")
  ensure
    if original_environment_value
      ENV["CALLE_OVERDUE_INVOICE_GOAL_ID"] = original_environment_value
    else
      ENV.delete("CALLE_OVERDUE_INVOICE_GOAL_ID")
    end
    Rails.application.config.x.calle.overdue_invoice_goal_id = original_config_value
  end
end
