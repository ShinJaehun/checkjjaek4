class AddColorKeyToBookshelves < ActiveRecord::Migration[8.0]
  def change
    add_column :bookshelves, :color_key, :string, null: false, default: "stone"
  end
end
