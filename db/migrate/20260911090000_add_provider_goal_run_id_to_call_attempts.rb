class AddProviderGoalRunIdToCallAttempts < ActiveRecord::Migration[8.1]
  def change
    add_column :call_attempts, :provider_goal_run_id, :string
    add_index :call_attempts, :provider_goal_run_id, unique: true
  end
end
