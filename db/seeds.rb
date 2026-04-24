demo_users_attributes = [
  { name: "신재훈", email: "a@a", password: "password" },
  { name: "해우", email: "b@b", password: "password" },
  { name: "녹우", email: "c@c", password: "password" },
  { name: "혜정", email: "d@d", password: "password" }
].freeze

demo_relationships = [
  [ "a@a", "b@b" ],
  [ "a@a", "c@c" ],
  [ "b@b", "d@d" ],
  [ "c@c", "a@a" ]
].freeze

demo_stickers = [
  [ "loved_it", "좋았어요" ],
  [ "really_loved_it", "너무 좋았어요" ],
  [ "stayed_with_me", "마음에 남아요" ],
  [ "want_to_reread", "다시 읽고 싶어요" ],
  [ "recommended_to_me", "추천받았어요" ],
  [ "want_to_recommend", "추천하고 싶어요" ]
].freeze

demo_books_attributes = [
  {
    isbn: "1111",
    title: "북짹 리부트",
    authors_text: "팀 체크짹",
    publisher: "checkjjaek4"
  }
].freeze

demo_emails = demo_users_attributes.map { |attrs| attrs[:email] }
existing_demo_users = User.where(email: demo_emails)

demo_book_ids =
  BookshelfEntry.where(user_id: existing_demo_users.select(:id)).pluck(:book_id) +
  Jjaek.where(user_id: existing_demo_users.select(:id)).where.not(book_id: nil).pluck(:book_id)

User.transaction do
  existing_demo_users.destroy_all

  Book.where(id: demo_book_ids.uniq).find_each do |book|
    next if book.bookshelf_entries.exists? || book.jjaeks.exists?

    book.destroy!
  end

  users = demo_users_attributes.index_by { |attrs| attrs[:email] }.transform_values do |attrs|
    User.create!(
      name: attrs[:name],
      email: attrs[:email],
      password: attrs[:password],
      password_confirmation: attrs[:password]
    )
  end

  demo_relationships.each do |follower_email, followee_email|
    Follow.create!(follower: users.fetch(follower_email), followee: users.fetch(followee_email))
  end

  demo_stickers.each_with_index do |(key, name), index|
    sticker = StickerDefinition.find_or_initialize_by(key: key)
    sticker.name = name
    sticker.position = index
    sticker.save!
  end

  books = demo_books_attributes.map do |attrs|
    book = Book.find_or_initialize_by(isbn: attrs[:isbn])
    book.assign_attributes(attrs)
    book.save!
    book
  end

  entry_a = BookshelfEntry.create!(user: users.fetch("a@a"), book: books[0], status: :reading)
  entry_a.sticker_definition_ids = StickerDefinition.where(key: %w[loved_it stayed_with_me]).pluck(:id)

  BookFriendship.create!(
    requester: users.fetch("a@a"),
    addressee: users.fetch("b@b"),
    status: :accepted
  )

  jjaek_a = Jjaek.create!(
    user: users.fetch("a@a"),
    book: books[0],
    content: "서재를 먼저 세우고 나니 어떤 글을 남길지 더 분명해졌어요.",
    visibility: :public_jjaek
  )

  Comment.create!(
    user: users.fetch("b@b"),
    jjaek: jjaek_a,
    content: "서재 흐름이 잡히니 글도 더 자연스럽게 이어지겠어요."
  )
end
