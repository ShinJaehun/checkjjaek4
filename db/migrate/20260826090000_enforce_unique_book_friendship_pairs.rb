class EnforceUniqueBookFriendshipPairs < ActiveRecord::Migration[8.1]
  DIRECTIONAL_INDEX = "index_book_friendships_on_requester_id_and_addressee_id"
  PAIR_INDEX = "index_book_friendships_on_unordered_pair"

  def up
    add_index :book_friendships,
              "LEAST(requester_id, addressee_id), GREATEST(requester_id, addressee_id)",
              unique: true,
              name: PAIR_INDEX
    remove_index :book_friendships, name: DIRECTIONAL_INDEX
  end

  def down
    add_index :book_friendships,
              [ :requester_id, :addressee_id ],
              unique: true,
              name: DIRECTIONAL_INDEX
    remove_index :book_friendships, name: PAIR_INDEX
  end
end
