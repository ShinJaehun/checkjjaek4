# Social Relationships MVP

## 목적

이 문서는 checkjjaek4의 관계 모델과 관계 기반 화면 규칙을
초기 MVP 범위에서 명확히 고정하기 위한 기준 문서다.

이 문서의 각 규칙은 아래 상태 표시와 함께 읽는다.

- `(현재 구현)`: 현재 코드에 반영되어 있는 규칙
- `(목표 상태)`: 제품 방향상 유지하지만 현재 코드와 완전히 일치하지는 않는 규칙
- `(미구현)`: 문서상 계획으로만 남아 있고 아직 구현되지 않은 규칙

이 문서는 아래를 다룬다.

- `Follow`와 `BookFriendship`의 역할 구분
- Relationship Page의 역할
- 관계 관련 Notification 진입점
- 댓글 visibility 정책
- 관계 없는 사용자의 공개 `Jjaek` 노출 원칙

관계 관련 세부 규칙은 이 문서를 우선 기준으로 본다.

---

## 핵심 관계

### Follow `(현재 구현)`

의미:
- 이 사람의 공개 짹 흐름을 내 피드에서 받고 싶다.

특징:
- 단방향 관계다.
- 공개 `Jjaek` 소비와 피드 구독의 기준이다.
- `BookFriendship`과는 독립 관계다.
- Follow를 해제해도 `BookFriendship`은 해제되지 않는다.

### BookFriendship `(현재 구현)`

의미:
- 신청/수락을 통해 성립하는 신뢰 관계다.

특징:
- 양방향 신뢰 관계로 해석한다.
- 두 사용자 사이에는 pending/accepted를 통틀어 하나의 관계만 존재하며, requester/addressee는 최초 요청 방향을 유지한다.
- `book_friends` visibility 접근의 기준이다.
- `Follow`와는 독립 관계다.
- `BookFriendship`을 해제해도 기존 `Follow`는 해제되지 않는다.
- 책친구 수락 시 자동 `Follow`는 MVP에서 하지 않는다.

---

## Relationship Page `(현재 구현)`

`/account/relationships`는 현재 구현된 관계 관리 허브다.

이 화면은 아래 다섯 관계를 탭으로 관리한다.

- 책친구 (기본 탭)
- 받은 책친구 신청
- 보낸 책친구 신청
- 소식받는 중
- 내 소식 구독자

조회와 표시:
- 각 탭은 검색어와 관계없이 현재 사용자의 해당 관계 전체 인원수를 COUNT 쿼리로 표시한다. 모바일에서는 탭을 가로 스크롤한다.
- `tab`, `q`, `page`를 GET으로 전달하며 선택한 탭의 관계만 DB에서 사용자 이름으로 검색하고 페이지당 24건씩 조회한다. handle은 검색 대상에서 제외한다. 검색 label은 `이름 검색`, placeholder는 `이름으로 검색`이다. SQL wildcard 문자는 escape한다. 전체 관계 ID를 Ruby 배열로 가져와 페이지를 나누지 않는다. 일반 통합 검색(`/search`)의 handle 검색은 유지한다.
- 책친구는 양방향 accepted 관계, 받은/보낸 신청은 해당 방향의 pending 관계, 소식 관계는 기존 Follow를 사용한다. 다른 사용자의 관계는 조회하지 않는다.
- 책친구·소식 관계는 사용자 이름 ASC·사용자 ID ASC, 신청은 생성 시각 DESC·관계 ID DESC로 정렬한다. 잘못된 탭은 책친구, 잘못되거나 1보다 작은 페이지는 1로 정규화하며 마지막 페이지 초과 시 마지막 유효 페이지로 보정한다.
- 검색어 변경은 현재 탭의 첫 페이지로 이동한다. 탭 전환은 검색어를 유지하고 첫 페이지로 이동한다.
- 사용자 카드는 768px 미만에서 1열, 그 이상에서 최대 2열이다. 아바타·이름·공개 handle만 표시하며 긴 이름·handle은 줄바꿈한다. 자기소개와 관계 수는 카드에 표시하지 않는다.
- 책친구 해제, 받은 신청 수락/거절, 보낸 신청 취소, 소식받기 해제는 기존 Pundit과 상태 전이를 유지한다. 내 소식 구독자 카드는 프로필 링크만 제공한다. 프로필의 관계 동작은 유지한다.
- 관계 변경 요청은 현재 `tab`·`q`·`page`를 전달한다. 성공한 Turbo Stream은 탭 건수와 선택 목록·검색·페이지네이션을 담은 `relationships-panel`을 함께 교체하고 flash를 갱신한다. 선택하지 않은 탭의 사용자 목록은 로드하지 않는다.
- HTML fallback은 정규화된 조회 상태로 303 redirect한다. 마지막 항목 제거로 현재 페이지가 사라지면 Turbo 요청도 유효한 페이지로 303 redirect하여 URL과 목록을 일치시킨다. 새 Stimulus나 클라이언트 상태 관리는 추가하지 않는다.
- 기존 공통 pagination partial을 재사용하되 이 화면의 24건 정책이 다른 화면의 페이지 크기를 변경하지 않는다.

원칙:
- 프로필 화면은 관계 상태 확인과 관계 액션의 보조 경로로 남길 수 있다.
- 하지만 관계 목록과 요청 처리의 중심 화면은 `/account/relationships`다.

---

## Notification 진입점 `(현재 구현)`

Notification의 canonical 기준은 `docs/specs/notifications_mvp.md`를 따른다.
이 문서에서는 관계 기능 관점에서 필요한 연결 규칙만 둔다.

현재 구현:
- 받은 책친구 요청은 `book_friendship_requested` notification으로 생성된다.
- 해당 알림은 `/account/relationships?tab=received_book_friend_requests#received-book-friend-requests`로 연결되어 받은 신청 탭을 연다.
- 알림을 읽음 처리해도 `BookFriendship.pending` 상태는 바뀌지 않는다.
- 책친구 요청을 수락하면 원래 신청자에게 `book_friendship_accepted` notification을 생성한다.
- 수락 알림은 수락한 사용자의 이름과 avatar를 표시하고 해당 사용자 프로필로 연결된다.

원칙:
- Notification은 관계 요청 확인의 진입점이다.
- 실제 관계 조회/처리의 주 화면은 `/account/relationships`다.
- 실제 권한 판단은 계속 policy와 관계 모델이 담당한다.
- `Follow` 알림은 초기 MVP 필수 범위로 두지 않는다.

soft rejection 원칙:
- 책친구 요청 거절은 상대방에게 notification을 생성하지 않는다.
- 내가 보낸 책친구 요청 취소도 상대방에게 notification을 생성하지 않는다.
- 책친구 관계 해제는 상대방에게 notification을 생성하지 않는다.
- 소식받기 해제는 상대방에게 notification을 생성하지 않는다.
- 위 이벤트들은 action을 수행한 현재 사용자에게만 flash로 안내한다.

## 계정 탈퇴와 관계 `(현재 구현)`

계정 탈퇴 시 Follow 관계와 BookFriendship 및 pending 요청은 종료한다.
계정 탈퇴는 콘텐츠 일괄 삭제와 같은 동작이 아니며, 상세 기준은
`docs/specs/account_group_lifecycle.md`를 canonical source로 본다.

---

## Comment Visibility 정책 `(현재 구현)`

댓글은 부모 `Jjaek` visibility를 상속한다.

원칙:
- 댓글은 별도 독립 공개 범위를 두지 않는다.
- 댓글의 읽기/작성 가능 범위는 부모 `Jjaek` visibility를 넘을 수 없다.
- 기준은 댓글 작성자와 조회자 사이의 별도 관계가 아니라,
  **조회자가 부모 `Jjaek`을 볼 수 있는가**다.
- 부모 `Jjaek` 접근 권한이 사라지면 댓글도 함께 비노출된다.
- ReJjaek의 quoted block에 달린 별도 댓글 모델은 도입하지 않는다.

현재 구현 상세는 `docs/architecture/authorization.md`와
`docs/architecture/jjaek_visibility.md`를 함께 본다.

---

## 프로필 Jjaek 노출 규칙

### 현재 프로필 구현 `(현재 구현)`

현재 구현 상세는 `docs/architecture/authorization.md`를 본다.

### 프로필 목표 규칙 `(목표 상태)`

타인 프로필의 Jjaek 노출은 아래와 같이 둔다.

- `stranger`: `public_jjaek`만 볼 수 있다
- `follow`: `public_jjaek`을 볼 수 있다
- `book_friend`: `public_jjaek` + `book_friends`를 볼 수 있다
- `self`: 모든 Jjaek을 볼 수 있다

다만 원칙:
- “프로필에서 볼 수 있음”과 “홈 피드에 들어옴”은 다르다.
- 홈에서 `Follow`는 구독 기준이고, accepted `BookFriendship`은 구독한 사람의 `book_friends` Jjaek과 BookActivity에 대한 추가 접근 기준이다.
- 관계 없음 또는 책친구만 있는 사용자의 일반 Jjaek·BookActivity는 홈 피드에 자동으로 들어오지 않는다.
- 소식받기만 하면 상대의 `public_jjaek`이, 소식받기와 accepted 책친구 관계가 모두 있으면 상대의 `public_jjaek`·`book_friends` Jjaek·BookActivity가 들어온다.
- 현재 사용자를 대상으로 한 non-private profile-context Jjaek은 Follow 여부와 관계없이 홈에 들어온다.
- 즉, 화면별 읽기 가능 범위와 홈 피드 편입 기준은 구분한다.

현재 유지하는 별도 규칙:
- 현재 구현 상세는 `docs/architecture/authorization.md`를 본다

---

## 책 상세 Jjaek 노출 규칙

### 현재 책 상세 구현 `(현재 구현)`

현재 구현 상세는 `docs/architecture/authorization.md`와
`docs/architecture/jjaek_visibility.md`를 함께 본다.

### 책 문맥 해석 `(목표 상태)`

책은 서비스 안에서 공용 리소스다.
다만 사용자가 어떤 경로로 들어왔는지에 따라 화면 의미는 달라질 수 있다.

#### 프로필에서 책으로 들어가는 경우 `(목표 상태)`

`A 프로필 → A의 책 클릭` 흐름은
**A가 그 책에 대해 남긴 활동을 보는 사용자 문맥**으로 해석한다.

이 문맥에서의 원칙:
- 관계 없는 사용자 `C`는 `A`가 해당 책에 남긴 `public_jjaek`만 볼 수 있다.
- `C`가 `A`의 책친구라면 `A`가 해당 책에 남긴 `book_friends` Jjaek까지 볼 수 있다.
- `A` 본인은 자신이 해당 책에 남긴 모든 Jjaek을 볼 수 있다.

즉, 같은 책이라도 이 문맥에서는
"이 책 자체"보다 "A가 이 책에 남긴 기록"이 우선이다.

#### 전역 책 상세로 들어가는 경우 `(현재 구현)`

`책 검색 → 책 상세` 또는 전역 링크에서 `books/:id`로 들어간 경우는
**이 책에 대한 여러 사용자의 공개 활동을 보는 전역 책 문맥**으로 해석한다.

이 문맥에서의 원칙:
- 전역 책 상세는 특정 한 사람의 기록 화면이 아니다.
- 따라서 화면의 기준은 "누가 이 책에 대해 무엇을 남겼는가"이지,
  특정 프로필 주인 한 명이 아니다.

현재 구현 상세는 `docs/architecture/authorization.md`와
`docs/architecture/jjaek_visibility.md`를 함께 본다.

#### 후속 확장 가능성 `(미구현)`

현재는 이 두 의미를 `books/:id` 한 화면에서 처리한다.

다만 화면 의미가 혼동되면 후속 단계에서는 아래처럼 URL을 분리할 수 있다.

- `/books/:id`
  - 책 자체의 전역 상세 화면
- `/users/:user_id/books/:book_id`
  - 특정 사용자의 특정 책 활동 화면

---

## 문서 관계

이 문서는 아래 활성 문서와 함께 읽는다.

- `docs/specs/bookjjaek_reboot_spec.md`
- `docs/architecture/current_system.md`

원칙:
- 제품/도메인 전체 방향은 `bookjjaek_reboot_spec.md`
- 현재 구현 사실은 `current_system.md`
- 관계/Relationship Page/관계 알림/댓글 visibility 세부 기준은 `social_relationships_mvp.md`
