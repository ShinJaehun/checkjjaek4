users = [
  { name: "신재훈", email: "a@a", password: "password" },
  { name: "해우", email: "b@b", password: "password" },
  { name: "녹우", email: "c@c", password: "password" },
  { name: "혜정", email: "d@d", password: "password" }
].index_by { |attrs| attrs[:email] }.transform_values do |attrs|
  user = User.find_or_initialize_by(email: attrs[:email])
  user.name = attrs[:name]
  user.password = attrs[:password]
  user.password_confirmation = attrs[:password]
  user.save!
  user
end

relationships = [
  [ users["a@a"], users["b@b"] ],
  [ users["a@a"], users["c@c"] ],
  [ users["b@b"], users["d@d"] ],
  [ users["c@c"], users["a@a"] ]
]

relationships.each do |follower, followee|
  Follow.find_or_create_by!(follower: follower, followee: followee)
end

stickers = [
  [ "loved_it", "좋았어요" ],
  [ "really_loved_it", "너무 좋았어요" ],
  [ "stayed_with_me", "마음에 남아요" ],
  [ "want_to_reread", "다시 읽고 싶어요" ],
  [ "recommended_to_me", "추천받았어요" ],
  [ "want_to_recommend", "추천하고 싶어요" ]
]

stickers.each_with_index do |(key, name), index|
  StickerDefinition.find_or_create_by!(key:) do |sticker|
    sticker.name = name
    sticker.position = index
  end
end

books = [
  {
    isbn: "1111",
    title: "북짹 리부트",
    authors_text: "팀 체크짹",
    publisher: "checkjjaek4"
  }
].map do |attrs|
  Book.find_or_create_by!(isbn: attrs[:isbn]) do |book|
    book.title = attrs[:title]
    book.authors_text = attrs[:authors_text]
    book.publisher = attrs[:publisher]
  end
end

entry_a = BookshelfEntry.find_or_create_by!(user: users["a@a"], book: books[0]) do |entry|
  entry.status = :reading
end

entry_a.sticker_definition_ids = StickerDefinition.where(key: %w[loved_it stayed_with_me]).pluck(:id)

BookFriendship.find_or_create_by!(requester: users["a@a"], addressee: users["b@b"]) do |friendship|
  friendship.status = :accepted
end

jjaek_a = Jjaek.find_or_create_by!(user: users["a@a"], book: books[0], content: "서재를 먼저 세우고 나니 어떤 글을 남길지 더 분명해졌어요.") do |jjaek|
  jjaek.visibility = :public_jjaek
end

Comment.find_or_create_by!(
  user: users["b@b"],
  jjaek: jjaek_a,
  content: "서재 흐름이 잡히니 글도 더 자연스럽게 이어지겠어요."
)
