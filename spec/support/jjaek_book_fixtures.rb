# Fixture construction uses the final attachment API. Historical metadata is
# explicit so legacy deletion scenarios keep their original meaning.
module JjaekBookFixtures
  def build_jjaek_with_books(user:, books: [], legacy_source_kind: nil, **attributes)
    record = user.jjaeks.build(**attributes, legacy_source_kind:)
    books.compact.each_with_index do |book, position|
      record.jjaek_book_attachments.build(book:, position:,
        visible_on_tombstone: legacy_source_kind == "book" && position.zero?)
    end
    record
  end

  def create_jjaek_with_books(save_method: :save!, **attributes)
    build_jjaek_with_books(**attributes).tap { |record| record.public_send(save_method) }
  end
end

RSpec.configure { |config| config.include JjaekBookFixtures }
