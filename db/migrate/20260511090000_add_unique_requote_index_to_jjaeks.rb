class AddUniqueRequoteIndexToJjaeks < ActiveRecord::Migration[8.1]
  def change
    add_index :jjaeks,
              [ :user_id, :quoted_jjaek_id ],
              unique: true,
              where: "quoted_jjaek_id IS NOT NULL",
              name: "index_jjaeks_on_user_id_and_quoted_jjaek_id_unique"
  end
end
