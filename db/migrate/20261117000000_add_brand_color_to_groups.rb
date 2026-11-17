class AddBrandColorToGroups < ActiveRecord::Migration[8.1]
  def change
    add_column :groups, :brand_color, :string
    add_check_constraint :groups,
      "brand_color IS NULL OR brand_color IN ('stone', 'red', 'orange', 'amber', 'emerald', 'teal', 'blue', 'violet')",
      name: "groups_brand_color_allowed"
  end
end
