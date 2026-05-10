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

### 하지 않을 것

- 댓글 Turbo화
- ReJjaek 목록 Turbo화
- notification badge Turbo화
- flash Turbo화
- Jjaek card 전체 replace

---

## 2차 대상: 댓글 inline panel

### 현재 문제

댓글을 보거나 작성하려면 Jjaek 상세 화면으로 이동해야 한다.

### 목표

사용자가 피드/프로필/책 상세 timeline에서 이미 Jjaek을 보고 있다면, 댓글 수 또는 댓글 보기 액션을 눌러 card 아래에서 댓글 목록과 입력 form을 볼 수 있게 한다.

### 구현 기준

- 댓글 panel은 Jjaek card 아래에 표시한다.
- 댓글 목록과 댓글 form은 기존 comments partial을 재사용한다.
- 댓글 작성 성공 시 댓글 목록과 댓글 수를 갱신한다.
- 댓글 작성 실패 시 panel 내부에 validation error를 표시한다.
- HTML fallback은 Jjaek 상세 페이지를 유지한다.

---

## 3차 대상: ReJjaek 목록 panel

### 현재 문제

ReJjaek count를 클릭하면 별도 목록 페이지로 이동한다.

### 목표

ReJjaek count/link 클릭 시 현재 card 아래에서 ReJjaek 목록을 볼 수 있는 구조를 검토한다.

### 주의

ReJjaek은 visibility 정책 영향이 크다.  
따라서 댓글보다 뒤에 적용한다.

### 구현 기준

- 기존 RequotesController#index와 policy_scope를 유지한다.
- inline panel에서도 visible ReJjaek만 보여준다.
- HTML fallback으로 기존 index 페이지 접근을 유지한다.

---

## 4차 후보: flash / notification badge

### flash

Turbo Stream을 여러 곳에서 쓰기 시작하면 flash도 독립 갱신 대상이 될 수 있다.

다만 1차 좋아요 Turbo화에서는 flash 갱신을 필수로 보지 않는다.

### notification badge

현재 notification badge는 partial로 분리되어 있다.  
하지만 badge가 없을 때 DOM 자체가 사라지는 구조라, Turbo Stream 교체 대상으로 쓰려면 wrapper 설계가 필요하다.

따라서 notification badge 실시간 갱신은 후순위로 둔다.

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
3. 좋아요 Turbo Stream 적용
4. 댓글 panel 표시
5. 댓글 작성/삭제 Turbo 적용
6. ReJjaek 목록 panel 검토
7. flash / notification badge 공통 갱신 검토
8. 관계 화면 row 제거 검토
9. 책 검색 result card 갱신 검토

---

## 완료 기준

Turbo 1차 완료 기준:

- 좋아요 클릭 시 전체 페이지 reload 없이 count/button이 갱신된다.
- HTML fallback이 유지된다.
- 기존 request spec이 통과한다.
- Turbo Stream 요청에 대한 request spec이 추가된다.
- 권한/visibility 정책 변경이 없다.
- 댓글/ReJjaek/notification/flash는 아직 변경하지 않는다.

Turbo MVP 완료 기준:

- Jjaek card 내부 주요 상호작용이 현재 맥락 안에서 처리된다.
- 좋아요, 댓글, ReJjaek 목록이 단계적으로 partial 갱신 구조를 갖는다.
- full redirect가 더 안전한 영역은 그대로 유지한다.
- view가 Turbo/JS 코드로 다시 복잡해지지 않는다.