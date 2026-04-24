# Social Relationships MVP

## 목적

이 문서는 checkjjaek4의 관계 모델과 관계 기반 화면 규칙을
초기 MVP 범위에서 명확히 고정하기 위한 기준 문서다.

이 문서는 아래를 다룬다.

- `Follow`와 `BookFriendship`의 역할 구분
- Relationship Page의 역할
- 관계 관련 Notification 진입점
- 댓글 visibility 정책
- 관계 없는 사용자의 공개 `Jjaek` 노출 원칙

관계 관련 세부 규칙은 이 문서를 우선 기준으로 본다.

---

## 핵심 관계

### Follow

의미:
- 이 사람의 공개 짹 흐름을 내 피드에서 받고 싶다.

특징:
- 단방향 관계다.
- 공개 `Jjaek` 소비와 피드 구독의 기준이다.
- `BookFriendship`과는 독립 관계다.
- Follow를 해제해도 `BookFriendship`은 해제되지 않는다.

### BookFriendship

의미:
- 신청/수락을 통해 성립하는 신뢰 관계다.

특징:
- 양방향 신뢰 관계로 해석한다.
- `book_friends` visibility 접근의 기준이다.
- `Follow`와는 독립 관계다.
- `BookFriendship`을 해제해도 기존 `Follow`는 해제되지 않는다.
- 책친구 수락 시 자동 `Follow`는 MVP에서 하지 않는다.

---

## Relationship Page

MVP에서는 `/relationships`를 관계 관리 허브로 둔다.

이 화면은 아래를 관리하는 주 화면이다.

- 받은 책친구 요청
- 보낸 책친구 요청
- 책친구 목록
- 내가 소식받는 사람
- 나를 소식받는 사람

원칙:
- 프로필 화면은 관계 상태 확인과 관계 액션의 보조 경로로 남길 수 있다.
- 하지만 관계 목록과 요청 처리의 중심 화면은 `/relationships`다.

---

## Notification 진입점

초기 MVP의 관계 관련 Notification은 직접 처리 화면이 아니라
`/relationships`의 특정 섹션으로 이동시키는 진입점으로 둔다.

예:
- 받은 책친구 요청 알림 → `/relationships#received-book-friend-requests`
- 보낸 책친구 요청 상태 알림 → `/relationships#sent-book-friend-requests`
- 책친구 수락 알림 → `/relationships#book-friends`

원칙:
- Notification은 관계 상태 변화의 진입점이다.
- 실제 관계 조회/처리의 주 화면은 `/relationships`다.
- 실제 권한 판단은 계속 policy와 관계 모델이 담당한다.
- `Follow` 알림은 초기 MVP 필수 범위로 두지 않는다.

---

## Comment Visibility 정책

댓글은 부모 `Jjaek` visibility를 상속한다.

원칙:
- 댓글은 별도 독립 공개 범위를 두지 않는다.
- 댓글의 읽기/작성 가능 범위는 부모 `Jjaek` visibility를 넘을 수 없다.
- 기준은 댓글 작성자와 조회자 사이의 별도 관계가 아니라,
  **조회자가 부모 `Jjaek`을 볼 수 있는가**다.
- 부모 `Jjaek` 접근 권한이 사라지면 댓글도 함께 비노출된다.
- ReJjaek의 quoted block에 달린 별도 댓글 모델은 도입하지 않는다.

예시:
- `public_jjaek`: 로그인 사용자가 댓글 가능
- `book_friends`: 부모 `Jjaek`을 볼 수 있는 책친구만 댓글 가능
- `private_jjaek`: 작성자만 댓글 가능

---

## 공개 Jjaek 노출 원칙

관계 없는 사용자는 프로필/책 상세에서 다른 사람의 `public_jjaek`을 볼 수 있다.

다만 원칙:
- 관계 없는 사용자의 `public_jjaek`이 홈 피드에 자동으로 들어오지는 않는다.
- 홈 피드 편입 기준은 `Follow`, `BookFriendship`, 그리고 명시된 피드 규칙이다.
- 즉, 화면별 읽기 가능 범위와 홈 피드 편입 기준은 구분한다.

---

## 책 문맥의 두 가지 접근

책은 서비스 안에서 공용 리소스다.
다만 사용자가 어떤 경로로 들어왔는지에 따라 화면 의미는 달라질 수 있다.

### 프로필에서 책으로 들어가는 경우

`A 프로필 → A의 책 클릭` 흐름은
**A가 그 책에 대해 남긴 활동을 보는 사용자 문맥**으로 해석한다.

이 문맥에서의 원칙:
- 관계 없는 사용자 `C`는 `A`가 해당 책에 남긴 `public_jjaek`만 볼 수 있다.
- `C`가 `A`의 책친구라면 `A`가 해당 책에 남긴 `book_friends` Jjaek까지 볼 수 있다.
- `A` 본인은 자신이 해당 책에 남긴 모든 Jjaek을 볼 수 있다.

즉, 같은 책이라도 이 문맥에서는
"이 책 자체"보다 "A가 이 책에 남긴 기록"이 우선이다.

### 전역 책 상세로 들어가는 경우

`책 검색 → 책 상세` 또는 전역 링크에서 `books/:id`로 들어간 경우는
**이 책에 대한 여러 사용자의 공개 활동을 보는 전역 책 문맥**으로 해석한다.

이 문맥에서의 원칙:
- 전역 책 상세는 특정 한 사람의 기록 화면이 아니다.
- viewer 기준 `policy_scope`를 통과한 여러 사용자의 Jjaek을 볼 수 있다.
- 따라서 화면의 기준은 "누가 이 책에 대해 무엇을 남겼는가"이지,
  특정 프로필 주인 한 명이 아니다.

### 후속 확장 가능성

MVP에서는 이 두 의미를 우선 `books/:id` 하나로 처리할 수 있다.

다만 화면 의미가 혼동되면 후속 단계에서는 아래처럼 URL을 분리할 수 있다.

- `/books/:id`
  - 책 자체의 전역 상세 화면
- `/users/:user_id/books/:book_id`
  - 특정 사용자의 특정 책 활동 화면

---

## 문서 관계

이 문서는 아래 활성 문서와 함께 읽는다.

- `docs/specs/bookjjaek_reboot_spec.md`
- `docs/reboot/reboot_plan.md`

원칙:
- 제품/도메인 전체 방향은 `bookjjaek_reboot_spec.md`
- 구현 단계와 순서는 `reboot_plan.md`
- 관계/Relationship Page/관계 알림/댓글 visibility 세부 기준은 `social_relationships_mvp.md`
