# Turbo Interactions MVP

## 목적

checkjjaek4에 Turbo를 전면 도입하지 않고, 사용자 체감이 큰 상호작용부터 단계적으로 적용한다.

현재 앱은 대부분 `redirect_to + flash + full render` 기반으로 안정적으로 동작한다.  
이 구조는 관계, 알림, 책장, 권한 흐름에서는 계속 유지할 가치가 있다.

다만 Jjaek card 내부 상호작용처럼 사용자가 이미 보고 있는 글 주변에서 처리할 수 있는 액션은 전체 페이지 reload 없이 부분 갱신하는 것이 더 자연스럽다.

---

## 기본 원칙

- 앱 전체를 Turbo Frame 기반으로 재설계하지 않는다.
- Turbo는 사용자 체감이 큰 작은 상호작용부터 적용한다.
- HTML fallback은 반드시 유지한다.
- 권한/visibility 정책은 변경하지 않는다.
- Pundit policy와 policy_scope 흐름은 유지한다.
- Stimulus/JavaScript는 필요한 경우에만 별도 단계에서 도입한다.
- 한 번에 하나의 상호작용만 Turbo화한다.
- Turbo 적용 전 partial 경계를 먼저 정리한다.
- 관련 view 구조는 `docs/refactor/view_refactor_before_turbo.md`를 따른다.

---

## 현재 완료된 준비 작업

Turbo 적용 전 view 리팩토링으로 다음 구조를 정리했다.

- Jjaek card partial 분리
- Comments panel/comment/form partial 분리
- Shared nav / notification badge partial 분리
- Book search form/result/add/pagination partial 분리
- Relationships section/row/empty partial 분리
- Book search view helper 정리
- Jjaek form copy polish

이제 Turbo를 적용할 최소 기반은 마련된 상태다.

---

## 1차 대상: Jjaek 좋아요

상태: 완료

### 현재 문제

좋아요/좋아요 취소 시 전체 페이지가 다시 렌더링된다.

### 목표

좋아요 클릭 시 해당 Jjaek의 좋아요 관련 영역만 갱신한다.

갱신 대상:

- 좋아요 수
- 좋아요 / 좋아요 취소 버튼

### 구현 기준

- 좋아요 count와 좋아요 button을 하나의 partial로 묶는다.
- Turbo Stream은 해당 partial 또는 action 영역을 replace한다.
- HTML 요청은 기존처럼 redirect fallback을 유지한다.
- 실패/권한 오류 흐름은 기존 정책을 유지한다.
- flash 갱신은 1차 범위에서 제외할 수 있다.

### 현재 구현

- 좋아요/좋아요 취소 Turbo Stream 응답은 해당 Jjaek의 좋아요 action 영역을 갱신한다.
- HTML fallback은 기존 redirect 흐름을 유지한다.
- Jjaek card 전체 replace는 하지 않는다.

### 하지 않을 것

- ReJjaek 목록 Turbo화
- notification badge Turbo화
- flash Turbo화
- Jjaek card 전체 replace

---

## 2차 대상: 댓글 inline panel

상태: 부분 완료 - home/profile/book 기준 구현 완료 / Requotes 화면 보류

### 현재 문제

댓글을 보거나 작성하려면 Jjaek 상세 화면으로 이동해야 한다.

### 목표

사용자가 home feed, profile 화면, book 상세 timeline에서 이미 Jjaek을 보고 있다면, 댓글 보기 액션을 눌러 card 아래에서 댓글 목록과 입력 form을 볼 수 있게 한다.

Requotes 화면의 inline comments panel은 아직 구현하지 않는다.

### 구현 기준

- 댓글 panel은 Jjaek card 아래에 표시한다.
- 댓글 목록과 댓글 form은 기존 comments partial을 재사용한다.
- 댓글 작성 성공 시 댓글 목록과 댓글 수를 갱신한다.
- 댓글 작성 실패 시 panel 내부에 validation error를 표시한다.
- HTML fallback은 Jjaek 상세 페이지를 유지한다.

### 현재 구현

- 상세 페이지 댓글 create/destroy는 Turbo Stream으로 comments panel을 갱신한다.
- 댓글 create 실패 시 Turbo Stream 응답은 comments panel 내부를 422 상태로 다시 렌더링하고 validation error를 표시한다.
- 댓글 create/destroy 성공 시 댓글 count/action 영역도 함께 갱신한다.
- home/profile/book Jjaek card에는 댓글 count 링크와 별도의 `댓글 보기` inline trigger가 함께 표시된다.
- 댓글 count 링크는 기존처럼 Jjaek 상세 페이지 comments panel anchor로 이동한다.
- `댓글 보기` trigger는 context별 comments panel placeholder에 comments panel을 로드한다.
- comments panel target id는 아래처럼 context별로 구분한다.
  - detail: `comments_panel_jjaek_ID`
  - home: `comments_panel_home_jjaek_ID`
  - profile: `comments_panel_profile_USERID_jjaek_ID`
  - book: `comments_panel_book_BOOKID_jjaek_ID`
- home/profile/book inline panel에서 댓글 create/destroy를 수행하면 해당 context panel을 갱신한다.
- home/profile/book inline panel에는 닫기 액션이 있으며, 닫기 시 해당 context panel을 같은 id의 빈 placeholder로 되돌린다.
- profile context는 `profile_user_id`가 존재할 때만 inline target을 사용하며, 없으면 detail fallback한다.
- book context는 `book_id`가 있고 Jjaek의 `book_id`와 일치할 때만 inline target을 사용하며, 맞지 않으면 detail fallback한다.
- raw DOM id는 params로 받지 않는다.
- detail comments panel에는 닫기 액션을 표시하지 않는다.
- HTML fallback은 기존 상세 페이지 흐름을 유지한다.

### 미구현/보류

- Requotes 화면 inline comments panel
- Stimulus 기반 open/close toggle
- modal 기반 comments UI
- 실시간 broadcast
- 같은 화면에 동일 Jjaek이 여러 번 렌더된 경우의 동시 갱신

---

## 3차 대상: ReJjaek 목록 panel

상태: 부분 완료 - detail page 기준 구현 완료 / feed 확장 보류

### 현재 문제

ReJjaek count를 클릭하면 별도 목록 페이지로 이동한다.

### 목표

Jjaek 상세 페이지에서 ReJjaek 목록을 현재 화면 안에서 확인할 수 있게 한다.

홈 피드, 프로필, 책 상세, ReJjaek 목록 화면의 inline ReJjaek panel은 아직 구현하지 않는다.

### 주의

ReJjaek은 visibility 정책 영향이 크다.  
따라서 댓글보다 뒤에 적용한다.

### 구현 기준

- 기존 RequotesController#index와 policy_scope를 유지한다.
- inline panel에서도 visible ReJjaek만 보여준다.
- HTML fallback으로 기존 index 페이지 접근을 유지한다.

### 현재 구현

- Jjaek 상세 페이지에 detail-only `requotes_panel_jjaek_ID` placeholder를 둔다.
- Jjaek 상세 페이지에만 `다시짹 보기` Turbo trigger를 표시한다.
- 공통 Jjaek card action의 `_requote_link.html.erb`는 기존 `다시짹 N개` HTML 링크를 유지한다.
- `GET /jjaeks/:jjaek_id/requotes` HTML 요청은 기존 ReJjaek index 페이지를 그대로 렌더한다.
- Turbo Stream 요청은 `requotes_panel_jjaek_ID` target만 replace한다.
- RequotesController#index의 기존 `authorize @jjaek, :requote?`와 `policy_scope(Jjaek)` 기반 visible ReJjaek 조회를 유지한다.
- panel 안에서는 visible heading을 반복 표시하지 않고 `sr-only` heading만 유지한다.
- ReJjaek policy, visibility, source deletion 로직은 변경하지 않는다.

### 미구현/보류

- home feed inline ReJjaek panel
- profile 화면 inline ReJjaek panel
- book 화면 inline ReJjaek panel
- ReJjaek 목록 화면 안의 inline ReJjaek panel
- Stimulus 기반 open/close toggle
- modal 기반 ReJjaek UI
- 실시간 broadcast
- 같은 화면에 동일 Jjaek이 여러 번 렌더된 경우의 동시 갱신

---

## 4차 후보: flash / notification badge

### flash

상태: 부분 완료 - comments create/destroy Turbo 성공 기준

Turbo Stream을 여러 곳에서 쓰기 시작하면 flash도 독립 갱신 대상이 될 수 있다.

현재 구현:

- layout에 stable `#flash-messages` wrapper를 항상 렌더한다.
- comments create/destroy Turbo 성공 시 `flash.now[:notice]`를 사용한다.
- comments create/destroy Turbo Stream 응답에서 `#flash-messages`를 update한다.
- comments create 실패 422 응답에는 flash update를 포함하지 않는다.
- likes Turbo는 좋아요 action 영역 갱신만 유지하며 flash update를 추가하지 않았다.

원칙:

- 모든 Turbo action에 무조건 flash를 붙이지 않는다.
- 좋아요처럼 button/count 변화만으로 충분히 피드백되는 interaction에는 flash update를 필수로 보지 않는다.
- 사용자에게 의미 있는 성공/실패 피드백이 필요한 action부터 선택적으로 적용한다.

### notification badge

상태: foundation 완료 / Turbo 갱신 보류

현재 notification badge는 partial로 분리되어 있다.  
Turbo Stream 교체 대상으로 쓸 수 있도록 stable wrapper foundation을 먼저 둔다.

현재 구현:

- nav에 stable `#notification-badge-container` wrapper를 항상 렌더한다.
- unread count가 0이어도 `#notification-badge-container`는 DOM에 남는다.
- unread count가 있으면 기존 `#notification-badge`와 count가 wrapper 안에 표시된다.

notification badge는 current_user의 unread count 기준이다.  
따라서 댓글/다시짹 작성자의 현재 화면에서 직접 갱신하면 안 된다.

현재 `GET /notifications`는 알림 목록 진입 시 unread id를 저장한 뒤 같은 요청 안에서 자동 read 처리한다.
따라서 이 정책을 유지하는 동안 별도 `read_all` Turbo action은 우선순위가 낮다.

명시적 `read_all` action은 나중에 알림 읽음 정책을 자동 read에서 명시적 read로 바꿀 때 별도 검토한다.
알림 읽음/확인 흐름 Turbo화와 notification badge 갱신은 별도 단계로 둔다.
ActionCable/실시간 broadcast도 이번 범위에서는 다루지 않는다.

---

## 5차 후보: 관계 화면 row 갱신

관계 화면은 section/row partial로 분리되어 있다.

Turbo 후보:

- 받은 책친구 요청 거절 시 row 제거
- 보낸 책친구 요청 취소 시 row 제거
- 소식받기 해제 시 row 제거

주의:

- 책친구 요청 수락은 row 제거와 book friends section 추가가 동시에 필요하다.
- 따라서 수락 Turbo화는 나중으로 둔다.
- soft rejection notification 정책은 변경하지 않는다.

---

## 6차 후보: 책 검색 결과 row 갱신

책 검색 결과는 result card와 add-to-shelf form으로 분리되어 있다.

Turbo 후보:

- 검색 결과에서 `서재에 담기` 후 해당 result card를 “이미 담김” 상태로 교체

주의:

- 현재는 서재에 담은 뒤 책 상세로 이동하는 흐름이다.
- 이 흐름은 제품 의도가 있을 수 있으므로 별도 판단 후 적용한다.

---

## 보류 대상

다음은 Turbo MVP 범위에서 제외한다.

- 앱 전체 Turbo Frame 구조 전환
- Requotes 화면 inline comments panel
- home/profile/book/requotes inline ReJjaek panel
- Stimulus 기반 comments toggle
- modal 기반 comments UI
- notification badge Turbo 갱신
- 알림 읽음/확인 흐름 Turbo화
- 실시간 broadcast
- 모든 Turbo action에 무조건 flash 추가
- 같은 화면의 동일 Jjaek 다중 렌더 동시 갱신
- 서재 DnD
- 책장 생성/수정/삭제 Turbo화
- notification 실시간 push
- PWA/service worker
- 관계 화면 전체 Turbo화
- 책 검색 전체 Turbo화
- 모든 form의 Turbo Stream 응답화

---

## 권장 적용 순서

1. Jjaek action 구조 정리
2. 좋아요 count + button partial 정리
3. 좋아요 Turbo Stream 적용 완료
4. 상세 페이지 댓글 작성/삭제 Turbo 적용 완료
5. home/profile/book inline comments panel 적용 완료
6. home/profile/book inline comments panel 닫기 UX 적용 완료
7. 상세 페이지 ReJjaek 목록 panel 적용 완료
8. flash / notification badge 공통 갱신 검토
9. 관계 화면 row 제거 검토
10. 책 검색 result card 갱신 검토

---

## 완료 기준

Turbo 1차 완료 기준:

- 좋아요 클릭 시 전체 페이지 reload 없이 count/button이 갱신된다.
- HTML fallback이 유지된다.
- 기존 request spec이 통과한다.
- Turbo Stream 요청에 대한 request spec이 추가된다.
- 권한/visibility 정책 변경이 없다.
- ReJjaek/notification/flash는 아직 변경하지 않는다.

Turbo MVP 완료 기준:

- Jjaek card 내부 주요 상호작용이 필요한 화면 맥락 안에서 단계적으로 처리된다.
- 좋아요, home/profile/book 댓글, 상세 페이지 ReJjaek 목록은 partial 갱신 구조를 갖는다.
- Requotes 화면 inline comments panel은 별도 검토 대상으로 남긴다.
- home/profile/book/requotes inline ReJjaek panel은 별도 검토 대상으로 남긴다.
- full redirect가 더 안전한 영역은 그대로 유지한다.
- view가 Turbo/JS 코드로 다시 복잡해지지 않는다.
