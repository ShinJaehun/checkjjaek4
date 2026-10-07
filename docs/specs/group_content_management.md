# 동아리 콘텐츠 관리 화면

## 상태와 목적

이 문서는 동아리 관리자용 콘텐츠 관리 화면의 canonical spec이다. 구현 전 목표 정책을 정한다.
현재 Group·Jjaek·Comment의 일반 접근 정책은 `docs/architecture/authorization.md`, 기존 hide/restore 권한과 감사 정책은
`docs/specs/moderation_mvp.md`를 따른다. 이 문서는 새 **목록 화면**의 접근·표시·검색 경계를 정하며 기존 단건 moderation 권한을 확대하지 않는다.

현재 해당 동아리 관리자가 자기 Group의 Jjaek과 Comment를 thread 문맥에서 조사하고, 허용된 기존 Group moderation으로
이동할 수 있도록 `GET /groups/:id/content`를 제공한다. 시스템 관리자용 `/admin/groups/:id/content`와 조회·표현의 일부를
공유할 수 있으나 authority는 독립된다.

- 시스템 관리자: platform moderation
- 동아리 관리자: group/community moderation

이 화면은 콘텐츠 조사 목록이다. 숨김·복구 실행과 사유 입력은 기존 전용 action page에서 처리한다.

---

## 접근과 권한 경계

- 현재 해당 Group의 `group_admin`만 목록에 접근한다. 과거 관리자는 관리자 이전 즉시 접근을 잃는다.
- `active`와 `inactive`(폐쇄) Group은 접근 가능하다. 폐쇄 Group의 과거 콘텐츠 검토를 허용한다.
- platform operation suspended Group도 조회할 수 있다. 정지 자체가 과거 콘텐츠 조사 권한을 없애지 않는다.
- `pending_approval` Group에는 접근할 수 없다. 일반 회원, 다른 Group 관리자, 비로그인 사용자도 접근할 수 없다.
- `global_admin`이라는 자격만으로 이 경로에 접근할 수 없다. 해당 사용자가 실제 현재 `group_admin`인 경우에는 그
  Group 관계에 의해 접근할 수 있다. 이때도 이 화면이 platform moderation 권한을 부여하지 않는다.
- `GroupPolicy`에 목록 접근을 위한 별도 predicate(예: `view_content_inventory?`)를 둔다. 목록 접근 판정과
  Jjaek/Comment 단건 hide·restore 판정은 분리한다. 링크와 직접 요청은 각각 기존 policy의 Group predicate를 따른다.
- 조회 relation은 인가된 Group에 한정한다. 다른 Group, 개인 콘텐츠 또는 User content를 검색 결과나 thread에 섞지 않는다.

### 접근·Group 상태 acceptance matrix

아래 `목록 포함`은 해당 사용자에게 이 경로의 목록이 제공되는지를 뜻한다. 접근이 허용된 경우 개별 row의 본문·검색·조치는
뒤의 콘텐츠 상태 표와 기존 단건 policy를 함께 따른다.

| 사용자·관계 | Group 상태 | 목록 포함 | 본문 표시 | 본문 검색 | hide/restore |
| --- | --- | --- | --- | --- | --- |
| 현재 group admin | active | 자기 Group thread 포함 | 콘텐츠 상태 표 적용 | 콘텐츠 상태 표 적용 | 기존 Group predicate 적용 |
| 현재 group admin | inactive/closed | 과거 자기 Group thread 포함 | 콘텐츠 상태 표 적용 | 콘텐츠 상태 표 적용 | 새 hide 금지; 기존 Group restore predicate만 가능 |
| 현재 group admin | operation suspended인 active/inactive | 과거 자기 Group thread 포함 | 콘텐츠 상태 표 적용 | 콘텐츠 상태 표 적용 | 기존 policy에 따라 hide/restore 모두 금지 |
| 현재 group admin | pending/미승인 | 접근 불가 | 없음 | 불가 | 없음 |
| 일반 회원 | 상태와 무관 | 접근 불가 | 없음 | 불가 | 없음 |
| 다른 Group 관리자 | 상태와 무관 | 접근 불가 | 없음 | 불가 | 없음 |
| 비로그인 사용자 | 상태와 무관 | 접근 불가 | 없음 | 불가 | 없음 |
| 해당 Group 관리자 관계가 없는 global admin | 상태와 무관 | 접근 불가 | 없음 | 불가 | 없음 |
| 해당 Group의 현재 group admin이기도 한 global admin | active/inactive, operation suspended | 해당 Group 관계로 목록 포함 | 콘텐츠 상태 표 적용 | 콘텐츠 상태 표 적용 | 기존 Group predicate 적용; platform action은 표시하지 않음 |

`operation suspended`는 lifecycle과 별도 상태다. `pending/미승인`에 operation 상태가 겹쳐도 접근 불가가 우선한다.
global admin 겸직자의 Group 조치 가능 여부도 기존 `JjaekPolicy`·`CommentPolicy`의 Group predicate 결과가 최종 기준이다.

---

## Thread와 필터

시스템 관리자 Group content에서 확정된 thread semantics를 유지한다.

- thread는 root Jjaek과 그 Comment 전체로 이뤄진다. Comment는 최신 `created_at`부터 표시하고 root는 항상 마지막에 둔다.
- `latest_activity_at`은 root와 해당 thread Comment의 `created_at` 중 최신 시각이다.
- 기본 정렬은 최근 활동순(`recent`)이며 오래된 활동순(`oldest`)도 제공한다. 동시각에는 안정적인 ID 순서를 사용한다.
- 페이지네이션 단위는 root thread다. 한 thread를 페이지 사이에서 쪼개지 않는다.
- root 또는 Comment 하나가 유형·상태·검색 조건에 일치하면 그 **전체 thread**를 표시한다. 검색 일치 여부와 row 표시
  권한은 별개이며, 전체 thread의 각 row에도 아래 본문 경계를 적용한다.
- 유형은 `all`, `general`(책 연결 없는 root), `book`(책 연결된 root), `comments`(Comment가 있는 thread)다.
- 상태는 `active`, `hidden`, `deleted`다. root 또는 Comment의 현재 상태로 thread를 선택한다. `deleted`는 삭제된
  root에만 적용하며 Comment에 별도 삭제 상태를 만들지 않는다.
- 검색·유형·상태 조건은 thread 선택 전에 함께 적용한다. 페이지 이동 시 현재 조건과 정렬을 보존하고 필터 변경 시
  첫 페이지부터 조회한다. 잘못된 유형·상태·정렬·페이지 입력은 안전한 기본값으로 처리한다.

---

## 목록 본문과 검색의 정보 경계

목록 relation에 row가 포함되는 것과 실제 본문을 출력하거나 검색할 권한은 별개다. 이 화면은 기존 단건 상세의 특별 열람
규칙과 독립된 **목록 전용 출력·검색 경계**를 적용한다. 특히 platform-hidden 원문을 다른 화면에서 조사할 수 있더라도
이 Group 관리 목록의 본문·HTML 속성·검색 결과에는 실어 보내지 않는다.

| 콘텐츠 현재 상태·authority | 목록 포함 | 본문 표시 | 본문 검색 | 작성자 이름 검색 | 행의 hide/restore |
| --- | --- | --- | --- | --- | --- |
| visible, 삭제되지 않음 | 포함 | 실제 본문 | 가능 | 가능 | 기존 `hide_as_group_admin?`이 허용하면 hide |
| group authority로 hidden, 삭제되지 않음 | 포함 | 실제 본문 | 가능 | 가능 | 기존 `restore_as_group_admin?`이 허용하면 restore |
| platform authority로 hidden, 삭제되지 않음 | 포함 | tombstone: 시스템에 의해 숨겨진 콘텐츠 | 불가 | 가능 | Group restore 및 platform action 없음 |
| deleted root | 포함 | tombstone: 삭제된 콘텐츠 | 불가 | 가능 | 조치 없음 |

- 삭제와 hidden이 겹치면 삭제 tombstone이 우선한다. 삭제 전 본문은 표시하거나 검색하지 않는다.
- hidden의 authority는 현재 hide의 저장된 snapshot을 기준으로 판단한다. 현재 actor 역할이나 작성자의 역할에서
  authority를 추론하지 않는다.
- platform-hidden 콘텐츠의 실제 본문, platform internal note 및 platform moderation history는 목록 HTML, 링크,
  속성, excerpt, 검색 결과에 노출하지 않는다. Group-origin 감사 정보도 이 목록에 새로 펼치지 않으며 기존 단건
  화면의 허가된 경계를 따른다.
- 작성자 이름은 위 네 상태 모두 검색 가능하다. 검색으로 일치한 thread를 열어도 각 row의 본문은 표의 경계를 따른다.
- 시스템 관리자 검색은 기존처럼 본문·작성자 이름·작성자 이메일을 대상으로 한다. Group 관리자 검색에서는 작성자
  이메일을 제외하고 **이 화면에 실제 표시 가능한 본문**과 작성자 이름만 검색한다. platform-hidden 및 deleted
  본문은 DB에 값이 남아 있더라도 검색 조건에 사용하지 않는다.
- 본문 검색 허용은 해당 row의 현재 상태를 기준으로 root와 Comment에 각각 적용한다. hidden parent가 있다고 해서
  Comment 본문까지 자동으로 숨기거나, visible parent가 있다고 hidden Comment 본문을 노출하지 않는다.
- 작성자 본인의 콘텐츠도 이 목록에서는 같은 상태 표를 적용한다. 단건 화면의 author-first 정책 및 자기 moderation
  금지는 그대로 유지한다.

---

## Moderation action과 authority

새 moderation action을 만들지 않는다. Jjaek group hide/restore와 Comment group hide/restore의 기존
route, controller, service, policy 및 사유 입력 화면을 그대로 사용한다.

- 각 row의 링크는 대상 Jjaek 또는 Comment의 기존 `hide_as_group_admin?`·`restore_as_group_admin?` 결과로만 결정한다.
  목록을 볼 수 있다는 이유로 action을 표시하지 않는다. 직접 GET/POST에서도 기존 policy와 service가 재검사한다.
- Group 화면에는 platform hide/restore route를 연결하지 않는다. platform-hidden 콘텐츠에는 Group restore 링크가 없다.
- 자기 콘텐츠, 기존 policy가 금지하는 global admin 작성 콘텐츠, 다른 Group 콘텐츠, 삭제된 Jjaek 및 lifecycle·운영
  상태 때문에 금지된 조치는 이 목록을 통해 가능해지지 않는다.
- 시스템 관리자는 platform authority, 동아리 관리자는 group/community authority로 조치한다. 동일 대상의 현재
  hidden 상태를 공유하더라도 권한 predicate, action route, 감사 authority snapshot은 합치지 않는다.
- 목록은 사유·내부 메모 입력, 운영 이력 전문, 별도 moderation mutation을 제공하지 않는다. 단건 화면과 기존 action
  page에서 이미 허가된 조사·조치를 이어간다.

---

## Route, query, view와 navigation

- `GET /groups/:id/content`는 `Groups::ContentsController#index`가 담당한다. `GroupsController`에 `content`
  action을 추가하지 않는다.
- controller는 Group 목록 접근을 `GroupPolicy`로 승인받고 자기 Group에 한정된 Jjaek/Comment relation을 준비한다.
  Admin controller는 현재 `AdminInventoryScope`를 유지한다. 이를 generic scope로 변경하지 않는다.
- 현재 `Admin::GroupContentThreadQuery`의 thread 선택·필터·정렬·페이지네이션·hydration은 공유 후보이다.
  먼저 admin과 Group 각각의 query contract를 spec으로 고정한 뒤 공통 thread mechanics만 추출한다. 단순 rename이나
  이동으로 두 검색 경계를 합치지 않는다. Group query에는 작성자 이메일 및 비노출 본문 검색이 들어가지 않는다.
- admin content page 전체를 재사용하지 않는다. header, filter form, navigation, admin 전용 링크와 action은
  각 화면에 둔다. thread table 구조, row 유형·상태 표현, 페이지네이션은 실제 중복이 확인될 때만 공유한다.
  공유 partial은 `admin_user_path` 또는 platform action route를 내부에 하드코딩하지 않는다.
- Group 상세 `/groups/:id`의 회원 관리·동아리 수정과 같은 관리 action 영역에 `콘텐츠 관리` 진입점을 둔다.
  콘텐츠 관리 화면에는 Group 상세로 돌아가는 링크를 둔다. 진입점도 목록 접근 predicate를 따른다.
- 새 사용자 문구와 tombstone은 locale에 정의한다. 이 문서는 표현 정책만 확정하며 이번 단계에서 locale 파일은
  수정하지 않는다.

---

## MVP 제외 범위

- platform moderation 권한·경로·서비스 변경 및 global admin 권한 확대
- GroupMembership moderation 변경
- 신고 기능, 삭제 기능 추가, 새 moderation action·authority, moderation service 통합
- DB/schema 변경, User content 화면 변경

---

## 검증 기준

- 위 접근·Group 상태 matrix의 직접 URL 접근과 Group 관리자 이전 후 권한 변경을 policy/request spec으로 고정한다.
- 콘텐츠 상태·authority matrix를 root Jjaek과 Comment 각각 검증한다. 특히 목록 HTML과 검색에서 platform-hidden
  및 deleted 본문·platform 내부 메모/이력이 누출되지 않는지 확인한다.
- Group 관리자 화면은 작성자 이름·실제 표시가 허용된 본문만, admin 화면은 작성자 이름·작성자 이메일·허용된 admin 본문을 검색하는지 두 query contract로 고정한다.
- 필터에 한 row가 일치할 때 전체 thread가 표시되고, 댓글 최신순·root 마지막·최근 활동 정렬·thread 페이지네이션이
  유지되는지 검증한다.
- action 링크와 직접 요청이 기존 Group predicate를 따르는지 확인한다. 자기 콘텐츠, global admin 작성자,
  platform hide, inactive/pending/operation suspended 및 다른 Group 경계를 포함한다.
- 기존 admin Group content request spec의 조회·필터·검색·페이지 동작을 회귀 검증한다. HTML 구조 세부사항보다
  권한, 정보 노출, thread 결과와 navigation을 우선한다.

## 구현 순서

1. canonical spec 승인
2. policy + route/controller contract
3. admin/group query spec
4. thread query 공용 경계 추출
5. Group content view/navigation
6. 기존 group hide/restore 연결
7. request/policy/query regression
8. architecture 문서 동기화
