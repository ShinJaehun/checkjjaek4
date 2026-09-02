class AddModerationAuthorityToModerationActions < ActiveRecord::Migration[8.1]
  def up
    add_column :moderation_actions, :moderation_authority, :string

    execute <<~SQL.squish
      UPDATE moderation_actions
      SET moderation_authority = 'platform'
      WHERE target_type = 'Jjaek'
        AND action_type IN (1, 2)
    SQL
  end

  def down
    remove_column :moderation_actions, :moderation_authority
  end
end
