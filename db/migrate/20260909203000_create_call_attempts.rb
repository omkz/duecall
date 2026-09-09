class CreateCallAttempts < ActiveRecord::Migration[8.1]
  def change
    create_table :call_attempts do |t|
      t.references :invoice, null: false, foreign_key: true
      t.references :contact, null: false, foreign_key: true
      t.string :provider_call_id
      t.integer :status, null: false, default: 0
      t.integer :outcome
      t.text :reason
      t.date :promise_to_pay_on
      t.string :sentiment
      t.text :summary
      t.text :transcript
      t.jsonb :raw_result, null: false, default: {}
      t.datetime :started_at
      t.datetime :completed_at

      t.timestamps
    end
  end
end
