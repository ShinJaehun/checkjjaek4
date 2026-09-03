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
