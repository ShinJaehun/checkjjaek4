class ScopeRequoteUniquenessToDestination < ActiveRecord::Migration[8.1]
  def up
    add_index :jjaeks, [ :user_id, :quoted_jjaek_id ],
              unique: true,
              where: "quoted_jjaek_id IS NOT NULL AND group_id IS NULL",
              name: "index_jjaeks_on_personal_requote_unique"
    add_index :jjaeks, [ :user_id, :quoted_jjaek_id, :group_id ],
              unique: true,
              where: "quoted_jjaek_id IS NOT NULL AND group_id IS NOT NULL",
              name: "index_jjaeks_on_group_requote_unique"

    remove_index :jjaeks, name: "index_jjaeks_on_user_id_and_quoted_jjaek_id_unique"
  end

  def down
    add_index :jjaeks, [ :user_id, :quoted_jjaek_id ],
              unique: true,
              where: "quoted_jjaek_id IS NOT NULL",
              name: "index_jjaeks_on_user_id_and_quoted_jjaek_id_unique"

    remove_index :jjaeks, name: "index_jjaeks_on_group_requote_unique"
    remove_index :jjaeks, name: "index_jjaeks_on_personal_requote_unique"
  end
end
