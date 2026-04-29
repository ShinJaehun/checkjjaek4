# Authorization Architecture

## 목적

이 문서는 checkjjaek4의 권한 구조를 정리하기 위한 architecture 문서다.

이 문서는 아래를 설명한다.

- Pundit 기반 권한 구조
- 관계 기준 용어
- 프로필 권한
- Jjaek 권한
- 댓글/좋아요 권한
- 관련 policy 파일 위치

이 문서는 새로운 정책을 정의하지 않는다.
현재 구현은 `docs/architecture/current_system.md`,
목표 상태와 제품 정책은 관련 spec 문서를 기준으로 읽는다.

---

## 권한 구조 개요

checkjjaek4의 서버측 권한 판단은 Pundit policy 중심으로 유지한다.

원칙:

- controller는 가능한 한 `authorize`, `policy_scope`를 호출하는 자리로 남긴다
- 단건 권한 판단은 policy에 둔다
- 목록 조회 범위 판단은 policy scope에 둔다
- view는 가능한 한 controller와 policy에서 정리된 결과를 소비한다

관련 위치:

- `app/policies/application_policy.rb`
- `app/policies/user_policy.rb`
- `app/policies/jjaek_policy.rb`
- `app/policies/bookshelf_entry_policy.rb`
- `app/policies/comment_policy.rb`
- `app/policies/like_policy.rb`
- `app/policies/home_policy.rb`
- `app/policies/book_policy.rb`

---

## 관계 기준 용어

이 문서에서 쓰는 관계 기준 용어는 아래와 같다.

- `self`
  - 현재 사용자와 프로필/콘텐츠 작성자가 같은 경우
- `follow`
  - 현재 사용자가 해당 사용자를 소식받는 관계인 경우
- `book_friend`
  - 책친구 신청/수락이 완료된 경우
- `stranger`
  - `self`, `follow`, `book_friend` 어느 쪽에도 해당하지 않는 경우

---

## 프로필 권한

### 현재 구현

현재 구현 기준 프로필 권한 요약:

- 로그인 사용자는 타인 프로필의 `BookshelfEntry` 목록을 볼 수 있다
- 로그인 사용자는 프로필 Jjaek 섹션을 볼 수 있다
- `stranger / follow`는 `public_jjaek`만 볼 수 있다
- `book_friend`는 `public_jjaek` + `book_friends`를 볼 수 있다
- `self`는 전체 Jjaek을 볼 수 있다
- `self / book_friend`는 프로필 책 목록에서 상태 배지를 볼 수 있다
- `self / book_friend`는 profile-context Jjaek 작성 진입을 사용할 수 있다

### 목표 상태

프로필 목표 규칙은 `docs/specs/social_relationships_mvp.md`를 기준으로 본다.

목표 상태 기준 프로필 Jjaek 조회 권한 요약:

- `stranger`: `public_jjaek`
- `follow`: `public_jjaek`
- `book_friend`: `public_jjaek` + `book_friends`
- `self`: 전체

이 규칙은 Jjaek 조회 범위에 대한 정책이며,
홈 피드 편입 규칙과는 별도로 해석한다.

---

## Jjaek 권한

### 조회

현재 구현 기준:

- `JjaekPolicy#show?`는 현재 사용자가 해당 Jjaek을 볼 수 있는지 판단한다
- quoted Jjaek이 있는 경우 quoted Jjaek도 현재 사용자에게 visible 해야 한다

목표 상태 기준 보완:

- 타인 프로필에서는 `stranger`도 `public_jjaek`을 조회할 수 있어야 한다
- `follow`의 추가 의미는 홈 피드 편입이며,
  프로필 조회 권한 자체는 `stranger`의 `public_jjaek` 조회와 구분한다

관련 위치:

- `app/policies/jjaek_policy.rb`

### 작성

현재 구현 기준:

- 로그인 사용자만 작성 가능하다
- 작성자는 현재 사용자 본인이어야 한다
- 책 문맥 작성은 현재 사용자의 `BookshelfEntry` 존재 여부와 연결된다
- profile-context 작성은 대상 사용자에 대한 권한 규칙을 함께 따른다

관련 위치:

- `app/policies/jjaek_policy.rb`
- `app/policies/user_policy.rb`

### 수정 / 삭제

현재 구현 기준:

- 수정과 삭제는 작성자 본인만 가능하다

관련 위치:

- `app/policies/jjaek_policy.rb`

### ReJjaek 가능 여부

현재 구현 기준:

- 현재 사용자가 원문 Jjaek을 볼 수 있어야 한다
- 원문이 `private_jjaek`이면 ReJjaek할 수 없다
- 원문 자체가 ReJjaek이면 다시 인용할 수 없다

관련 위치:

- `app/policies/jjaek_policy.rb`
- `app/models/jjaek.rb`

---

## FeedScope

현재 구현에는 홈 피드 전용 `JjaekPolicy::FeedScope`가 있다.

현재 구현 기준:

- 홈 피드는 일반 조회 scope와 별도 규칙으로 계산된다
- 내 Jjaek
- 현재 사용자를 대상으로 한 profile-context Jjaek
- 소식받는 사용자의 공개 Jjaek
- 책친구 공개 Jjaek

이 scope는 프로필 조회 권한과 분리해서 읽어야 한다.
특정 사용자의 `public_jjaek`을 프로필에서 볼 수 있다고 해서
그 사용자의 글이 홈 피드에 자동으로 들어오지는 않는다.

관련 위치:

- `app/policies/jjaek_policy.rb`
- `app/controllers/homes_controller.rb`

---

## 댓글 / 좋아요 권한

현재 구현 기준:

- 댓글과 좋아요는 부모 Jjaek을 볼 수 있는 사용자만 가능하다
- 별도 관계 자체보다 부모 Jjaek 접근 가능 여부를 기준으로 판단한다

관련 위치:

- `app/policies/comment_policy.rb`
- `app/policies/like_policy.rb`
- `app/policies/jjaek_policy.rb`
