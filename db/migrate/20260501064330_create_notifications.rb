class CreateNotifications < ActiveRecord::Migration[8.1]
  def up
    create_table :notifications do |t|
      t.references :recipient, null: false, foreign_key: { to_table: :users }
      t.references :actor, null: false, foreign_key: { to_table: :users }
      t.integer :action, null: false
      t.references :notifiable, polymorphic: true, null: false
      t.datetime :read_at

      t.timestamps
    end

    add_index :notifications,
              [ :recipient_id, :actor_id, :action, :notifiable_type, :notifiable_id ],
              unique: true,
              name: "index_notifications_on_unique_event"
    add_index :notifications, [ :recipient_id, :read_at, :created_at ]

    backfill_pending_book_friendship_notifications
  end

  def down
    drop_table :notifications
  end

  private

  def backfill_pending_book_friendship_notifications
    book_friendship_class = Class.new(ActiveRecord::Base) do
      self.table_name = "book_friendships"
    end
    notification_class = Class.new(ActiveRecord::Base) do
      self.table_name = "notifications"
    end

    now = Time.current
    rows = book_friendship_class.where(status: 0).find_each.map do |book_friendship|
      {
        recipient_id: book_friendship.addressee_id,
        actor_id: book_friendship.requester_id,
        action: 0,
        notifiable_type: "BookFriendship",
        notifiable_id: book_friendship.id,
        created_at: now,
        updated_at: now
      }
    end

    notification_class.insert_all(rows, unique_by: "index_notifications_on_unique_event") if rows.any?
  end
end
