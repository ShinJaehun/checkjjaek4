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
- BookshelfEntry
- Follow
- BookFriendship
- Comment
- Like

역할 요약:

- Jjaek: 사용자 콘텐츠 단위
- Book: 외부 검색 기반 도서 데이터
- BookshelfEntry: 사용자-책 관계 (상태/스티커)
- BookFriendship: 관계 기반 권한 확장
- Follow: 피드 구독
- Comment: Jjaek에 대한 댓글
- Like: Jjaek에 대한 좋아요

---

## 주요 화면과 흐름

### 1. 홈 (/)

- `JjaekPolicy::FeedScope` 기반 Jjaek 피드
- 내 Jjaek, 소식받는 사용자의 공개 Jjaek, 책친구 공개 Jjaek,
  현재 사용자 대상 profile-context Jjaek이 함께 섞일 수 있음

관련 코드:
- controller: app/controllers/homes_controller.rb
- view: app/views/homes/show.html.erb

---

### 2. 책 화면 (/books/:id)

- 책 정보 표시
- viewer 기준 `policy_scope`를 통과한 해당 책의 Jjaek 목록 표시
- 현재 사용자의 `BookshelfEntry`가 있을 때만 책짹 작성 컨텍스트가 열림
- 현재 사용자의 `BookshelfEntry`가 있을 때만 상태/스티커 편집 컨텍스트가 열림

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
- profile-context Jjaek 작성 가능 여부도 관계에 따라 달라짐
- 현재 구현에서는 `follow / book_friend / self`만 프로필 Jjaek 섹션이 열린다
- 목표 정책과의 차이는 `docs/architecture/authorization.md`를 본다

관련 코드:
- controller: app/controllers/users_controller.rb (show)
- context 준비:
  - prepare_profile_context
  - prepare_profile_jjaek_form
- view:
  - app/views/users/show.html.erb
  - app/views/users/_profile_header.html.erb
  - app/views/users/_profile_jjaek_form.html.erb
  - app/views/users/_bookshelf_section.html.erb
  - app/views/users/_jjaeks_section.html.erb

---

### 4. 관계 화면 (/relationships)

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

### 5. 책 검색 화면 (/book_search)

- `book_searches#show` 기반 검색 화면
- query string 기반 GET 검색
- `BookSearches::SearchService`와 `BookSearches::KakaoAdapter`를 통해
  Kakao 책 검색 API를 호출하고 결과를 정규화함

관련 코드:
- controller: app/controllers/book_searches_controller.rb
- service:
  - app/services/book_searches/search_service.rb
  - app/services/book_searches/kakao_adapter.rb

---

## Jjaek 문맥

하나의 모델로 통합:

- 일반 짹
- 책짹 (book_id 있음)
- profile-context 짹 (target_user_id 있음)
- ReJjaek (quoted_jjaek 있음)

→ 하나의 Jjaek 모델이 문맥(context)에 따라 역할을 나눠 갖는다.

---

## 권한 / visibility 구조 (상세는 별도 문서)

현재 구현의 권한 구조와 visibility 상세는 아래 문서를 함께 본다.

- 권한 구조: `docs/architecture/authorization.md`
- visibility 구조: `docs/architecture/visibility.md`

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
  - 상태 / 스티커

- Jjaek
  - 글 / 공개 범위

→ 상태와 콘텐츠는 분리된 모델에서 관리한다

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
- ReJjaek visibility 제약 상세는 `docs/architecture/visibility.md`를 본다

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
- visibility 구조: docs/architecture/visibility.md
- 기능 spec: docs/specs/*
- 제품 방향: docs/reboot/reboot_plan.md
- 리팩토링: docs/refactor/*
- 테스트 전략: docs/testing/rspec_strategy.md
