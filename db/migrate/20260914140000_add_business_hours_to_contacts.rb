class AddBusinessHoursToContacts < ActiveRecord::Migration[8.1]
  def change
    add_column :contacts, :business_hours_start, :time, default: "09:00:00", null: false
    add_column :contacts, :business_hours_end, :time, default: "17:00:00", null: false
  end
end
