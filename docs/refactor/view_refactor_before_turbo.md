# View Refactor Before Turbo

## 목적

Turbo를 적용하기 전에 Rails view 구조를 먼저 정리한다.

현재 checkjjaek4는 대부분의 화면이 `redirect_to + flash + full render` 기반으로 안정적으로 동작한다.
하지만 좋아요, 댓글, ReJjaek 목록, 일부 글 작성 흐름처럼 화면 전체 이동 없이 현재 맥락 안에서 갱신하는 것이 더 자연스러운 영역도 있다.

Turbo를 바로 적용하면 ERB view 안에 조건문, helper 호출, form/button, DOM id, Turbo Frame/Stream 대상이 한꺼번에 섞일 수 있다.
따라서 Turbo 적용 전에 view를 먼저 정리하여 ERB가 복잡해지는 것을 막는다.

이 문서는 기능 spec이 아니라, Turbo 적용 전 view 리팩토링 기준 문서다.

---

## 기본 원칙

### 1. View는 조립 역할을 우선한다

View는 가능한 한 다음 역할에 집중한다.

- partial 조립
- 이미 준비된 값 출력
- form/button/link 배치
- Tailwind class 적용
- 간단한 present?/empty? 수준의 표시 분기

복잡한 판단, 라벨 결정, 버튼 상태 결정, 권한 계산은 view 안에 직접 쌓지 않는다.

---

### 2. 조건 판단은 helper/controller/policy 쪽으로 이동한다

View에서 다음과 같은 판단이 길어지면 분리 후보로 본다.

- 현재 사용자가 어떤 버튼을 볼 수 있는가
- 버튼 label/path/method/class가 무엇인가
- 어떤 count를 보여줄 것인가
- 어떤 visibility option을 보여줄 것인가
- 어떤 Turbo target으로 갱신할 것인가
- 어떤 empty state를 보여줄 것인가

기준:

- 권한 판단은 policy/controller에서 처리한다.
- 화면용 label/path/class 조합은 helper로 뺀다.
- collection/count/preload는 controller에서 준비한다.
- view는 준비된 값을 소비한다.

---

### 3. Turbo target이 될 영역은 먼저 partial로 분리한다

Turbo 적용 전, 나중에 교체될 영역을 partial 단위로 나눈다.

예상되는 Turbo target:

- Jjaek card
- Jjaek action bar
- like button/count 영역
- comment count 영역
- comments panel
- comment row
- comment form
- ReJjaek count/link 영역
- ReJjaek list panel
- flash 영역
- notification badge
- book search result card
- relationship row

Turbo Frame/Stream 코드는 리팩토링 단계에서는 넣지 않는다.
다만 나중에 Turbo target으로 삼기 쉬운 경계까지만 먼저 만든다.

---

## 하지 않을 것

이번 리팩토링 단계에서는 다음을 하지 않는다.

- Turbo Frame 추가
- Turbo Stream response 추가
- Stimulus controller 추가
- JavaScript 추가
- DnD 구현
- 새 기능 추가
- 디자인 변경
- 사용자 흐름 변경
- 권한 정책 변경
- visibility 정책 변경
- 테스트 기대값을 기능 변경에 맞춰 수정

리팩토링의 목표는 동작 동일성 유지다.

---

## 우선 점검 대상

### 1. Jjaek card

대상:

- `app/views/jjaeks/_jjaek.html.erb`

현재 Jjaek card는 다음 책임을 한 파일에서 처리한다.

- 작성자/문맥 표시
- 작성 시각/visibility 표시
- 수정/삭제 버튼
- 책 정보 표시
- quoted jjaek 표시
- 본문 표시
- 좋아요 수
- 댓글 수
- ReJjaek 수/link
- 좋아요/취소 버튼
- 상세 보기 link

Turbo 적용 전에 의미 단위로 나눌 수 있는지 점검한다.

분리 후보:

- `jjaeks/_jjaek_header.html.erb`
- `jjaeks/_jjaek_body.html.erb`
- `jjaeks/_jjaek_book.html.erb`
- `jjaeks/_jjaek_actions.html.erb`
- `jjaeks/_jjaek_meta.html.erb`
- `jjaeks/_like_action.html.erb`
- `jjaeks/_requote_link.html.erb`

처음부터 모든 partial을 만들 필요는 없다.
좋아요/댓글/ReJjaek Turbo 적용에 직접 필요한 경계부터 나눈다.

---

### 2. Comments 영역

대상:

- `app/views/jjaeks/show.html.erb`
- `app/controllers/comments_controller.rb`

현재 댓글 목록과 댓글 작성 form은 Jjaek 상세 화면에 직접 포함되어 있다.

Turbo 적용 전 분리 후보:

- `comments/_comments_panel.html.erb`
- `comments/_comment.html.erb`
- `comments/_form.html.erb`

나중에 기대하는 흐름:

- 댓글 수 클릭
- 현재 Jjaek card 아래에 comments panel 표시
- 댓글 작성 시 목록 append
- 댓글 삭제 시 row remove
- 댓글 수 갱신

이 단계에서는 위 흐름을 구현하지 않고, partial 경계만 준비한다.

---

### 3. ReJjaek 목록 영역

대상:

- `app/controllers/requotes_controller.rb`
- `app/views/requotes/index.html.erb`
- `app/views/jjaeks/_jjaek.html.erb`

현재 ReJjaek 수/link는 Jjaek card에 표시되고, 목록은 별도 index 화면에서 조회한다.

Turbo 적용 전 점검할 것:

- ReJjaek count/link 영역을 partial로 분리할 수 있는가
- ReJjaek list를 panel partial로 분리할 수 있는가
- visibility 정책을 view가 아니라 controller/policy_scope가 책임지고 있는가

ReJjaek은 댓글보다 visibility 정책 영향이 크므로 좋아요/댓글 이후 단계로 둔다.

---

### 4. Layout / flash / notification badge

대상:

- `app/views/layouts/application.html.erb`
- `app/views/shared/_flash.html.erb`

Turbo Stream을 적용하면 flash와 notification badge는 독립 갱신 대상이 된다.

분리 후보:

- `shared/_nav.html.erb`
- `shared/_notification_badge.html.erb`
- `shared/_flash.html.erb`

이 단계에서는 Turbo Stream을 적용하지 않는다.
다만 layout 안의 조건과 badge 렌더링을 partial로 분리할 수 있는지 점검한다.

---

### 5. Book search result

대상:

- `app/views/book_searches/show.html.erb`

책 검색 화면은 검색 form, 검색 결과 card, 서재 담기 form, pagination을 한 파일에서 처리한다.

분리 후보:

- `book_searches/_search_form.html.erb`
- `book_searches/_result_card.html.erb`
- `book_searches/_add_to_shelf_form.html.erb`
- `book_searches/_pagination.html.erb`

나중에 Turbo 적용 후보:

- 검색 결과에서 `서재에 담기` 후 해당 result card만 “이미 담김” 상태로 교체

다만 현재처럼 책 상세로 이동시키는 흐름도 제품 의도가 있으므로, Turbo 적용 여부는 별도 판단한다.

---

### 6. Relationships 화면

대상:

- `app/views/relationships/index.html.erb`

관계 화면은 다음 섹션을 한 파일에서 반복 렌더링한다.

- 받은 책친구 요청
- 보낸 책친구 요청
- 책친구
- 소식받기
- 팔로워

분리 후보:

- `relationships/_section.html.erb`
- `relationships/_request_row.html.erb`
- `relationships/_user_row.html.erb`
- `relationships/_empty_state.html.erb`

나중에 Turbo 적용 후보:

- 요청 거절 row 제거
- 보낸 요청 취소 row 제거
- 소식받기 해제 row 제거

요청 수락은 한 row가 다른 섹션으로 이동하는 액션이므로 나중 단계로 둔다.

---

### 7. Home / Profile / Book show의 작성 form

대상:

- `app/views/homes/show.html.erb`
- `app/views/users/_profile_jjaek_form.html.erb`
- `app/views/books/_jjaek_form_panel.html.erb`

나중에 Turbo 적용 후보:

- 홈에서 글 작성 후 피드 상단 prepend
- 프로필에서 profile-context Jjaek 작성 후 활동 목록 갱신
- 책 상세에서 책짹 작성 후 timeline 갱신

Turbo 적용 전 점검할 것:

- form partial이 충분히 독립적인가
- 작성 실패 시 error 표시가 form 내부에서 처리되는가
- 작성 성공 후 갱신할 list 영역이 partial로 분리되어 있는가
- controller가 해당 화면을 다시 준비하는 로직을 중복 없이 갖고 있는가

---

## 우선순위

### P1. Jjaek card 구조 정리

가장 먼저 정리한다.

이유:

- 좋아요 Turbo화의 직접 대상
- 댓글 펼치기/작성의 직접 대상
- ReJjaek 목록 표시의 직접 대상
- 홈, 프로필, 책 상세 timeline에서 공통 사용

---

### P2. Comments partial 분리

Jjaek 상세 댓글 영역을 독립 partial로 나눈다.

이유:

- 댓글 펼치기
- 댓글 작성
- 댓글 삭제
- 댓글 수 갱신

위 Turbo 작업의 기반이 된다.

---

### P3. Shared flash/nav/badge 정리

Turbo Stream을 여러 곳에서 쓰기 전에 flash와 notification badge를 독립 렌더링 단위로 만든다.

---

### P4. Book search result card 정리

검색 결과 card와 add form을 분리한다.

---

### P5. Relationships section/row 정리

관계 화면의 반복 구조를 partial로 정리한다.

---

## Turbo 적용 순서 초안

View 리팩토링 이후 Turbo 적용은 다음 순서를 우선 검토한다.

1. 좋아요/좋아요 취소
2. 댓글 panel 펼치기
3. 댓글 작성/삭제
4. ReJjaek 목록 panel
5. 홈 피드 글 작성 후 prepend
6. 책 상세 책짹 작성 후 timeline 갱신
7. 프로필 profile-context Jjaek 작성 후 활동 목록 갱신
8. 책 검색 결과의 서재 담기 row 갱신
9. 관계 화면 일부 row 제거
10. notification badge / flash 공통 stream 정리

이 순서는 확정된 구현 계획이 아니라, view 리팩토링 후 검토할 후보 순서다.

---

## 완료 기준

View 리팩토링 단계의 완료 기준:

- 기능 변화 없음
- 디자인 변화 없음
- 기존 request/system spec 통과
- Jjaek card의 책임이 의미 단위 partial로 나뉨
- 댓글 영역이 partial로 분리됨
- Turbo target 후보가 될 영역의 경계가 명확해짐
- view 안의 복잡한 조건/라벨/버튼 상태 계산이 줄어듦
- 이후 Turbo 적용 시 ERB 복잡도가 급격히 증가하지 않는 구조가 됨

