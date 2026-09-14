class AddPreferredCallTimeToContacts < ActiveRecord::Migration[8.1]
  def change
    add_column :contacts, :preferred_call_time, :time
  end
end
