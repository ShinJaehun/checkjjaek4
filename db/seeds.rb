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

posts = [
  [ users["a@a"], "이번 주는 개인 feed 흐름부터 제대로 올려보는 중입니다. 읽고 쓰는 감각부터 다시 잡아보려 해요." ],
  [ users["b@b"], "주말엔 긴 소설보다 짧은 에세이가 더 잘 읽히는 날이 있더라고요." ],
  [ users["c@c"], "팔로우는 노출 규칙이고, 댓글과 좋아요는 접근 가능한 글에 대한 상호작용이라는 방향이 꽤 자연스럽습니다." ],
  [ users["d@d"], "프로필 페이지에서 공개 글을 훑어보다가 마음에 드는 글에 바로 반응할 수 있는 흐름이 좋네요." ]
].map do |user, content|
  Post.find_or_create_by!(user: user, content: content)
end

Comment.find_or_create_by!(
  user: users["b@b"],
  post: posts[0],
  content: "이 흐름이면 홈 feed랑 프로필 정책이 확실히 구분되겠네요."
)

Comment.find_or_create_by!(
  user: users["a@a"],
  post: posts[2],
  content: "맞아요. 팔로우를 상호작용 권한이 아니라 노출 규칙으로 두는 게 핵심 같아요."
)

Like.find_or_create_by!(user: users["c@c"], post: posts[0])
Like.find_or_create_by!(user: users["d@d"], post: posts[1])
Like.find_or_create_by!(user: users["a@a"], post: posts[3])
