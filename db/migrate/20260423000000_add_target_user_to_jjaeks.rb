class AddTargetUserToJjaeks < ActiveRecord::Migration[8.1]
  def change
    add_reference :jjaeks, :target_user, foreign_key: { to_table: :users }
  end
end
