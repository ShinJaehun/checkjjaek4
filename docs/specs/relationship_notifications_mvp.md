# Relationship Notifications MVP

## 목적

이 문서는 checkjjaek4의 관계 관련 Notification MVP 범위를 정의한다.

이 문서는 새 관계 정책을 정의하지 않는다.
관계 정책 자체는 `docs/specs/social_relationships_mvp.md`를 따른다.
현재 구현 상태는 `docs/architecture/current_system.md`를 따른다.

이 문서의 목적은 아래를 좁게 고정하는 것이다.

- 관계 관련 알림의 최소 범위
- 알림이 사용자를 어디로 보내야 하는지
- `/relationships` 허브와의 역할 분담
- 초기 구현에서 하지 않을 것
- 이후 구현 시 필요한 테스트 기준

---

## 배경

현재 checkjjaek4에는 `/relationships` 관계 허브가 있다.

이 화면은 아래 정보를 보여준다.

- 받은 책친구 요청
- 보낸 책친구 요청
- 책친구 목록
- 내가 소식받는 사람
- 나를 소식받는 사람

관계 관련 Notification은 별도 처리 화면을 새로 만들기보다,
이미 있는 `/relationships` 화면의 받은 요청 섹션으로 사용자를 보내는 진입점으로 둔다.

---

## 핵심 원칙

### 1. Notification은 처리 화면이 아니다

Notification 자체에서 관계를 승인하거나 거절하지 않는다.

Notification은 사용자를 관련 관계 화면으로 이동시키는 진입점이다.

예:

- 받은 책친구 요청 알림
  - `/relationships#received-book-friend-requests`

실제 요청 수락, 거절, 삭제, 관계 해제는 기존 관계 controller와 policy가 담당한다.

---

### 2. 초기 MVP는 받은 책친구 요청 알림만 다룬다

초기 Notification MVP 범위는 BookFriendship의 받은 pending 요청 알림으로 제한한다.

포함:

- 받은 책친구 요청이 있음을 알려주는 표시
- 관계 허브의 받은 요청 섹션으로 이동
- 필요하면 책친구 수락 후 관계 허브로 돌아가기

제외:

- Follow 알림
- Like 알림
- Comment 알림
- Jjaek 언급 알림
- 실시간 알림
- 읽음/안 읽음 상태를 가진 범용 Notification 모델
- 이메일 알림
- 브라우저 푸시 알림

---

### 3. 알림의 source of truth는 기존 관계 데이터다

초기 MVP에서는 별도의 `Notification` 모델을 만들지 않는다.

받은 책친구 요청 개수는 기존 `BookFriendship.pending` 데이터를 기준으로 계산한다.

즉:

- 알림 수를 따로 저장하지 않는다.
- 읽음 상태를 따로 저장하지 않는다.
- 관계 요청이 수락/삭제되면 알림도 자연스럽게 사라진 것으로 본다.

이 구조는 단순하고 현재 MVP에 충분하다.

후속 단계에서 여러 종류의 알림이 필요해지면,
그때 별도 `Notification` 모델 도입을 검토한다.

---

## 사용자 시나리오

### 시나리오 1: 받은 책친구 요청이 있는 경우

조건:

- 로그인 사용자에게 pending 상태의 받은 책친구 요청이 있다.

동작:

- 화면 상단 또는 관계 진입 링크 근처에 받은 요청 개수를 표시한다.
- 사용자가 클릭하면 `/relationships#received-book-friend-requests`로 이동한다.
- 실제 수락/거절은 `/relationships` 화면에서 처리한다.

예시 UI 문구:

- `책친구 요청 2`
- `받은 책친구 요청 2개`
- `관계`

최종 문구는 실제 UI 맥락에 맞춰 i18n으로 관리한다.

---

### 시나리오 2: 받은 책친구 요청이 없는 경우

조건:

- 로그인 사용자에게 pending 상태의 받은 책친구 요청이 없다.

동작:

- 알림 배지를 표시하지 않는다.
- 관계 페이지 진입 링크는 일반 상태(`/relationships`)로 유지한다.

---

### 시나리오 3: 책친구 요청을 수락한 경우

조건:

- 사용자가 `/relationships`에서 받은 책친구 요청을 수락한다.

동작:

- 수락 후 `/relationships`로 돌아온다.
- 가능하면 관련 섹션으로 돌아온다.
- pending 요청 개수는 기존 관계 데이터 기준으로 줄어든다.

---

## 초기 UI 범위

초기 MVP에서는 navbar 또는 공통 header에 관계 알림 진입점을 둔다.

권장 형태:

```text
관계
관계 2
책친구 요청 2
```

구체적인 디자인은 중요하지 않다.

중요한 것은 다음이다.

- 받은 책친구 요청이 있으면 사용자가 알아볼 수 있어야 한다.
- 받은 책친구 요청이 있으면 링크가 `/relationships#received-book-friend-requests`를 가리켜야 한다.
- 받은 책친구 요청이 없으면 링크는 일반 상태(`/relationships`)로 유지한다.
- 요청이 없으면 과한 UI를 보여주지 않는다.

---

## 권한 원칙

관계 알림은 현재 로그인 사용자 기준으로만 계산한다.

- guest는 관계 알림을 볼 수 없다.
- 로그인 사용자는 자기에게 온 pending 책친구 요청 개수만 본다.
- 다른 사용자의 요청 개수는 볼 수 없다.

관계 처리 권한은 기존 `BookFriendshipPolicy`와 controller 흐름을 따른다.

---

## 구현 방향

### 1차 구현

별도 모델 없이 시작한다.

예상 구현 위치:

- controller/helper 계층에서 현재 사용자의 받은 pending 요청 수 계산
- layout/navbar에서 알림 배지 표시
- `/relationships` 화면의 받은 요청 섹션에 anchor id 부여 또는 확인
- 관계 요청 수락/삭제 후 return_to 흐름 정리

가능한 helper 이름 예:

- `received_book_friend_requests_count`
- `show_relationship_notification_badge?`

단, 실제 이름은 현재 코드 스타일에 맞춰 정한다.

---

## 테스트 기준

초기 구현 시 아래 테스트를 우선한다.

### request spec

- guest는 관계 알림 UI를 보지 못한다.
- 로그인 사용자는 받은 pending 책친구 요청 개수를 볼 수 있다.
- 다른 사용자의 pending 요청은 개수에 포함되지 않는다.
- pending 요청이 없으면 알림 배지가 표시되지 않는다.
- 알림 링크는 `/relationships#received-book-friend-requests`를 가리킨다.
- `/relationships` 화면에 `received-book-friend-requests` anchor가 존재한다.

### relationship request spec

- 받은 책친구 요청을 수락한 뒤 관계 허브로 돌아갈 수 있다.
- `return_to=relationships` 흐름이 기존 동작과 충돌하지 않는다.

### view/helper spec 여부

초기에는 request spec 중심으로 충분하다.
helper가 복잡해질 경우에만 helper spec을 추가한다.

---

## 비목표

이번 MVP에서 하지 않는다.

- 범용 Notification 모델 생성
- Notification 읽음/안 읽음 상태
- 여러 알림 타입 통합
- 알림 목록 페이지
- 실시간 알림
- ActionCable
- 이메일 알림
- Like / Comment / Follow 알림
- Jjaek mention 알림
- 그룹/교실 알림

---

## 후속 확장 가능성

나중에 알림 종류가 늘어나면 별도 `Notification` 모델을 검토할 수 있다.

후속 후보:

- 책친구 요청 수락 알림
- 댓글 알림
- 좋아요 알림
- ReJjaek 알림
- 그룹 초대 알림
- 교실 활동 알림

다만 이 단계에서는 관계 허브 진입점으로 충분한지 먼저 확인한다.

---

## 한 줄 기준

초기 Notification MVP는 별도 알림 시스템이 아니라,
받은 책친구 요청을 `/relationships`의 적절한 섹션으로 안내하는 가벼운 진입점이다.
