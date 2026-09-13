class AddParentCallAttemptToCallAttempts < ActiveRecord::Migration[8.1]
  def change
    add_reference :call_attempts, :parent_call_attempt,
      foreign_key: { to_table: :call_attempts },
      index: { unique: true }
  end
end
