class AddGroupApplicationAndClosureDetails < ActiveRecord::Migration[8.1]
  def change
    add_column :groups, :application_purpose, :text
    add_column :groups, :closure_reason, :text
    add_column :groups, :closed_at, :datetime
  end
end
