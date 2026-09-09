class CreateContacts < ActiveRecord::Migration[8.1]
  def change
    create_table :contacts do |t|
      t.references :customer, null: false, foreign_key: true
      t.string :name, null: false
      t.string :phone_number, null: false
      t.string :email
      t.string :role

      t.timestamps
    end
  end
end
