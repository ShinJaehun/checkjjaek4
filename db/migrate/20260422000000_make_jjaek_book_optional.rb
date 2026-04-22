class MakeJjaekBookOptional < ActiveRecord::Migration[8.1]
  def change
    change_column_null :jjaeks, :book_id, true
  end
end
