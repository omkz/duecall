class AddAutonomousFollowUpEnabledToInvoices < ActiveRecord::Migration[8.1]
  def change
    add_column :invoices, :autonomous_follow_up_enabled, :boolean, default: false, null: false
  end
end
