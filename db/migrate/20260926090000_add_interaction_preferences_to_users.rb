class AddInteractionPreferencesToUsers < ActiveRecord::Migration[8.1]
  def change
    add_column :users, :accepts_book_friend_requests, :boolean, default: true, null: false
    add_column :users, :accepts_group_invitations, :boolean, default: true, null: false
    add_column :users, :allows_new_followers, :boolean, default: true, null: false
  end
end
