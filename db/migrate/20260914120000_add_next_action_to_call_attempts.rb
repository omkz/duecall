class AddNextActionToCallAttempts < ActiveRecord::Migration[8.1]
  def change
    add_column :call_attempts, :next_action, :integer
    add_column :call_attempts, :next_action_on, :date
  end
end
