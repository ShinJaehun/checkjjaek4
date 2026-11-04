class AddRecommendationsToJjaeks < ActiveRecord::Migration[8.1]
  def change
    add_column :jjaeks, :recommendation, :boolean, default: false, null: false
    add_check_constraint :jjaeks,
      "NOT recommendation OR (book_id IS NULL AND quoted_jjaek_id IS NULL AND quoted_source_deleted_at IS NULL AND target_user_id IS NULL)",
      name: "jjaek_recommendation_context"

    create_table :jjaek_recommendations do |t|
      t.references :jjaek, null: false, foreign_key: true
      t.references :book, null: false, foreign_key: true
      t.integer :position, null: false
      t.timestamps
    end
    add_index :jjaek_recommendations, %i[jjaek_id book_id], unique: true
    add_index :jjaek_recommendations, %i[jjaek_id position], unique: true
    add_check_constraint :jjaek_recommendations, "position >= 0", name: "jjaek_recommendation_position"
  end
end
