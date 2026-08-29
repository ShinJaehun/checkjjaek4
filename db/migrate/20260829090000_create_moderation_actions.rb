class CreateModerationActions < ActiveRecord::Migration[8.1]
  def change
    create_table :moderation_actions do |t|
      t.references :target, polymorphic: true, null: false, index: false
      t.references :actor, null: false, foreign_key: { to_table: :users }
      t.integer :action_type, null: false
      t.text :public_reason, null: false
      t.text :internal_note
      t.references :reversal_of, index: false, foreign_key: { to_table: :moderation_actions }

      t.timestamps
    end

    add_index :moderation_actions, [ :target_type, :target_id, :created_at ],
              name: "index_moderation_actions_on_target_and_created_at"
    add_index :moderation_actions, :action_type
    add_index :moderation_actions, :reversal_of_id,
              unique: true,
              where: "reversal_of_id IS NOT NULL",
              name: "index_moderation_actions_on_unique_reversal"
  end
end
