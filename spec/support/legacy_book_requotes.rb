# Historical rows may own a book; the new creation contract forbids it.
# Keep existing reading/visibility/deletion scenarios using historical data.
module LegacyBookRequotes
  def create_legacy_book_requote(user:, book:, **attributes)
    quote = user.jjaeks.create!(**attributes)
    quote.update_columns(book_id: book.id)
    JjaekRecommendation.insert_all!([{ jjaek_id: quote.id, book_id: book.id, position: 0 }])
    quote.reload
  end
end

RSpec.configure { |config| config.include LegacyBookRequotes }
