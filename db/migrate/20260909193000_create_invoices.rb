class CreateInvoices < ActiveRecord::Migration[8.1]
  def change
    create_table :invoices do |t|
      t.references :customer, null: false, foreign_key: true
      t.string :number, null: false
      t.bigint :amount_cents, null: false
      t.string :currency, null: false, default: "USD"
      t.date :issued_on
      t.date :due_on, null: false
      t.integer :status, null: false, default: 0
      t.string :external_id

      t.timestamps
    end

    add_index :invoices, %i[ customer_id number ], unique: true
  end
end
