# Legacy Models — checkjjaek3

## 목적

이 문서는 `checkjjaek3`의 레거시 모델 구조를 정리하고,
`checkjjaek4`에서 무엇을 유지하고 무엇을 단순화하거나 버릴지 판단하기 위한 기준 문서다.

원칙:

- 이 문서는 레거시 구조를 그대로 복제하기 위한 문서가 아니다.
- 모델 이름보다 역할과 사용자 흐름을 먼저 본다.
- `checkjjaek4`에서는 최신 Rails 방식과 현재 합의한 구조를 우선한다.
- 특히 레거시의 polymorphic, CanCanCan/Rolify, 구형 프론트엔드 전제를 그대로 가져오지 않는다.

---

## 레거시 핵심 모델 개요

`checkjjaek3`의 스키마와 모델 기준으로 보면, 레거시 핵심 축은 다음과 같다.

### 중심 축
- User
- Group
- UserGroup
- Post
- Comment
- Book

### 부가 축
- Message
- Photo
- Follow
- Like
- Tag
- PostRecipientUser
- PostRecipientGroup

### 권한/역할 축
- Role
- users_roles (join table)

또한 Active Storage가 이미 사용되고 있어,
User avatar, Group cover_image, Photo images 등의 첨부 구조가 존재한다.

---

## 모델별 정리

## 1. User

### 레거시 역할
사용자 계정의 중심 모델이다.

### 레거시 특징
- Devise 기반 인증 사용
- Rolify 사용
- `posts_count` counter cache 보유
- posts, comments, likes, follows, groups와 연결
- avatar 첨부 사용
- 가입 시 기본 role(`standard`) 자동 부여

### 주요 연관
- `has_many :posts`
- `has_many :comments`
- `has_many :likes`
- `has_many :like_posts, through: :likes`
- `has_many :user_groups`
- `has_many :groups, through: :user_groups`
- `has_many :followees`
- `has_many :followers`
- `has_many :post_recipient_users, foreign_key: :recipient_user_id`

### checkjjaek4 판단
유지 대상이다.

다만 아래는 그대로 가져오지 않는다.

- Rolify 기반 role 처리
- 레거시 follow 토글 구현 세부
- 기본 role 자동 부여 방식

`checkjjaek4`에서는 User를 유지하되,
권한은 Pundit 중심으로 다시 정리한다.

---

## 2. Group

### 레거시 역할
사용자들이 모이는 독서/커뮤니티 단위다.

### 레거시 특징
- `name`, `description`, `group_state` 보유
- user_groups를 통해 사용자와 연결
- cover_image 첨부 사용
- Rolify resource 역할도 가짐

### 주요 연관
- `has_many :user_groups`
- `has_many :users, through: :user_groups`
- `has_many :post_recipient_groups, foreign_key: :recipient_group_id`

### checkjjaek4 판단
유지 대상이다.

다만 아래를 다시 검토한다.

- `group_state`가 실제로 필요한 상태인지
- group 상태를 enum으로 둘지 단순 boolean/nullable로 갈지
- Rolify resource 개념을 유지할 필요가 있는지

---

## 3. UserGroup

### 레거시 역할
User와 Group 사이의 가입 관계를 표현하는 join 모델이다.

### 레거시 특징
- `user_id`, `group_id`, `state` 보유
- 현재 모델 자체는 매우 단순함
- 실제 의미는 “멤버십 상태”에 가까움

### checkjjaek4 판단
매우 중요한 유지 대상이다.

다만 `checkjjaek4`에서는
`UserGroup`이라는 레거시 이름을 유지할지,
아예 `Membership` 같은 더 의도가 분명한 이름으로 바꿀지 검토할 가치가 있다.

핵심은 이름보다 아래를 유지하는 것이다.

- 그룹 가입 관계
- 가입/승인 상태
- 그룹 멤버십이 도메인 규칙의 중심이라는 점

---

## 4. Post

### 레거시 역할
실질적인 피드/글의 중심 모델이다.

### 레거시 특징
- `content` 필수, 최대 200자
- `user_id` 보유
- `postable_type`, `postable_id`를 통한 polymorphic 구조
- likes, comments, tags와 연결
- `post_recipient_user`, `post_recipient_group`를 각각 `has_one`으로 가짐
- 본문에서 해시태그를 추출해 Tag와 연결
- `Book`, `Message`, `Photo`가 모두 postable이 될 수 있음

### checkjjaek4 판단
핵심 유지 대상이지만, 구조는 크게 단순화할 가능성이 높다.

초기 방향:
- `postable` polymorphic은 우선 복제하지 않는다.
- `Post` 단일 모델 중심으로 재설계한다.
- 책 연결은 `book_id(optional)` 형태를 우선 검토한다.
- 사진은 Active Storage 첨부로 표현한다.
- 메시지성 글도 별도 `Message` 모델 대신 Post의 대상/공개 범위 개념으로 먼저 검토한다.

즉, `Post`는 유지하되,
레거시의 `postable` 구조는 재검토 대상이다.

---

## 5. Comment

### 레거시 역할
댓글과 대댓글을 담당한다.

### 레거시 특징
- `commentable_type`, `commentable_id` polymorphic
- `user_id`
- `parent_id`
- `belongs_to :parent`, `has_many :replies`
- 본문 최대 200자

### checkjjaek4 판단
유지 대상이다.

다만 아래를 다시 판단한다.

- commentable polymorphic이 정말 필요한가
- 초기에는 Post에만 댓글을 붙이는 구조로 단순화할 수 있는가
- 대댓글은 1단계만 허용할지, 현재처럼 parent/replies 구조를 유지할지

현재 판단으로는
`Comment`는 유지하되,
초기에는 `Post` 전용 댓글로 단순화하는 것도 충분히 가능하다.

---

## 6. Book

### 레거시 역할
책 메타데이터를 저장하는 모델이다.

### 레거시 특징
- `title`, `contents`, `isbn`, `publisher`, `thumbnail`, `authors`, `translators`, `datetime`, `url`
- `has_many :posts, as: :postable`
- `accepts_nested_attributes_for :posts`

### checkjjaek4 판단
유지 대상이다.

다만 레거시처럼 Book이 postable이 되는 구조는 우선 유지하지 않는다.

더 단순한 초기 방향:
- Book은 독립된 메타데이터 모델
- Post가 선택적으로 Book을 참조
- 책 검색 결과를 저장할지, 일부만 저장할지 별도 결정

---

## 7. Message

### 레거시 역할
원래는 사용자 간 메시지 개념을 표현하려 한 모델로 보인다.

### 레거시 특징
- `sender_id`, `receiver_id` 컬럼 존재
- 하지만 sender/receiver association은 주석 처리됨
- 실제로는 `has_many :posts, as: :postable` 구조로 사용됨

### checkjjaek4 판단
초기 이식 대상에서 제외 가능성이 높다.

이유:
- 현재 구조에서는 Message 자체보다 Post가 실질 중심이다.
- Rails 8 재구축에서는 Message를 별도 모델로 두기보다
  Post의 대상/공개 범위 개념으로 먼저 단순화하는 편이 자연스럽다.

즉, Message는 “유지 대상”이라기보다
“레거시에서 나중에 정리해야 할 분리 모델”에 가깝다.

---

## 8. Photo

### 레거시 역할
이미지 묶음을 표현하는 모델이다.

### 레거시 특징
- `has_many :posts, as: :postable`
- `has_many_attached :images`
- jpeg/jpg/png만 허용하는 커스텀 validation 존재

### checkjjaek4 판단
초기에는 별도 모델로 유지하지 않을 가능성이 높다.

대신:
- Post에 이미지 첨부를 붙이는 구조를 우선 검토한다.

Photo가 별도 모델로 다시 필요해지는 경우는,
이미지 자체가 독립 라이프사이클과 규칙을 가질 때다.
초기 재구축에서는 그 단계까지 갈 필요가 없어 보인다.

---

## 9. Follow

### 레거시 역할
User 간 팔로우 관계를 표현한다.

### 레거시 특징
- `followee_id`
- `follower_id`
- 둘 다 User를 가리킴

### checkjjaek4 판단
핵심은 아니지만, 서비스 성격상 충분히 되살릴 가치가 있다.

다만 초기 우선순위는 아니다.
인증, 그룹, 포스트, 댓글, 책 연결이 먼저다.

---

## 10. Like

### 레거시 역할
Post 좋아요를 표현한다.

### 레거시 특징
- `user_id`
- `post_id`

### checkjjaek4 판단
단순하고 이해하기 쉬운 모델이라 나중에 다시 살리기 쉽다.

하지만 초기 핵심 이식 대상은 아니다.

---

## 11. Tag

### 레거시 역할
해시태그/태그 모델이다.

### 레거시 특징
- `has_and_belongs_to_many :posts`
- `posts_tags` join table 사용
- Post가 저장/수정될 때 content에서 해시태그를 추출

### checkjjaek4 판단
후순위 기능이다.

해시태그가 정말 사용자 가치의 핵심인지 다시 확인해야 한다.
초기 재구축에서는 뒤로 미뤄도 된다.

---

## 12. PostRecipientUser / PostRecipientGroup

### 레거시 역할
Post의 수신 대상(user/group)을 분리해서 표현하는 join 모델이다.

### 레거시 특징
- Post는 각각 하나의 `post_recipient_user`, 하나의 `post_recipient_group`을 가질 수 있게 설계됨
- 레거시 코드에는 `has_many` 대신 `has_one`으로 바꾼 이유가 주석으로 남아 있음

### checkjjaek4 판단
이 개념 자체는 중요할 수 있다.

하지만 구현 방식은 다시 봐야 한다.

검토 포인트:
- 정말 user 대상과 group 대상을 별도 join model로 둘지
- Post에 단순한 visibility/target 속성을 둘지
- 향후 Pundit policy와 함께 어떤 구조가 더 읽기 쉬운지

초기에는 단순한 구조를 우선 검토한다.

---

## 13. Role / users_roles

### 레거시 역할
Rolify 기반 역할 모델이다.

### 레거시 특징
- `roles` 테이블
- `users_roles` 조인 테이블
- Group도 `resourcify` 사용

### checkjjaek4 판단
그대로 가져오지 않는다.

`checkjjaek4`는 CanCanCan + Rolify를 복제하지 않고,
Pundit policy 중심으로 권한을 재설계한다.

필요하다면 User 또는 Membership에 명시적인 역할/상태를 두는 편이 낫다.

---

## 모델 분류 요약

## 그대로 유지할 가능성이 높은 축
- User
- Group
- Membership 성격의 UserGroup
- Post
- Comment
- Book

## 구조를 단순화해서 가져올 가능성이 높은 축
- Post
- Comment
- Book 연결 방식
- Post 대상/공개 범위 구조

## 초기에 제외하거나 뒤로 미룰 가능성이 높은 축
- Message
- Photo
- Follow
- Like
- Tag
- Rolify role 구조

---

## checkjjaek4 기준 현재 잠정 방향

### 권장 초기 모델 축
- User
- Group
- Membership
- Book
- Post
- Comment

### 권장 초기 제외
- Message
- Photo
- Follow
- Like
- Tag
- Role

### 이유
초기 재구축 목표는
“레거시의 모든 개념을 되살리는 것”이 아니라,
핵심 사용자 흐름을 최신 Rails 구조에서 다시 작동시키는 것이기 때문이다.

---

## 다음에 이어서 볼 문서

이 문서 다음에는 아래 문서를 이어서 본다.

- `docs/legacy/features.md`
- `docs/migration/plan.md`

이후 실제 구현이 시작되면,
`docs/specs/*.md`와 `docs/architecture/*.md`가 더 중요한 기준이 된다.

