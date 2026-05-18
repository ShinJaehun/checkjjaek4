# Current System Overview

## 목적

이 문서는 checkjjaek4의 현재 구현 상태를 빠르게 파악하기 위한 요약 문서다.

- spec을 대체하지 않는다
- 상세 설계 설명을 반복하지 않는다
- 코드 읽기 전에 전체 구조를 잡기 위한 지도 역할만 한다
- 계획, 목표 상태, 후속 기능은 다루지 않는다

---

## 핵심 도메인

현재 시스템의 핵심 모델:

- User
- Jjaek
- Book
- Bookshelf
- BookshelfEntry
- Follow
- BookFriendship
- Comment
- Like
- Notification
- BookActivity

역할 요약:

- Jjaek: 사용자 콘텐츠 단위
- Book: 외부 검색 기반 도서 데이터
- Bookshelf: 사용자의 책장 단위와 책장 visibility, 기본 책장 여부
- BookshelfEntry: 사용자-책-책장 관계 (상태/스티커)
- BookFriendship: 관계 기반 권한 확장
- Follow: 피드 구독
- Comment: Jjaek에 대한 댓글
- Like: Jjaek에 대한 좋아요
- Notification: 직접 상호작용 알림 inbox와 읽음 상태
- BookActivity: 책 관련 사용자 행동을 피드 이벤트로 기록하기 위한 기반 모델

---

## 주요 화면과 흐름

### 1. 홈 (/)

- `JjaekPolicy::FeedScope` 기반 Jjaek 피드와 `BookActivityPolicy::Scope` 기반 BookActivity 피드를 합성
- 내 Jjaek, 소식받는 사용자의 공개 Jjaek, 책친구 공개 Jjaek,
  현재 사용자 대상 profile-context Jjaek이 함께 섞일 수 있음
- BookActivity는 현재 사용자와 accepted book_friend의 활동만 함께 섞임
- follow-only / stranger의 BookActivity는 홈 피드에 노출하지 않음
- Jjaek과 BookActivity는 `created_at` 기준으로 함께 정렬함

관련 코드:
- controller: app/controllers/homes_controller.rb
- view: app/views/homes/show.html.erb

---

### 2. 책 화면 (/books/:id)

- 책 정보 표시
- viewer 기준 `policy_scope`를 통과한 해당 책의 원본 책짹 목록 표시
- `books/:id`의 책짹 목록에는 ReJjaek을 직접 포함하지 않는다
- 원본 책짹 카드의 visible ReJjaek count는 유지한다
- ReJjaek 목록 조회 기준은 `docs/specs/requotes_mvp.md`를 본다
- 현재 사용자의 `BookshelfEntry`가 있을 때만 책짹 작성 컨텍스트가 열림
- 현재 사용자의 `BookshelfEntry`가 있을 때만 상태/스티커 편집 컨텍스트가 열림
- 현재 사용자의 `BookshelfEntry`가 있을 때 현재 책장 이름을 보여주고, 사용자의 책장이 2개 이상이면 기존 책장 이동 흐름으로 책장을 옮길 수 있음

관련 코드:
- controller: app/controllers/books_controller.rb (show)
- view:
  - app/views/books/show.html.erb
  - app/views/books/_book_header.html.erb
  - app/views/books/_bookshelf_panel.html.erb
  - app/views/books/_timeline.html.erb
  - app/views/books/_jjaek_form_panel.html.erb

---

### 3. 프로필 화면 (/users/:id)

- 관계에 따라 다른 데이터 노출
- 프로필은 항상 공개 요약 화면으로 해석한다
- profile-context Jjaek 작성 가능 여부도 관계에 따라 달라짐
- 로그인 사용자는 프로필의 최근 활동 섹션을 볼 수 있다
- stranger / follow-only는 프로필에서 `public` 책 목록을 flat summary 형태로 볼 수 있다
- self / accepted book_friend는 프로필에서 접근 가능한 책 목록 요약을 볼 수 있다
- 프로필에서는 누구에게도 책장 탭, 책장 정렬 UI, 책장 관리 UI, 책 이동 UI를 보여주지 않는다
- stranger / follow-only는 Library 링크를 볼 수 없다
- self / accepted book_friend는 프로필에서 Library 링크를 볼 수 있다
- 최근 활동 섹션은 profile owner의 visible Jjaek과 visible BookActivity를 함께 보여준다
- 실제 Jjaek 노출 범위는 기존 profile Jjaek 정책을 따른다
- BookActivity 노출 범위는 `self / accepted book_friend` 기준이다
- stranger / follow-only 사용자는 프로필 최근 활동에서 BookActivity를 볼 수 없다
- 홈 피드는 현재 사용자와 accepted book_friend의 BookActivity를 Jjaek과 함께 합성한다
- 책장 탭, 책장 관리, 책 이동, 책 목록 정렬은 Library Screen에서만 제공한다
- 상세 권한 규칙은 `docs/architecture/authorization.md`를 본다

관련 코드:
- controller: app/controllers/users_controller.rb (show)
- context 준비:
  - prepare_profile_context
  - prepare_profile_jjaek_form
- view:
  - app/views/users/show.html.erb
  - app/views/users/_profile_header.html.erb
  - app/views/users/_profile_jjaek_form.html.erb
  - app/views/users/_profile_public_books.html.erb
  - app/views/users/_activity_section.html.erb

---

### 4. 서재 화면 (/users/:user_id/library)

- 사용자별 전체 서재 화면
- Library는 새 DB 모델이 아니라 화면/라우팅 개념이다
- 내부 데이터 모델은 기존 `Bookshelf`와 `BookshelfEntry`를 그대로 사용한다
- self / accepted book_friend만 접근할 수 있다
- stranger / follow-only가 접근하면 프로필 화면으로 redirect된다
- 접근 가능한 책장 탭, 선택된 책장 책 목록, 책장 간 Drag and Drop 이동, 일반 책장 생성/수정/삭제, 색상, 순서 변경, 책 목록 정렬, 보기 모드를 제공한다
- 관리 기능은 self에게만 제공한다
- self는 Library에서 책장 인덱스 기반 Drag and Drop으로 책을 다른 내 책장으로 이동할 수 있다
- select 기반 책장 이동은 Book 상세 화면에서 제공한다
- 책장 간 이동 DnD는 selected bookshelf panel의 header와 목록을 덮는 hover target preview overlay를 제공하며, 이동 성공 후 target 책장을 연다
- hover target preview overlay는 drop 성공 전까지 실제 selected bookshelf를 바꾸지 않는다
- 본인 Library의 기본 책 목록 정렬은 `manual`이고, visitor / book_friend 등 타인이 보는 Library의 기본 정렬은 `recent`이다
- 책장 안 책 순서 변경은 `sort=manual`에서만 활성화되며, `BookshelfEntry.position`과 `PATCH /bookshelf_entries/reorder`를 사용한다
- owner의 `manual` 정렬에서는 같은 목록 안 카드 drag로 같은 책장 안 순서를 바꿀 수 있다
- 버튼, input, select, textarea, form 같은 control 요소는 reorder drag 대상에서 제외한다
- detail/compact 카드 전체는 책장 간 이동 drag source로 동작하며, 책 제목 링크는 클릭 시 책 상세 링크로 동작하고 drag 시 책장 간 이동 drag source로 동작한다
- Library UX는 책장 tab/index를 사전 index 또는 바인더 tab처럼 보이게 하고, 선택된 책장과 책 목록 영역을 `Bookshelf.color_key` 기반 accent로 약하게 연결한다
- 책장 tab/index는 horizontal scroll과 좌우 버튼으로 탐색하며, 선택된 tab은 자동으로 화면 안에 보이게 한다
- 책 목록 전체를 진하게 칠하지 않고, 선택된 tab/index와 목록 container border/top border/ring/옅은 tint 수준만 사용한다
- 정렬은 선택된 책장 header 오른쪽 컨트롤로 제공하며, 새 책장 생성과 선택된 일반 책장 관리는 tab/index와 책 목록 사이의 drag 동선을 방해하지 않도록 페이지 내 사전 렌더링 modal로 분리한다
- Library 보기 모드는 URL query parameter `view=detail|compact`로만 처리하며, 기본값과 invalid fallback은 `detail`이고, 전환 UI는 tab/index 위 Library summary/header card 오른쪽에 둔다
- 책장 탭 이동, 정렬 변경, 같은 책장 안 순서 변경, Drag and Drop 책장 이동 후에도 현재 `view`와 허용된 `sort`를 유지한다
- 책장 관리 modal은 Turbo Frame fetch 없이 Stimulus로 create/edit panel을 전환하고, 기존 create/update/move_up/move_down/destroy 흐름을 재사용한다
- 기본 책장 “내 책장”은 삭제할 수 없다
- 일반 책장은 비어 있을 때만 삭제할 수 있고, 책이 들어 있는 책장은 삭제 버튼 대신 안내 문구를 보여준다
- compact book card는 상세 보기보다 더 많은 책이 한 화면에 보이는 간단 카드 격자이며, 표지를 충분히 크게 보여주고 카드 크기와 썸네일 영역을 안정적으로 유지한다
- detail/compact 모두 저자와 출판사를 한 줄 metadata로 표시하고, 상태와 스티커를 카드 하단 footer row에 표시한다
- sticker 목록은 일부 표시와 `+N` 또는 count badge로 요약하며, compact count badge는 전체 sticker 이름을 `title`/`aria-label`로 제공한다
- compact view의 hover preview overlay는 compact card style을 따르고, detail/compact 모두 Library 카드 안에는 책장 이동 select/form을 두지 않는다

관련 코드:
- controller: app/controllers/users/libraries_controller.rb
- view: app/views/users/libraries/show.html.erb
  - app/views/users/_bookshelf_section.html.erb
  - app/views/bookshelf_entries/_profile_bookshelf_entry.html.erb
  - app/views/bookshelf_entries/_compact_bookshelf_entry.html.erb

---

### 5. 관계 화면 (/relationships)

- 현재 구현된 관계 관리 허브 화면
- 받은 책친구 요청
- 보낸 책친구 요청
- 책친구 목록
- 내가 소식받는 사람
- 나를 소식받는 사람

관련 코드:
- controller: app/controllers/relationships_controller.rb
- view: app/views/relationships/index.html.erb

---

### 6. 알림 화면 (/notifications)

- `Notification` 모델 기반 알림 inbox
- unread count를 navbar에 표시
- `/notifications` 진입 시 현재 사용자의 unread 알림을 read 처리
- 책친구 요청 알림은 `/relationships#received-book-friend-requests`로 연결
- profile-context Jjaek, 댓글, ReJjaek 알림은 관련 Jjaek 상세로 연결
- BookFriendship / Jjaek / Comment의 source of truth를 대체하지 않음

관련 코드:
- controller: app/controllers/notifications_controller.rb
- model: app/models/notification.rb
- view: app/views/notifications/index.html.erb

---

### 7. 책 검색 화면 (/book_search)

- `book_searches#show` 기반 검색 화면
- query string 기반 GET 검색
- query string 기반 이전/다음 pagination 제공
- 검색 결과에서 새 책을 `서재에 담기` 할 때 사용자의 책장이 2개 이상이면 대상 책장 select를 표시
- 대상 책장을 선택하지 않으면 기본 책장 “내 책장”에 담김
- `BookSearches::SearchService`와 `BookSearches::KakaoAdapter`를 통해
  Kakao 책 검색 API를 호출하고 결과를 정규화함

관련 코드:
- controller: app/controllers/book_searches_controller.rb
- service:
  - app/services/book_searches/search_service.rb
  - app/services/book_searches/kakao_adapter.rb

### 8. 책 상세 read-only 서재 담기

- 현재 사용자의 `BookshelfEntry`가 없는 책 상세 화면은 read-only 상태로 표시됨
- 이 상태에서 `서재에 담기`를 할 수 있음
- 사용자의 책장이 2개 이상이면 대상 책장 select를 표시
- 대상 책장을 선택하지 않으면 기본 책장 “내 책장”에 담김

---

## 공통 책 썸네일 정책

- 책 썸네일은 `app/views/books/_thumbnail.html.erb` 공통 partial을 사용한다.
- 책 표지는 사진처럼 crop해서 꾸미는 대상이 아니라, 책 정보를 전달하는 이미지로 본다.
- thumbnail이 있는 경우에는 고정 세로형 wrapper에 억지로 맞추지 않는다.
- thumbnail 이미지는 max-height / max-width 안에서 원본 비율을 유지해 자연스럽게 표시한다.
- 이미지를 wrapper에 맞추기 위해 찌그러뜨리거나 강제로 crop하지 않는다.
- 기본 object-fit은 `object-contain`을 사용한다.
- 표지 없음 fallback일 때만 size별 고정 박스를 사용한다.
- 화면별 크기는 partial의 `size` 옵션으로 조정한다.
- Kakao 썸네일 URL은 임의 크기 치환 없이 API 응답값을 우선 사용한다.
- crop이 필요한 별도 UI가 생기면 기본 정책이 아니라 명시적 옵션으로 분리한다.

---

## Jjaek 문맥

하나의 모델로 통합:

- 일반 짹
- 책짹 (book_id 있음)
- profile-context 짹 (target_user_id 있음)
- ReJjaek (quoted_jjaek 있음)

→ 하나의 Jjaek 모델이 문맥(context)에 따라 역할을 나눠 갖는다.

ReJjaek은 원문을 복사하지 않고 `quoted_jjaek`으로 참조한다.
원문이 수정되면 quoted block도 최신 원문을 보여준다.
원문 또는 ReJjaek 본문이 수정된 경우 MVP에서는 수정 이력 전체가 아니라 “수정됨” 표시만 둔다.
원문이 삭제되지 않았지만 현재 사용자에게 보이지 않으면, 해당 사용자에게는 ReJjaek도 조회 시점 권한 기준으로 비노출한다.
이 경우 ReJjaek을 자동으로 private 전환하지 않는다.
원문이 hard delete되면 ReJjaek 본문은 보존하고 `private_jjaek`으로 전환한다.
이후 ReJjaek 작성자 본인에게만 보이며, quoted block 위치에는
“원문이 삭제되어 나만 볼 수 있습니다.” 안내를 표시한다.
deleted-source 안내에는 원문 작성자 표시 이름, 원문 종류(짹/책짹), 원문 삭제 시각만 남기고,
원문 본문/책 메타/avatar snapshot은 저장하지 않는다.
공개 화면에서는 “삭제된 원문입니다” placeholder를 표시하지 않는다.
한 사용자는 같은 원문 Jjaek을 한 번만 ReJjaek할 수 있으며,
동일 사용자 + 동일 원문 중복 ReJjaek 요청은 새 ReJjaek을 만들지 않는다.
다른 사용자가 같은 원문을 ReJjaek하는 것은 허용한다.

---

## 권한 / visibility 구조 (상세는 별도 문서)

현재 구현의 권한 구조와 visibility 상세는 아래 문서를 함께 본다.

- 권한 구조: `docs/architecture/authorization.md`
- visibility 구조: `docs/architecture/jjaek_visibility.md`

---

## 권한 처리 구조

- Pundit policy 사용
- controller → authorize / policy_scope
- view는 결과만 소비

핵심 위치:
- app/policies/*
- UsersController
- JjaeksController

세부 권한 규칙은 `docs/architecture/authorization.md`를 본다.

---

## 데이터 책임 분리

- BookshelfEntry
  - 사용자-책-책장 관계
  - 상태 / 스티커
  - 목록 화면은 별도로 제공하지 않으며, 대표 서재 화면은 `/users/:user_id/library`를 사용한다

- Bookshelf
  - 책장 이름 / visibility
  - 기본 책장 여부
  - 기본 책장은 직접 삭제하거나 이름을 변경할 수 없음

- Jjaek
  - 글 / 공개 범위

- BookActivity
  - 책 관련 활동 이벤트 기반

현재 `BookActivity`는 모델/테이블과 `BookshelfEntry` 생성/수정 성공 후 실제 변경을 기록하는 기반이 도입되어 있다.
프로필 화면에는 Jjaek과 함께 최근 활동 섹션으로 노출되며, 조회 가능 범위는 현재 `self / accepted book_friend` 기준이다.
home feed에는 현재 사용자와 accepted book_friend의 BookActivity를 Jjaek과 함께 합성한다.
books/:id timeline에는 아직 합성하지 않는다.

→ 현재 상태, 본문 콘텐츠, 피드용 이벤트는 분리된 모델에서 관리한다

---

## 작성 흐름

### 1. 프로필에서 짹 작성

UsersController#show
→ Jjaek.new (profile_jjaek)
→ POST /jjaeks
→ JjaeksController#create

---

### 2. 책에서 짹 작성

BooksController#show
→ Jjaek.new (book context)
→ POST /jjaeks
→ JjaeksController#create

---

## 상호작용 / ReJjaek 참고

- 댓글 / 좋아요 권한 상세는 `docs/architecture/authorization.md`를 본다
- ReJjaek visibility 제약 상세는 `docs/architecture/jjaek_visibility.md`를 본다
- ReJjaek 목록 조회 기준은 `docs/specs/requotes_mvp.md`를 본다

Turbo 1차 적용 상태:

- 좋아요는 count/button 영역만 갱신한다.
- 댓글은 상세 페이지와 home/profile/book inline comments panel에서 panel과 count/action 영역을 갱신한다.
- 상세 페이지 ReJjaek 목록은 detail panel만 갱신한다.
- flash는 stable wrapper 기반으로 일부 Turbo 성공 응답에서 갱신된다.
- notification badge는 stable wrapper foundation만 완료했고 실제 Turbo 갱신은 보류 상태다.
- relationships hub의 핵심 관계 action은 section 단위로 갱신한다.
- 책 검색 결과의 `서재에 담기` 성공 케이스는 해당 result card만 갱신한다.
- bookshelf 관련 Turbo화는 현재 HTML fallback 흐름을 유지하며, DnD 설계 이후 재검토한다.

---

## 테스트 구조

- request spec: 사용자 흐름
- model spec: 도메인 규칙
- policy: 권한 검증

관련 문서:
- docs/testing/rspec_strategy.md

---

## 관련 문서

- 작업 규칙: AGENTS.md
- 현재 구현 요약: docs/architecture/current_system.md
- 권한 구조: docs/architecture/authorization.md
- visibility 구조: docs/architecture/jjaek_visibility.md
- 기능 spec: docs/specs/*
- 제품/도메인 기준: docs/specs/bookjjaek_reboot_spec.md
- 과거 리부트 계획: docs/archive/reboot_plan.md (참고용)
- 리팩토링: docs/refactor/*
- 테스트 전략: docs/testing/rspec_strategy.md
