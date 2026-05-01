# Checkjjaek4 Reboot Plan

## 목적

이 문서는 checkjjaek4 리부트 작업 중
아직 남아 있는 구현 계획을 정리하기 위한 문서다.

이 작업은 새 repo를 만드는 작업이 아니다.
같은 repo에서 새 브랜치로 진행하는 **도메인 리부트** 작업이다.

이 문서의 각 항목은 아래 상태 표시와 함께 읽는다.

- `완료`: 현재 구현에 반영된 항목
- `부분 완료`: 핵심 흐름은 동작하지만, spec 기준과 차이가 있어 추가 정리가 필요한 항목
- `계획`: 아직 구현되지 않았거나 후속 단계로 남아 있는 항목

---

## 현재 상태 요약

현재 checkjjaek4는 더 이상 초기의 post 중심 상태를 그대로 유지하지 않는다.
핵심 도메인과 주요 화면은 이미 Jjaek / Book / BookshelfEntry / Relationship 중심으로 상당 부분 옮겨와 있다.

현재 구현 요약은 `docs/architecture/current_system.md`를 우선 기준으로 본다.

이 문서는 현재 구현 설명을 반복하기보다,
남은 리부트 작업과 미완료 항목을 정리하는 데 집중한다.

---

## 구현 상태 요약

### 핵심 도메인 도입 `완료`

- `Book`
- `BookshelfEntry`
- `StickerDefinition`
- `BookshelfEntrySticker`
- `Jjaek`
- `BookFriendship`

### 관계 의미 전환 `완료`

- `Follow`는 피드 구독 관계로 유지
- `BookFriendship`은 신청/수락 기반 신뢰 관계로 분리
- `/relationships` 관계 허브 구현

### 홈 / 책 / 프로필의 Jjaek 흐름 `완료`

- 홈은 `JjaekPolicy::FeedScope` 기반 Jjaek 피드로 동작한다
- 책 화면은 visible Jjaek과 책짹 작성 컨텍스트를 가진다
- 프로필 화면은 관계에 따라 BookshelfEntry / Jjaek / profile-context 작성 진입이 달라진다
- 프로필 Jjaek 읽기 범위는 현재 정책 기준으로 반영되었다

### 책 검색 `완료`

- `book_searches#show`
- `BookSearches::SearchService`
- `BookSearches::KakaoAdapter`
- 검색 결과 기반 책 상세 진입과 import 흐름

### 댓글 / 좋아요 / ReJjaek 핵심 규칙 `완료`

- 상세 정책은 `docs/architecture/authorization.md`와
  `docs/architecture/visibility.md`를 본다

---

## 남은 작업 계획

### 1. Notification 진입점 `완료`

`Notification` 모델 기반 알림 inbox와 navbar unread count가 구현되었다.
받은 책친구 요청은 `book_friendship_requested` action으로 통합되며,
관계 요청 처리는 여전히 `/relationships`에서 담당한다.

현재 MVP 범위:
- 받은 책친구 요청
- profile-context Jjaek
- 댓글
- ReJjaek

관련 문서:
- `docs/specs/notifications_mvp.md`

후속 후보:
- 알림 목록 pagination
- 삭제된 notifiable 알림 표시 정책
- `comment_created` 알림의 preload/N+1 점검
- 책친구 요청 수락/거절 알림 여부 검토

위 항목은 현재 MVP 범위가 아니며, 실제 사용 후 필요성이 확인되면 별도 spec으로 다룬다.

### 2. BookActivity 도입 `부분 완료`

현재 피드는 Jjaek 중심이다.
BookshelfEntry / BookshelfEntrySticker의 상태 변화를 피드 이벤트로 표현하는
`BookActivity` 모델과 `BookshelfEntry` 변경 기록 기반은 도입되었다.

남은 작업:
- home/profile feed 합성 방식
- BookActivity 노출 UI
- 권한/visibility 적용 방식

관련 문서:
- `docs/specs/book_activity_mvp.md`

### 3. 다중 책장 구조 `계획`

현재 MVP는 사용자당 기본 서재 1개 전제로 동작한다.
여러 책장, 공개/비공개 책장 모델은 아직 구현되지 않았다.

- `Bookshelf`
- `BookshelfMembership`
- 여러 책장
- 책장 공개 범위

### 4. 프로필 책 문맥과 전역 책 문맥 분리 여부 `계획`

현재는 `books/:id` 하나로 책 문맥을 처리한다.
필요하면 후속 단계에서 아래 분리를 검토한다.

- `/books/:id`
- `/users/:user_id/books/:book_id`

### 5. 기존 레거시 Post 흐름 정리 `완료`

레거시 Post 런타임 경로는 정리 완료되었다.
현재 런타임에서 사용하는 Post 잔재는 없으며,
남은 Post 언급은 migration history 및 archive/legacy 문서로 보존한다.

migration squash 전에는 과거 posts/post_id migration을 삭제하지 않는다.
archive/legacy 문서도 현재 판단 기록 보존용으로 유지한다.

---

## 현재 문서에서 다루지 않는 것

- 세부 구현 사실
  - `docs/architecture/current_system.md`
- 권한 구조 / visibility 상세
  - `docs/architecture/authorization.md`
  - `docs/architecture/visibility.md`
- 제품 방향과 도메인 원칙
  - `docs/specs/bookjjaek_reboot_spec.md`
- 관계 세부 규칙
  - `docs/specs/social_relationships_mvp.md`

---

## 한 줄 기준

이 문서는 이미 끝난 리부트 선언을 반복하는 문서가 아니라,
남은 작업을 구분해서 추적하는 계획 문서다.
