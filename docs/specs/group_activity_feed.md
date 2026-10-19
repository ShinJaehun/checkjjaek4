# Group activity feed

## 목적

홈은 사람을 따라 읽는 feed, 동아리는 모임을 따라 읽는 feed로 콘텐츠 경계를 분리한다.
기존 Jjaek visibility, Group read boundary와 moderation 정책은 변경하지 않는다.

## 홈 feed (`/`)

- 홈에는 기존 개인·사회적 관계 기반 Jjaek과 BookActivity만 표시한다.
- 현재 public, book-friend, follow, target relationship 등 personal Jjaek eligibility는 유지하되 `group_id`가 있는
  Group Jjaek과 Group Book Jjaek은 visible/hidden 여부와 관계없이 제외한다.
- eligibility를 먼저 결정한 뒤 moderation state를 적용한다. moderation 때문에 home read scope를 넓히지 않으며,
  hidden placeholder도 원래 home eligibility를 만족하는 personal Jjaek에만 표시한다.

## 동아리 index (`/groups`)

### 내 동아리 바로가기

- 전체 discoverable Group 목록 대신 현재 사용자가 active membership으로 속한 Group 카드만 표시한다.
- 기존 Group card 디자인과 상세 링크를 재사용한다. 가입하지 않은 Group은 표시하지 않는다.
- 받은 초대 영역은 기존 가입 lifecycle이므로 유지하되 내 동아리 카드나 activity feed 범위에는 포함하지 않는다.
- global admin의 별도 운영 조사·inventory 권한과 direct access는 유지한다. 사용자-facing `/groups`의 내 동아리 영역과
  activity feed는 global admin도 자신의 membership 범위를 따르며, 이 화면을 운영 inventory로 사용하지 않는다.
- 가입한 Group이 없으면 기존 서비스 어휘를 우선한 별도 empty state를 표시한다.

### 최근 동아리 활동

- active membership으로 속해 있고 기존 `GroupPolicy#read_jjaeks?`를 만족하는 Group들의 Group Jjaek과
  Group Book Jjaek을 하나의 feed로 표시한다.
- 여러 Group의 글은 `created_at DESC, id DESC`로 안정적으로 정렬한다.
- 각 글은 기존 Jjaek partial, actions, comments와 Group context header를 재사용한다.
- 읽을 수 없는 Group의 콘텐츠는 URL이나 query parameter 조작 여부와 관계없이 relation에 포함하지 않는다.
- Group은 있지만 표시할 게시물이 없으면 내 동아리 empty state와 구분되는 최근 동아리 활동 empty state를 표시한다.

## 특정 동아리 (`/groups/:id`)

- 기존 Group 상세, 게시물 흐름, lifecycle과 권한을 변경하지 않는다.

## 권한과 moderation

- 서버측 relation/scope에서 먼저 active membership과 Group read policy에 맞는 Group 범위를 한정한 뒤 feed를 만든다.
- eligibility first, moderation state second 원칙과 기존 hidden placeholder, hidden original inspection,
  hidden read-actions 및 author/global admin/Group admin의 특별 조회 경계를 그대로 유지한다.
- Group admin과 global admin의 권한을 확대하거나 축소하지 않으며 moderation policy/service를 변경하지 않는다.

## 구현 원칙

- 기존 home `FeedScope`의 personal eligibility 구조는 유지하고 Group records 합성만 제거한다.
- 기존 Group membership/read scope와 Jjaek partial을 재사용한다.
- Group activity feed는 DB relation에서 정렬하고 현재 프로젝트의 서버 pagination 방식이 있으면 재사용한다.
  전량을 Ruby로 load한 뒤 정렬하지 않는다.
- 필요한 association을 preload해 N+1을 피하고 query, 정렬과 권한 판단을 view에 두지 않는다.
- 새 feed framework나 불필요한 abstraction 없이 읽기 쉬운 Rails 코드로 최소 구현한다.

## Acceptance criteria

1. home에는 personal Jjaek의 기존 eligibility가 유지되고 Group Jjaek과 Group Book Jjaek은 visible/hidden 모두 표시되지 않는다.
2. `/groups`의 Group 카드는 active membership으로 속한 Group만 표시하고 가입하지 않은 전체 Group 목록은 제거한다.
3. `/groups`는 읽을 수 있는 내 Group들의 일반 짹과 책짹을 `created_at DESC, id DESC` 통합 feed로 표시한다.
4. Group activity card는 기존 context, actions와 comments를 유지하고 어느 Group의 글인지 식별할 수 있다.
5. 기존 Group read boundary 밖 콘텐츠는 visible/hidden 모두 표시되지 않는다.
6. hidden Group Jjaek은 기존 authority별 placeholder, original inspection과 read-action 경계를 유지한다.
7. 내 Group과 최근 동아리 활동의 empty state는 각각 독립적으로 표시된다.
8. `/groups/:id`, 초대, Group lifecycle과 moderation 권한은 회귀하지 않는다.

## 제외 범위

- 전체 동아리 탐색 전용 페이지, 검색, 추천, 관련 동아리 UI와 가입 추천 알고리즘
- Classroom, Comment moderation, notification 변경
- Group lifecycle·가입 정책 변경
- 새 feed framework, schema와 migration


## A12 Delta Specs — 목록 로딩 `(확정)`

### Proposal — 목적과 범위

전체 활동을 메모리에 적재하던 흐름을 제한된 페이지 조회로 바꾼다. 적용 대상은 홈 `/`,
프로필 `/users/:id` 최근 활동, `/groups` 통합 활동, `/groups/:id` 글 목록,
`/books/:id` 책짹 목록(개인·동아리 문맥)이다. 작성 폼·상단 정보·도서 카드와 다른 섹션,
Pundit scope·visibility·moderation 정책은 유지한다. A05 사용자 목록·모달은 제외한다.

### Specs — ADDED / MODIFIED / REMOVED

- **ADDED:** 최초·후속 페이지는 각각 최대 20개다. 하단 접근 시 자동 로딩하며 진행 중 요청과
  이미 성공한 같은 cursor 요청을 중복 실행하지 않는다. 다음 페이지가 없으면 로딩을 종료한다.
- **ADDED:** 실패 시 기존 카드를 유지하고 자동 재요청을 멈춘다. 같은 다음 소식 링크로 재시도할 수 있다.
  JavaScript가 없어도 이 링크의 HTML 페이지에서 다음 20개를 읽을 수 있다.
- **ADDED:** 빈 목록은 기존 화면별 빈 상태, 마지막 페이지는 공통 종료 안내를 표시한다.
  변조·잘못된 구조의 cursor는 HTML·Turbo 모두 `400 Bad Request`로 거부한다. 빈 cursor는 최초 페이지다.
- **MODIFIED:** 모든 피드는 `created_at DESC, 타입 순위 DESC, id DESC`로 정렬한다.
  타입 순위는 Jjaek=1, BookActivity=0으로, 동일 시각에는 Jjaek이 먼저이고 각 타입 안에서는 ID 내림차순이다.
  단일 Jjaek 목록은 `created_at DESC, id DESC`가 된다.
- **MODIFIED:** 기존 카드·댓글 문맥·좋아요·다시짹은 유지한다. 독서 상태·visible requote count는
  실제 표시하는 페이지의 Jjaek에만 준비하고 작성자·대상 사용자·인용 원문 작성자의 avatar preload를 유지한다.
- **REMOVED:** 홈·프로필에서 양쪽 전체 목록을 `to_a`로 읽어 합성하는 방식을 제거한다.

### Design — cursor와 조회

- `FeedPage`는 이미 권한이 적용된 Relation만 입력받는다. 마지막 표시 항목의
  `[created_at(마이크로초), 타입 순위, id]`를 서명한 cursor를 사용하며 OFFSET은 사용하지 않는다.
- 후속 조회는 정렬 tuple이 cursor보다 작은 항목만 선택한다. 다른 화면의 유효 cursor를 재사용해도
  해당 요청의 현재 policy scope·동아리·책 문맥을 다시 적용하므로 권한을 확대하지 않는다.
- 각 소스는 다음 페이지 확인용 1개를 포함해 최대 21개만 DB에서 읽는다. 혼합 피드는 최대 42개를
  같은 tuple로 병합해 20개를 표시한다. 다음 cursor는 마지막 표시 항목을 기준으로 만든다.
- cursor가 가리키던 row가 삭제돼도 tuple만으로 계속 읽는다. 이미 읽은 위치보다 최신인 새 글은
  후속 페이지에 끼워 넣지 않으며 최초 페이지를 다시 열면 표시한다. 과거 시각으로 삽입된 글,
  `created_at` 수정, 읽는 도중의 권한 변화까지 snapshot으로 고정하지는 않는다.
- 명시적인 추가 조회는 GET + cursor + Turbo Stream 형식 + `X-Feed-Pagination: true` 헤더를
  모두 갖춘 요청이다. `feed_page_request?`로 홈·프로필·동아리 목록·상세·책 상세에 같은 계약을 적용한다.
  이때만 `feed-items`에 카드만 append하고 `feed-pagination`만 replace한다. 전용 헤더는
  무한 스크롤 Stimulus fetch에만 붙이며 일반 링크나 폼 제출에는 붙이지 않는다.
- 일반 방문과 폼 제출 후 리다이렉트는 Turbo Stream Accept 헤더가 남아 있어도 전체 HTML을 반환한다.
  대상 화면의 `prepare_feed_response_format`이 요청과 template lookup 형식을 HTML로 맞춘다.
  cursor만 있는 다음 링크도 기존 전체 화면과 해당 페이지를 렌더하므로 JavaScript 없이 이동할 수 있다.
  전용 헤더만 있고 cursor가 없는 요청도 최초 HTML 화면이다.
- 단일 Stimulus controller에서 IntersectionObserver·요청 상태·오류와 재시도를 처리한다.

### Tasks / 검증

1. 단일 동아리·책 피드를 cursor 조회로 제한한다.
2. 홈·프로필의 두 Relation에 같은 cursor 경계를 적용해 제한 조회 후 합성한다.
3. 동일 시각·타입 경계·추가/삭제·빈 결과·마지막 페이지·잘못된 cursor와 현재 권한 재검사를
   Model/Request spec으로 고정한다. DB instantiation 수로 소스별 21개 상한도 확인한다.
4. 자동 append·종료·실패 후 수동 재시도와 추가된 카드의 댓글 동작을 최소 System spec으로 확인한다.

코드와 spec은 작성되어 있으며 실행 검증은 사용자 담당이다.
