class AddGroupToJjaeks < ActiveRecord::Migration[8.1]
  def change
    add_reference :jjaeks, :group, null: true, foreign_key: true
  end
end
