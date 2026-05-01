# Notifications MVP

## 목적

이 문서는 checkjjaek4에서 `Notification` 모델을 도입한 이후의
통합 알림 기준을 정리한다.

이 문서는 Notification의 canonical spec이다.
기존에는 `BookFriendship.pending` 기반 badge로 관계 요청 알림을 처리했지만,
Notification 모델 도입 후에는 `book_friendship_requested` action으로 통합한다.

---

## Notification의 역할

`Notification`은 사용자의 알림 inbox와 읽음 상태를 담당한다.

`Notification`은 각 도메인 객체의 source of truth를 대체하지 않는다.

- `BookFriendship`은 관계 요청과 수락/거절 상태의 source of truth다.
- `Jjaek`은 사용자가 남긴 글과 ReJjaek 문맥의 source of truth다.
- `Comment`는 Jjaek 댓글의 source of truth다.

즉, Notification은 "사용자가 확인해야 할 일"의 진입점이며,
도메인 상태 자체를 저장하거나 판정하는 모델이 아니다.

---

## 기존 관계 요청 알림과의 관계

기존 받은 책친구 요청 badge는
`BookFriendship.pending` 데이터를 직접 세는 초기 MVP였다.

`Notification` 모델 도입 후에는 받은 책친구 요청도
`Notification`으로 생성한다.

다만 두 상태는 분리한다.

- 알림을 읽음 처리해도 `BookFriendship`의 `pending` 상태는 바뀌지 않는다.
- 책친구 요청 수락/거절은 여전히 `/relationships`에서 처리한다.
- 관계 요청 처리 권한은 기존 `BookFriendshipPolicy`와 controller 흐름을 따른다.

---

## 초기 action 범위

초기 `Notification` MVP는 아래 네 가지 action만 다룬다.

- `book_friendship_requested`
- `profile_jjaek_created`
- `comment_created`
- `requote_created`

좋아요, follow, feed성 활동은 이 범위에 포함하지 않는다.

---

## notifiable 매핑

각 action의 `notifiable`은 아래처럼 둔다.

- `book_friendship_requested` -> `BookFriendship`
- `profile_jjaek_created` -> `Jjaek`
- `comment_created` -> `Comment`
- `requote_created` -> `Jjaek`

`requote_created`의 notifiable은 새로 생성된 ReJjaek이다.
원문 Jjaek이 아니다.

---

## 제외 범위

이번 MVP에서 하지 않는다.

- 좋아요 알림
- follow 알림
- 일반 책짹 작성 알림
- 책 서재 추가 알림
- 책 상태/스티커 변경 알림
- `BookActivity`
- 실시간 ActionCable
- 이메일 알림
- 푸시 알림

---

## 읽음 처리

`Notification`은 `read_at`을 가진다.

- `read_at`이 `nil`이면 unread다.
- `read_at`이 있으면 read다.

기본 후보는 `/notifications` 목록에 들어가면
현재 사용자의 unread 알림을 읽음 처리하는 방식이다.

관계 요청 알림의 `read_at`과 `BookFriendship.pending`은 별개다.
알림을 읽어도 관계 요청은 pending으로 남고,
사용자는 `/relationships`에서 수락하거나 거절해야 한다.

---

## 클릭 / 이동 경로

알림 항목 클릭 시 이동 경로는 아래처럼 둔다.

- `book_friendship_requested`
  - `/relationships#received-book-friend-requests`
- `profile_jjaek_created`
  - 생성된 Jjaek 상세
- `comment_created`
  - 댓글이 달린 Jjaek 상세
- `requote_created`
  - 생성된 ReJjaek 상세

알림 목록은 처리 화면이 아니라 진입점이다.
관계 요청 처리는 `/relationships`,
Jjaek / Comment / ReJjaek 확인은 관련 Jjaek 상세에서 한다.

---

## 생성 조건

알림은 self-action에 대해 생성하지 않는다.

- 내가 내 프로필에 남긴 Jjaek은 알림을 만들지 않는다.
- 내가 내 Jjaek에 단 댓글은 알림을 만들지 않는다.
- 내가 내 글을 ReJjaek한 경우 알림을 만들지 않는다.

각 action별 생성 조건:

- `book_friendship_requested`
  - 책친구 요청 수신자에게만 생성한다.
- `profile_jjaek_created`
  - `target_user`가 있고, 작성자와 `target_user`가 다를 때 생성한다.
- `comment_created`
  - 댓글이 달린 Jjaek의 작성자에게 생성한다.
  - 댓글 작성자와 Jjaek 작성자가 같으면 생성하지 않는다.
- `requote_created`
  - 원문 Jjaek 작성자에게 생성한다.
  - ReJjaek 작성자와 원문 작성자가 같으면 생성하지 않는다.
  - 수신자가 볼 수 없는 private/book_friends ReJjaek은 알림으로 누설하지 않는다.

---

## 중복 방지

같은 이벤트에 대한 중복 알림은 만들지 않는다.

기본 후보:

- `recipient`
- `actor`
- `action`
- `notifiable`

위 조합을 기준으로 중복 생성을 막는다.

동일 사용자가 같은 Jjaek에 여러 댓글을 남기는 경우에는
각 댓글이 별도 `Comment`이므로 별도 알림으로 볼 수 있다.

---

## 기존 관계 badge MVP와의 관계

초기 구현은 별도 `Notification` 모델 없이
`BookFriendship.pending`을 직접 세어 받은 책친구 요청 badge를 표시했다.

이 문서는 Notification 모델 도입 이후의 통합 기준이다.
받은 책친구 요청, profile-context Jjaek, 댓글, ReJjaek 알림을 함께 다룬다.

구현이 완료되면 현재 시스템 설명은
`docs/architecture/current_system.md`에 최소 반영한다.

---

## 구현 전 테스트 기준

### Model spec

- `Notification`은 `recipient`, `actor`, `action`, `notifiable`이 필요하다.
- `read_at`이 `nil`이면 unread로 판정한다.
- unread scope가 unread 알림만 반환한다.
- recent scope가 최신 알림부터 반환한다.

### Request spec

- 책친구 요청 생성 시 notification이 생성된다.
- profile-context Jjaek 생성 시 notification이 생성된다.
- comment 생성 시 notification이 생성된다.
- ReJjaek 생성 시 notification이 생성된다.
- self-action은 notification을 생성하지 않는다.
- navbar에 unread notification count가 표시된다.
- `/notifications`에서 현재 사용자의 알림 목록을 볼 수 있다.
- `/notifications` 목록 진입 시 unread 알림이 read 처리된다.
- `/notifications`에서 책친구 요청 알림을 read 처리해도 `BookFriendship`은 pending 상태로 남는다.
- 각 알림 링크가 올바른 목적지로 이동한다.
