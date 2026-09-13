class AddTimeZoneToContacts < ActiveRecord::Migration[8.1]
  def change
    add_column :contacts, :time_zone, :string
  end
end
