# Historical rows may own a book; the new creation contract forbids it.
# Keep existing reading/visibility/deletion scenarios using historical data.
module LegacyBookRequotes
  def create_legacy_book_requote(user:, book:, **attributes)
    quote = user.jjaeks.create!(**attributes)
    quote.update_columns(legacy_source_kind: "book")
    JjaekBookAttachment.insert_all!([ { jjaek_id: quote.id, book_id: book.id, position: 0, visible_on_tombstone: true } ])
    quote.reload
  end
end

RSpec.configure { |config| config.include LegacyBookRequotes }
