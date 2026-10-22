# 동아리 MVP

## 목적

이 문서는 일반 사용자용 동아리 기능의 canonical 제품 정책을 정리한다.

동아리는 일반 사용자가 함께 읽고 기록하고 토론하는 독서 공동체다.
내부적으로 `Group` 모델과 `GroupMembership` 모델로 구현한다.
현재 구현 사실은 `docs/architecture/current_system.md`와 `docs/architecture/authorization.md`를 따르며,
이 문서는 구현된 기능과 아직 남은 목표 정책을 구분한다.
계정 탈퇴와 Group 승인·운영 lifecycle의 목표 정책은
`docs/specs/account_group_lifecycle.md`를 canonical 기준으로 본다.

---

## 현재 상태

동아리 기반은 현재 다음 범위까지 구현되어 있다.

- `Group`과 `GroupMembership`
- 공개·승인·비공개 동아리의 사용자 생성
- 발견 가능한 동아리 및 active membership이 있는 비공개 동아리의 목록 조회
- 공개 동아리 즉시 가입
- 승인 동아리 가입 요청·요청 취소·동아리 관리자 승인
- `/groups`의 내 동아리 카드에서 본인이 관리하는 승인 동아리의 현재 pending 신청이 있으면 “가입 승인 대기 N건” 링크를 표시한다. 기존 회원 관리 페이지로 연결하며, 일반 회원·공개/비공개 동아리·0건에는 표시하지 않는다. 회원 관리의 pending 조회 기준을 그대로 사용하고 건수는 목록 전체에 대해 한 번에 집계한다.
- 일반 active member 탈퇴와 현재 관리자 membership 삭제 방지
- 비공개 동아리의 관리자/active member 조회 권한 기반
- 비공개 동아리 생성과 관리자의 기존 사용자 초대
- 받은 초대의 수락·거절
- 동아리 관리자의 이름·소개 수정과 다른 active member로의 관리자 권한 이전
- 동아리 관리자의 active 구성원 내보내기, 승인 요청 거절, 보낸 초대 취소
- membership 가입·신청·승인·거절·초대·수락·거절·취소·탈퇴·내보내기를 Group 단위 append-only 이력으로 보존
- 동아리 안의 `짹`과 `책짹` 작성·조회
- 권한 있는 사용자의 작성자 프로필에서 동아리의 `짹`과 `책짹` 조회
- 일반 사용자의 동아리 신청과 global admin 승인·최초 개설 신청 거절, 신청자 본인의 승인 전 취소
- 동아리 관리자의 동아리 운영 종료와 재활성화 요청·재승인, 시스템 관리자의 재운영 신청 거절과 현재 동아리 관리자의 신청 철회
- 신규 신청의 개설 목적과 운영 종료 사유·시각 기록
- 신청·승인·운영 종료·재활성화·재승인의 시각과 목적/사유 snapshot을 운영 이력으로 누적
- Group lifecycle은 `lifecycle_status`와 `GroupLifecycleEvent`, global admin의 platform 운영 정지는 `operation_suspended_at`과 Group 대상 `ModerationAction`으로 서로 분리
- 동아리 관리자 화면과 global admin 운영 상세에서 lifecycle event와 platform operation suspend/restore action을 실제 event 단위의 시간순 운영 이력으로 표시
- 동아리 관리자는 lifecycle detail과 platform 공개 사유를 보고, global admin은 platform 내부 메모까지 포함한 전체 운영 이력을 조사
- admin Group 목록·상세에서 lifecycle, 재활성화 대기와 platform 운영 정지를 반영한 통합 현재 상태를 표시하고, 현재 가능한 운영 정지·복구 action이 없으면 운영 관리 card를 표시하지 않음
- User 계정 정지와 Group 운영 정지의 신규 조치는 각각 정의된 predefined 공개 사유를 사용하고 기존 자유 텍스트 감사 row는 그대로 표시
- GroupMembership의 별도 `moderation_status` 기반 활동 정지·복구와 `GroupMemberBan` 기반 이용 제한·해제
- 회원 관리 화면에서 `GroupMembershipEvent`와 GroupMembership·GroupMemberBan 대상 `ModerationAction`을 실제 사건 단위의 통합 회원 운영 이력으로 표시
- Group admin과 global admin의 권한 경계에 따른 Group Jjaek·Comment 숨김·복구 및 append-only 감사 이력
- 개인 원문의 동아리 다시짹과 같은 동아리 안의 다시짹, 경로별 원문 삭제 후 처리
- 현재 동아리 관리자의 thread 기반 콘텐츠 관리 화면과 기존 hide/restore action 연결

비공개 동아리는 사용자 생성 UI에서 제공하며, 동아리 관리자가 기존 사용자를 초대할 수 있다.
초대는 `GroupMembership`의 `invited` 상태로 표현하고 수락하면 `active`, 거절하면 삭제한다.
초대 상태만으로 동아리나 내부 콘텐츠 조회 권한을 얻지는 않는다.
동아리 종류는 생성 후 변경하지 않는다.
일반 membership 상태는 `pending` / `invited` / `active`만 사용한다.
일반 member의 자발적 탈퇴와 동아리 관리자의 내보내기는 membership을 즉시 삭제한다.
내보내기는 ban이 아니며 이후 기존 Group 유형에 따라 재가입·재신청·재초대할 수 있다.
동아리 이용 제한은 `GroupMemberBan`으로 현재 Group/User 제한 상태를 보존하고 membership을 종료해 가입·신청·승인·초대·수락을 차단한다.
global admin의 동아리 운영 정지는 nullable `operation_suspended_at`으로 현재 상태를 보존하며 group admin의 자발적 `inactive` 운영 종료와 구분한다. 정지 중 기존 visibility 읽기와 자기 콘텐츠 삭제·Like 철회는 유지하고 새 콘텐츠·membership·회원 moderation·Group 운영 mutation은 차단하며, 복구는 lifecycle·membership·User suspension·GroupMemberBan을 변경하지 않는다.
해제는 ban marker만 제거하며 membership을 자동 복구하지 않는다.

`GroupMembership`은 현재 membership 상태, `GroupMembershipRemoval`은 관리자 내보내기 후 private Group stale URL UX를
구별하는 현재 표식, `GroupMembershipEvent`는 membership lifecycle의 append-only history다. 활동 정지·해제는
`ModerationAction`에만 기록한다. membership이 탈퇴·내보내기로 삭제되거나 removal 표식이 재가입으로 삭제되어도
과거 lifecycle event와 moderation audit는 보존한다.
GroupMembership 대상 `ModerationAction`은 membership hard delete 후에도 어느 Group의 어느 User에 대한 조치인지
식별할 수 있도록 `membership_group_id`와 `membership_user_id`를 historical attribution snapshot으로 보존한다.
이 값은 현재 membership 관계나 FK가 아니다.
동아리 이용 제한·해제는 `GroupMemberBan` 대상 `ModerationAction`으로 사유·처리자와 Group/User historical attribution을 보존하며
일반 내보내기 `removed` lifecycle event로 중복 기록하지 않는다. group admin만 해당 Group의 활동 정지·해제와 이용 제한·해제를
실행하고 global admin은 회원·제한·감사 이력을 운영 조사 목적으로만 조회한다.
개인 Jjaek의 동아리 다시짹과 같은 동아리 안의 다시짹은 구현되어 있으며
상세 경로와 원문 삭제 후 처리는 `docs/specs/group_sharing_requotes.md`를 따른다.
이메일·초대 링크를 통한 가입은 기존 사용자 초대와 별개의 미구현 후속 후보로 남아 있다.
신고 queue와 별도 platform moderator 역할은 `docs/specs/moderation_mvp.md`에서 다룬다.

또한 여기서 사용하는 `visibility`, `discoverability`, `join policy`는 제품 정책을 설명하기 위한 개념적 구분이다. 실제 DB column, enum, association 구조를 확정하지 않는다.

---

## 핵심 설계 원칙

- 동아리는 일반 사용자들의 독서 공동체다.
- 개인 Jjaek의 관계 기반 visibility와 동아리라는 게시 공간의 접근 정책을 분리한다.
- 글의 열람 권한은 게시 공간이 정한다.
- 댓글은 부모 글의 열람 권한을 상속하고, 별도 visibility를 갖지 않는다.
- 동아리에서 글과 댓글을 작성하는 행위는 현재 동아리 멤버에게만 허용한다.
- 게시 공간보다 넓은 곳으로 콘텐츠가 자동으로 확산되지 않는다.
- 다른 공간으로 공유하면 원문은 참조하되 토론은 새 공간에서 새로 시작한다.
- Classroom은 Group의 SNS·콘텐츠 접근 정책을 재사용할 수 있지만, Group lifecycle을 자동 적용하지 않는다.

핵심 원칙을 한 문장으로 정리하면 다음과 같다.

> 글의 열람 권한은 게시 공간이 정하고, 댓글은 그 글의 열람 권한을 상속하되 동아리에서의 작성 행위는 동아리 멤버에게만 허용한다. 다른 공간으로 공유하면 원문은 참조하되 토론은 새 공간에서 새로 시작한다.

---

## 동아리 종류

사용자에게는 우선 다음 세 가지 프리셋을 제공한다.

### 공개 동아리

- 로그인 사용자는 동아리와 게시물·댓글을 볼 수 있다.
- 누구나 바로 가입할 수 있다.
- 게시물과 댓글 작성은 현재 멤버만 가능하다.

### 승인 동아리

- 동아리 자체는 검색하고 발견할 수 있다.
- 게시물과 댓글은 현재 멤버만 볼 수 있다.
- 가입하려면 동아리 관리자의 승인이 필요하다.

### 비공개 동아리

- 일반 검색·발견 대상이 아니다.
- 초대받은 사용자를 중심으로 가입한다.
- 게시물과 댓글은 현재 멤버만 볼 수 있다.

세 프리셋은 개념적으로 다음 세 축으로 설명할 수 있다.

- visibility: `public` / `private`
- discoverability: `visible` / `hidden`
- join policy: `open` / `approval` / `invite-only`

이는 제품 정책을 설명하기 위한 구분이며, 구현 필드나 enum 설계가 아니다.

---

## 내 동아리 목록 표시

- `/groups`는 독서 동아리 타이틀 → 내 동아리 → 최근 동아리 소식의 단일 열 구조를 유지하며 사이드바를 추가하지 않는다. 최근 동아리 소식의 기존 짹·책짹 피드, 정렬·조회 정책, 무한 스크롤·댓글·액션은 유지한다.
- 내 동아리의 현재 회원 목록은 `GroupPolicy::MembershipScope`, 과거 실제 참여 목록은 `PastMembershipScope`를 기준으로 하며 현재 회원 뒤에 과거 동아리를 표시한다. 목록에서 제외한 동아리는 표시하지 않는다. 개인 순서를 저장하기 전에는 기존 동아리 최신 생성순(`groups.created_at DESC, groups.id DESC`)으로 표시한다. 0개는 기존 빈 상태, 1개는 정적 그리드로 표시한다.
- 2개 이상이면 하나의 캐러셀에서 모바일(`md` 미만) 1개, 태블릿(`md` 이상·`lg` 미만) 2개, PC(`lg` 이상) 3개를 한 줄에 표시한다. 예: PC의 4개는 `[1~3] / [4]`, 7개는 `[1~3] / [4~6] / [7]`이다. 전체 개인 순서를 유지하고 카드 중복이나 추가 목록을 만들지 않는다.
- 이전/다음 버튼, 방향키·Home·End, 가로 스와이프와 `1 / 3` 형태의 페이지 표시를 유지한다. 첫 페이지의 이전 버튼과 마지막 페이지의 다음 버튼은 비활성화하며, 해당 화면 너비에서 한 페이지면 탐색 컨트롤을 숨긴다. 현재 페이지 외의 카드는 숨겨 키보드 탐색 대상에서 제외한다. 화면 크기 변경 시 포커스된 카드 또는 현재 첫 카드를 포함하는 페이지를 표시하며, 숨겨지는 카드·컨트롤의 포커스는 viewport로 옮긴다. 모든 동아리는 너비 변경 후에도 탐색할 수 있다.
- 현재 회원 카드는 단일 그리드와 캐러셀의 모든 페이지에서 같은 group_card partial을 사용하며 가입 상태·운영 상태·관리자 정보·가입 승인 대기 링크를 동일하게 표시한다. 기존 policy scope, 현재 사용자 membership 일괄 조회와 pending 단일 집계를 유지하고, 이미 로드한 목록을 분할하여 추가 DB 조회나 중복 카드 없이 렌더링한다.
- 카드의 제목·배지·가입 승인 대기 링크를 유지하면서 padding·배지 사이 간격을 줄인다. 관리자 아바타·이름과 회원 정보를 하단 한 줄에 표시하고 별도 관리자·회원 라벨의 수직 공간은 제거한다. 관리자 역할과 회원 영역은 기존 번역을 사용한 접근성 label로 구분한다. 관리자·회원 프로필 링크, 활성 일반 회원 아바타 최대 3개와 전체 회원 수는 유지한다. 회원 아바타는 작게 겹쳐 표시하고 회원 수는 기존 `groups.active_member_count`를 사용한다. 관리자는 일반 회원 수·미리보기에서 제외하고 `GroupMembership.active`만 집계한다. pending·invited는 제외하며 활동 정지와 membership의 active 여부는 구분한다.
- 회원 미리보기는 membership의 가입 시각(`created_at`)과 ID 오름차순이다. 각 아바타는 `user_avatar_image`를 사용하고 해당 회원 프로필로 연결한다. 일반 회원이 0명이면 회원 아바타 없이 “회원 0명”을 표시한다.
- 회원 정보는 현재 회원인 동아리 카드에 대해서만 일괄 조회한다. SQL window count와 순위를 사용해 전체 활성 일반 회원 수를 계산하면서 Group마다 최대 3개의 membership만 로드하고 사용자·아바타도 preload한다. count와 preview를 partial의 명시적인 local로 전달하며 카드별 쿼리, 다른 동아리 정보 혼입이나 접근 범위 확대를 허용하지 않는다. 상세 화면의 회원 표시와 기존 membership 순서 저장 검증은 유지한다.

### 개인별 표시 순서 `(현재 구현)`

- “내 동아리” 제목 옆의 “순서 변경”으로 `/groups/membership_order/edit`에 진입한다. 캐러셀 페이지 구분 없이 현재 회원 동아리를 정렬하고 과거 동아리와 목록에서 제외한 동아리도 같은 화면에서 관리한다. 현재 2개 이상이거나 과거/제외/제거 가능한 동아리가 있으면 진입 버튼을 표시한다.
- 순서 편집 화면은 번호·별도 손잡이 없이 PC에서 기존 SortableJS로 카드 전체를 드래그하고 모바일에서만 ↑·↓ 버튼을 표시한다. 모바일 버튼의 aria-label은 유지하고 첫 항목의 위로·마지막 항목의 아래로 버튼은 비활성화한다.
- 저장 전 조작은 화면 안에서만 반영한다. 저장하면 `PATCH /groups/membership_order`를 통해 전체 순서를 저장하고 `/groups`로 돌아간다. 취소는 저장하지 않고 `/groups`로 돌아간다.
- `GroupMembership.position`에 사용자별 순서를 저장하며 순서용 별도 설정 테이블이나 Group 공통 순서를 만들지 않는다. membership과 독립적인 목록 숨김만 `GroupListHiding`에 저장한다. 기존 membership과 새 membership의 기본값은 `NULL`이고 기존 데이터 backfill은 필요하지 않다.
- 저장된 position의 오름차순을 먼저 표시하고 position이 없는 새 가입 동아리는 그 뒤에 기존 동아리 최신 생성순으로 표시한다. 가입 승인·초대 수락으로 새롭게 active가 된 membership도 같은 규칙을 따른다. 탈퇴·내보내기·이용 제한으로 membership이 삭제되면 순서도 함께 사라진다. 남은 position의 빈 번호는 정리하지 않으며 같은 동아리에 재가입해도 새 membership으로 뒤에 표시한다.
- 정렬 대상은 `MembershipScope`가 허용한 Group에 대한 본인의 목록에서 제외하지 않은 active membership 전체다. 과거 동아리는 정렬 대상에 포함하지 않는다. pending·invited membership과 신규 개설 거절·취소 Group은 포함하지 않는다. Group lifecycle·운영 정지·회원 활동 정지에 따른 기존 목록·읽기·관리 권한은 변경하지 않는다.
- 서버는 요청 membership ID 배열과 현재 편집 대상 전체를 transaction 안에서 비교해 중복·누락·타인·대상 밖·잘못된 ID와 변경된 목록을 거부한다. 사용자별 저장을 직렬화하고 해당 사용자의 membership 행을 잠가 현재 상태를 검사한다. position 저장과 저장 중 추가된 membership에 대한 재검사까지 원자적으로 처리한다.
- 실패하면 position 변경을 rollback하고 현재 목록과 오류를 HTTP 422로 표시한다. 성공한 순서는 새로고침 후에도 유지하며 다른 사용자의 순서에는 영향을 주지 않는다.
- 기존 group_card partial·최근 동아리 소식의 피드와 개인별 순서 저장 로직을 유지한다. 먼저 전체 개인별 순서를 정한 뒤 `group_carousel_controller.js`가 화면 너비에 따라 1·2·3개씩 표시한다. 조회·검증·저장 로직은 `GroupMembership`, 순서 편집 조작은 별도 `group_membership_sort_controller.js`가 담당한다.

## 가입·발견 정책

- 공개 동아리는 발견 가능하며 로그인 사용자가 즉시 가입할 수 있다.
- 승인 동아리는 발견 가능하지만 가입 승인이 필요하다.
- 비공개 동아리는 일반 발견 대상에서 제외하며 초대를 기본 진입점으로 삼는다.
- 비공개 동아리의 새 초대는 대상 사용자의 프로필에서 시작한다. 관리 중인 초대 가능한 비공개 동아리가 여러 개면 한 동아리를 선택해 한 번에 한 명만 초대한다. 기존 pending 초대는 대상 프로필과 `/groups/:id/members` 양쪽에서 취소할 수 있다. 두 화면 모두 같은 revoke action과 `GroupMembershipPolicy#revoke?`를 사용한다.
- 초대 후보는 대상의 `accepts_group_invitations` 설정과 기존 membership·이용 제한을 반영하며, 최종 권한은 `GroupMembershipPolicy#invite?`가 확인한다. 초대 workflow Notification은 `docs/specs/notifications_mvp.md`를 따른다.
- 일반 사용자의 생성을 운영 신청으로 보고, global admin 승인 전에는 정상 운영하지 않는다.
- 일반 사용자의 동시 신규 개설 승인 대기는 최대 1개다. 최초 `pending_approval`이며 `closed_at`이 없는 신청만 집계하고 생성 POST에서 User 행 잠금으로 동시 요청까지 제한한다. 재활성화 승인 대기·운영 중·운영 종료·과거 거절/취소는 제외하며, 기존 5회/24시간 rate limit과 회원 가입 정책은 유지한다.
- 최초 신청은 global admin이 필수 500자 이하 사유로 거절하거나 현재 group admin 본인이 확인 후 취소할 수 있다. `rejected` / `cancelled`와 `opening_rejected` / `opening_cancelled` event로 결과·처리자·시각을 보존한다. 승인·거절·취소 시 Group 행 잠금 안에서 현재 권한과 상태를 다시 검사한다.
- 거절·취소된 Group은 내 동아리 운영 목록·발견·활동 피드에서 제외한다. 신청자와 global admin만 관리 문맥에서 결과·사유·이력을 확인하며 같은 Group의 재승인·재활성화는 허용하지 않는다. 다시 신청하려면 새 Group을 생성한다.
- `closed_at`이 있는 재운영 승인 대기는 global admin이 필수 500자 이하 사유로 거절하거나 현재 group admin 본인이 확인 후 사유 없이 철회할 수 있다. 두 경로는 `inactive`로 복귀하고 `reactivation_rejected` / `reactivation_withdrawn` event로 구분한다. 종료 metadata·콘텐츠·membership·기존 이력을 보존하며 같은 Group에서 재신청할 수 있다. 상태와 이력은 Group 잠금 아래 원자적으로 처리하고 중복 결정을 차단한다. 상세 정책과 기존 공개 범위는 `docs/specs/account_group_lifecycle.md`를 따른다.
- global admin이 직접 생성한 동아리는 승인 대기를 거치지 않고 즉시 `active`로 시작한다. 이는 다른 사용자가 만든 pending 동아리의 자동 승인을 뜻하지 않는다.
- 신규 신청에는 일반 소개와 별도의 동아리 개설 목적을 제출하며 group admin과 global admin만 확인한다.
- 승인·운영 lifecycle의 상세 기준은 `docs/specs/account_group_lifecycle.md`를 따른다.
- 동아리 생성 요청의 기본 rate limit은 `docs/specs/basic_rate_limiting.md`에 따라 구현되어 있다. 운영 중 동아리 총량 제한, 계정 연령과 고급 남용 방지 조건은 아직 결정하지 않는다.

---

## 동아리 Jjaek 작성·조회

현재 Jjaek의 `public_jjaek`, `book_friends`, `private_jjaek`은 사용자 관계를 기준으로 한 개인 Jjaek의 공개 범위다.
동아리는 별도의 게시 공간이므로, 동아리 접근 권한을 기존 visibility 값으로 표현하지 않는다.

- 동아리에서 새 Jjaek을 작성할 때 개인 Jjaek의 visibility 선택 UI를 그대로 제공하지 않는다.
- 동아리 Jjaek의 가시성은 해당 동아리의 접근 정책을 따른다.
- 공개 동아리에서는 동아리 비회원인 로그인 사용자도 글을 읽을 수 있지만 작성할 수 없다.
- 승인 동아리와 비공개 동아리에서는 현재 멤버만 글을 읽고 작성할 수 있다.
- 일반 열람에서는 동아리 접근 권한이 없는 경로를 통해 동아리 Jjaek을 조회할 수 없어야 한다. 아래 “내 글 정리” 예외는 본인 작성 내용 확인·삭제만 허용하며 일반 열람 권한을 부여하지 않는다.

동아리 문맥을 기존 `visibility_rank`만으로 표현할 수 있다고 전제하지 않는다.

책 상세의 새 원본 책짹 작성은 `게시 위치`에서 책짹/동아리 책짹을 선택한다.
동아리 진입 시 해당 동아리를 기본값으로 사용하고, 본문을 유지한 채 개인 게시나 다른 게시 가능한 동아리로 전환할 수 있다.
동아리 선택 목록은 현재 active 동아리, 운영 정지 없음, active·활동 정지되지 않은 membership 기준으로 제한한다.
`GroupPolicy::CreateJjaekScope`의 목록과 저장 시 `JjaekPolicy#create?`가 기존 작성 권한을 강제한다.
일반 공개 범위 선택은 개인 게시에만 표시·전송하며 동아리의 실제 공개 범위는 기존 Group 정책을 따른다.
새 책짹의 `POST /jjaeks`는 명시적인 book_post_destination과 기존 group_id를 검증한다.
누락·불일치 목적지, 미등록 서재 책, 권한 없는 동아리는 게시하지 않는다.
기존 일반 짹·nested 동아리 작성과 공유·다시짹 경로의 정책은 유지하며 이 selector를 공유·다시짹 요청에 혼합할 수 없다.
동아리 피드 작성 선택은 `짹 / 동아리 책짹`이고 책 상세 작성 카드에는 중복 선택 버튼을 두지 않는다.
개인 독서 기록과 BookActivity에는 동아리 소속을 추가하지 않는다.
세부 화면과 실패 복원 기준은 `docs/specs/bookshelf_ui.md`를 따른다.

---

## 현재·과거 동아리와 자기 콘텐츠 정리 — Delta Specs

### MODIFIED: 내 동아리와 개인별 목록 관리

- `/groups`는 현재 active membership 동아리(기존 개인별 저장 순서), 과거 실제 참여 동아리(최근 회원 자격 종료 우선)를 차례로 표시한다. 운영 종료·운영 정지·회원 활동 정지는 탈퇴가 아니다. 단순 신청·미수락 초대는 과거 참여로 인정하지 않는다.
- 실제 참여는 `GroupMembershipEvent`의 가입·승인·초대 수락·탈퇴·내보내기·관리자 역할 이력과 이용 제한 `ModerationAction`의 보존된 Group/User attribution으로 확인한다. 회원 상태 표시는 자발적 탈퇴에 “탈퇴함”, 관리자 내보내기에 “탈퇴 처리”, 현재 이용 제한에 “이용 제한”을 사용한다. 상태가 불명확하거나 이용 제한만 해제된 경우 중립적인 “이전 회원” 배지를 사용한다.
- 과거 카드에는 현재 동아리 이름·유형·운영 상태와 회원 자격 종료 상태 배지를 표시한다. `/groups`와 순서 편집·제외 영역은 기존 `past_group_card` partial을 재사용하며 옅은 회색 배경·차분한 테두리를 적용하고 blur·전체 opacity 및 카드별 참여 설명은 사용하지 않는다. 관리자·회원 정보·아바타·회원 수는 표시하지 않는다. 목록의 이 식별 정보 표시만 허용하며 제한 상세 화면이나 일반 콘텐츠 접근 권한은 확대하지 않는다. `/groups`의 링크는 숫자 ID 경로를 유지하고 편집 화면의 이름에는 링크를 추가하지 않는다. 기존 현재 회원 카드와 1/2/3개 반응형 캐러셀·최근 동아리 소식 읽기 scope는 유지한다.
- `/groups/membership_order/edit`에서 현재 회원의 순서 저장과 목록에서 제거/복원을 제공한다. “활동하지 않는 동아리” 영역은 회원 자격이 종료된 과거 동아리만 포함하고 영역 설명으로 이를 명시한다. 운영 종료·운영 정지·회원 활동 정지 중에도 active membership이 유지된 동아리는 기존 정렬 목록에 남으며 과거 회원으로 분류하지 않는다. 과거 동아리 ID는 membership 순서 저장에 포함하지 않는다. 정상 활동 가능한 현재 동아리는 제거할 수 없다. 과거·운영 종료·운영 정지·회원 활동 정지 동아리는 확인 후 제거하며 같은 화면의 제외 영역에서 복원한다.
- 목록 제거는 사용자/동아리 unique constraint를 가진 `GroupListHiding`에 저장한다. Group·membership·콘텐츠·감사 이력은 보존한다. 현재 회원의 숨김 여부와 관계없이 기존 membership 순서는 유지한다.
- Group이 active·운영 정지 없음이고 본인의 active·활동 정지 없음 membership이 유지/복구되면 숨김 설정을 자동 삭제한다. 모든 제한이 해소되어야 한다. 탈퇴·내보내기·이용 제한 이후에는 재가입/초대 수락이 필요하며, 이용 제한 해제나 Group 재운영만으로 membership은 복구하지 않는다. 자동 복귀 뒤 재정지되어도 이전 숨김 설정은 재적용하지 않는다.

### ADDED: 기존 동아리 상세의 제한 화면

- 별도의 사용자 관리 페이지를 만들지 않는다. `/groups/:id`는 기존 읽기 권한이 있으면 일반 상세를 유지한다(탈퇴 후 공개 동아리 포함). 읽기 권한 없는 과거 실제 회원에게만 자기 콘텐츠 제한 화면을 제공하며 일반 상세 데이터 준비 전에 분기한다.
- 서버에서 current user, 실제 참여 이력, 해당 Group을 검증한다. 본인의 삭제되지 않은 동아리 짹·책짹과 댓글만 종류별 50개씩 페이지네이션한다. 댓글은 tombstone 부모 아래에서도 정리할 수 있다. 타인·다른 Group·개인 영역은 제외한다.
- 숫자 Group ID, 콘텐츠 종류·본인 본문·작성 시각·삭제 버튼만 표시한다. 현재 Group 이름·책·인용 원문·다른 사용자·부모 본문·회원/관리자 정보와 내부 피드 링크를 표시하지 않는다. 숨김 글·댓글 및 숨김 부모 아래 댓글은 본문 대신 안내만 표시한다.
- 기존 `JjaekPolicy#destroy?`, `CommentPolicy#destroy?`, `Jjaek#destroy_or_tombstone!`와 댓글 삭제 처리를 사용한다. 댓글 있는 Jjaek의 tombstone·댓글·moderation 이력은 보존한다. 삭제 후 고정 return context를 검증하고 삭제한 콘텐츠의 Group ID 경로로 303 복귀한다. 클라이언트가 다른 Group이나 외부 URL을 복귀 대상으로 지정할 수 없다.
- 일반 Group/Jjaek/Comment·홈·프로필·피드 열람 scope, `GroupPolicy#read_jjaeks?`, `JjaekPolicy#show?`, 수정·작성·인용 원문 권한과 기존 membership/moderation/lifecycle은 완화하지 않는다.

---

## 홈 피드와 프로필 노출

홈 피드 편입과 프로필에서의 조회 가능 여부는 서로 다른 정책이다.

### 홈 피드

- 동아리에 작성한 Jjaek은 해당 동아리 피드에 나타난다.
- 홈(`/`)에는 membership, 동아리 종류와 작성자에 관계없이 Group Jjaek을 포함하지 않는다.
- 가입한 동아리의 통합 활동 피드는 `/groups`에서 제공한다. 홈과 동아리 활동 피드 경계의 canonical 기준은 `docs/specs/group_activity_feed.md`다. 이전 회원 동아리 게시물의 홈 포함 규칙은 이 정책으로 대체되었다.
- 작성자의 일반 팔로워에게 동아리 글이라는 이유만으로 자동 배포하지 않는다.
- 공개 동아리라는 이유만으로 작성자의 모든 팔로워 홈 피드에 자동 노출하지 않는다.

작성자의 일반 팔로워에게 동아리 글을 자동 배포하지 않는 것은 확정 원칙이다.
즉, 동아리에서의 발언과 일반 개인 피드에서의 발언을 분리하고,
게시 공간보다 넓은 곳으로 콘텐츠가 자동 확산되지 않게 한다.

### 작성자 프로필

동아리 Jjaek은 작성자의 활동 기록이므로 작성자 프로필에 표시할 수 있다.
다만 프로필을 보는 사용자가 해당 동아리 Jjaek을 볼 권한이 있을 때만 표시한다.

- 공개 동아리 글은 로그인 사용자가 볼 수 있다.
- 승인 동아리와 비공개 동아리 글은 현재 active member만 볼 수 있다.
- global admin은 운영 조사를 위해 membership 없이도 특정 작성자 프로필에서 모든 동아리 글을 볼 수 있다.

일반 사용자에게 프로필 접근은 동아리 접근 권한을 우회하는 경로가 될 수 없다.

---

## 동아리에서 개인 영역으로 ReJjaek

동아리 글은 작성자의 일반 팔로워 피드로 자동 확산되지 않는다.
사용자가 개인 영역으로 가져가려면 명시적으로 ReJjaek 또는 공유해야 한다.

현재 구현 정책:

- active 공개 동아리 원문은 로그인 사용자가 membership 없이도 동아리 밖 개인 영역으로 ReJjaek할 수 있다.
- 승인 동아리 원문은 동아리 밖으로 ReJjaek할 수 없다.
- 비공개 동아리 원문은 동아리 밖으로 ReJjaek할 수 없다.
- inactive 또는 pending 동아리 원문에서는 새 ReJjaek을 만들 수 없다.

기존 ReJjaek의 핵심 제약도 유지한다.

- 현재 사용자가 원문을 볼 수 있어야 한다.
- ReJjaek은 원문보다 독자 범위를 넓힐 수 없다.
- 원문 접근 권한을 잃으면 이를 참조하는 ReJjaek도 원문 권한을 우회할 수 없다.
- nested ReJjaek은 허용하지 않는다.

생성된 ReJjaek은 `group_id`가 없는 개인 Jjaek이며 원문 댓글을 복사하지 않는다.
원본 동아리가 inactive가 되는 등 원문 접근 권한을 잃으면 기존 ReJjaek도 조회 시점 권한에 따라 비노출한다.
ReJjaek row를 자동 삭제하거나 visibility를 변경하지 않는다.
개인·동아리 공유 경로와 원문 삭제 후 처리는 `docs/specs/group_sharing_requotes.md`,
다시짹 목록 조회와 노출 범위는 `docs/specs/requotes_mvp.md`를 따른다.

---

## 개인 영역에서 동아리로 공유

기존 개인 Jjaek을 동아리로 가져오는 것은 자동 복제가 아니라 명시적인 “동아리에 공유” 동작이다.

현재 구현에서는 다음만 허용한다.

- `public_jjaek`은 동아리에 공유할 수 있다.
- `book_friends`는 동아리에 공유할 수 없다.
- `private_jjaek`은 동아리에 공유할 수 없다.

공유된 콘텐츠는 원문을 복사하지 않고 `quoted_jjaek`으로 참조하는 새 Group Jjaek이다.
경로별 생성·조회·삭제 정책은 `docs/specs/group_sharing_requotes.md`를 따른다.

---

## 댓글과 토론 맥락

댓글의 열람 범위는 부모 Jjaek의 접근 범위를 상속하며 댓글 자체에 별도 visibility를 두지 않는다.
다른 공간으로 공유할 때 원문의 댓글을 복사하거나 공유된 공간에 함께 노출하지 않는다.

예:

```text
개인 Jjaek
└─ 개인 Jjaek의 댓글

개인 Jjaek을 동아리에 공유
└─ 동아리에서 새로 시작된 댓글
```

```text
동아리 Jjaek
└─ 동아리 내부 댓글

동아리 Jjaek을 개인 영역에 ReJjaek
└─ 개인 ReJjaek에서 새로 시작된 댓글
```

즉, 원문은 참조하지만 토론은 게시된 공간별로 독립적으로 유지한다.

### 동아리 댓글 권한

- 공개 동아리
  - 동아리 비회원인 로그인 사용자도 게시물과 댓글을 읽을 수 있다.
  - 댓글 작성은 현재 동아리 멤버만 가능하다.
- 승인 동아리
  - 게시물·댓글 읽기와 댓글 작성 모두 현재 멤버만 가능하다.
- 비공개 동아리
  - 게시물·댓글 읽기와 댓글 작성 모두 현재 멤버만 가능하다.

동아리 Jjaek도 기존 `Comment` 모델을 사용하며 댓글 visibility는 부모 Jjaek을 상속한다.
댓글 작성과 자기 댓글 수정은 active member만 가능하다. 탈퇴하거나 내보내진 사용자의 기존 댓글은 유지되며 새 작성·수정은 불가하지만 자기 댓글 삭제는 가능하다.
동아리 관리자의 타인 댓글 삭제는 구현하지 않는다. 타인 Comment의 moderation hide/restore는 원문 수정이나 삭제와 분리된 상태로 구현되어 있다.

---

## Group membership 탈퇴 후 콘텐츠

이 절은 계정 탈퇴가 아니라 특정 Group membership 탈퇴를 다룬다.
계정 탈퇴 시 콘텐츠와 관계 처리 기준은 `docs/specs/account_group_lifecycle.md`를 따른다.
membership 탈퇴 후 콘텐츠 정책은 다음과 같이 확정한다.

- 탈퇴 전에 작성한 댓글은 동아리에 남긴다.
- 탈퇴 후 새 댓글을 작성할 수 없다.
- 탈퇴 후 기존 댓글을 수정할 수 없다.
- 본인이 작성한 기존 댓글은 탈퇴 후에도 삭제할 수 있다.
- active 작성자는 자기 기존 동아리 Jjaek을 수정·삭제할 수 있다.
- 탈퇴하거나 내보내진 작성자는 자기 기존 동아리 Jjaek을 수정할 수 없지만 삭제할 수 있다.
- 댓글이 없는 Jjaek은 hard delete하고, 댓글이 있으면 본문을 제거한 tombstone과 기존 댓글을 보존한다.
- 삭제된 Jjaek에는 새 댓글·좋아요·ReJjaek을 허용하지 않는다.
- 동아리 관리자의 타인 Jjaek 수정·작성자 삭제는 구현하지 않는다. 타인 Jjaek의 moderation hide/restore는 원문 lifecycle과 분리된 상태로 구현되어 있다.

승인 동아리 또는 비공개 동아리에서 탈퇴해 원문 접근 권한을 잃은 사용자는 동아리 콘텐츠를 다시 볼 수 없어야 한다.
위 권한을 만족시키는 정확한 UI, 메시지와 동선은 후속 구현에서 결정한다.

### 동아리 좋아요 권한

- 조회 가능한 active 동아리의 active member만 새 좋아요를 만들 수 있다.
- 공개 동아리 비회원은 콘텐츠를 읽을 수 있어도 좋아요를 만들 수 없다.
- 동아리가 inactive가 되거나 membership이 종료되거나 Jjaek이 삭제된 뒤에도, 현재 원문을 볼 수 있다면 기존 자기 좋아요는 철회할 수 있다.
- 원문 조회 권한을 잃은 경우에는 기존 좋아요 철회를 위해 접근 정책을 우회하지 않는다.
- 타인의 좋아요는 철회할 수 없다.

---

## moderation 정책

group admin은 일반 active 회원의 동아리 활동을 정지·복구할 수 있다. membership과 내부 콘텐츠 읽기 권한은 유지하며 해당 Group의 Jjaek·책짹·Comment 생성·수정과 새 Like를 차단하되 자기 콘텐츠 삭제와 기존 Like 철회는 허용한다. global admin은 이 상태와 감사 이력을 조사하지만 Group membership moderation을 실행하지 않는다. 이는 일반 membership lifecycle 및 User 계정 정지와 별도이고 서로 자동 전파되지 않는다.
활동 정지는 현재 GroupMembership에만 적용된다. 자발적 탈퇴·내보내기·이용 제한으로 membership이 삭제되면 현재 정지도 종료되고 새 membership에 자동 승계하지 않으며 기존 감사 row는 보존한다.
승인 동아리의 pending 가입 신청은 승인·거절 심사 대상으로만 다루며 동아리 이용 제한 대상이 아니다. 동아리 이용 제한은 active membership에만 적용한다.

동아리 관리자는 자기 Group의 Jjaek·책짹·Comment를 사유와 함께 숨김·복구할 수 있다.
원문 수정·hard delete나 서비스 전체 User 정지는 허용하지 않으며 현재 Group당 group admin 1명 구조를 유지한다.
상태 분리, 감사 기록, 역할 경계와 제외 범위의 canonical 기준은 `docs/specs/moderation_mvp.md`를 따른다.

---

## 관리자 권한 이전 감사 이력

- 기존 관리자에서 다른 active 회원으로 관리자 권한이 실제 이전되면 기존 `GroupMembershipEvent`를 재사용해 관리자 권한 해제 사건과 관리자 권한 부여 사건을 각각 append-only로 남긴다.
- 두 사건의 대상 `user`, 실행 `actor`, `created_at`으로 이전 관리자, 새 관리자, 조치자와 조치 시각을 추적할 수 있어야 한다.
- 관리자 권한 변경과 두 사건 생성은 하나의 transaction으로 처리한다. 실패하거나 rollback되면 권한과 감사 이력 모두 이전 상태를 유지한다.
- 두 사건은 기존 동아리 회원 운영 이력에서 자연스럽게 확인할 수 있어야 한다.
- 새 감사 모델을 만들지 않으며 기존 관리자 이전 권한 정책도 확대하지 않는다.

---

## Acceptance Criteria

- global admin이 직접 생성한 Group은 즉시 `active`가 된다.
- 일반 사용자가 생성한 승인 대상 Group은 기존처럼 `pending_approval`로 시작한다.
- 승인 동아리의 pending 가입 신청에는 승인·거절만 제공하며 동아리 이용 제한 UI와 직접 요청을 허용하지 않는다.
- active membership은 기존 동아리 이용 제한 정책을 유지한다.
- 관리자 이전 성공 시 이전 관리자의 권한 해제와 새 관리자의 권한 부여가 append-only 회원 운영 이력으로 생성된다.
- 각 이력에서 대상 사용자, 조치자와 시각을 확인하여 이전 관리자와 새 관리자를 추적할 수 있다.
- 관리자 이전 실패 시 관리자 권한과 감사 이력 모두 이전 상태를 유지한다.
- 기존 Group lifecycle, membership, ban, suspension 정책에 회귀가 없다.

---

## Classroom과의 경계

Classroom은 동아리 MVP와 이번 Group lifecycle 설계 범위에 포함하지 않는다.

- 동아리는 일반 사용자가 참여하는 독서 공동체다.
- Classroom은 Group에서 확립된 SNS·콘텐츠 접근 정책을 재사용할 수 있다.
- 다만 Classroom의 생성·승인·종료, 교사 역할과 학생 membership은 성격이 다를 수 있다.
- Group 승인·운영 lifecycle을 Classroom에 자동으로 적용하지 않는다.

Classroom의 구조와 상세 정책은 실제 Classroom 작업 시 결정한다.

---

## 현재 범위에서 하지 않는 것

- Classroom 구현 또는 상세 설계
- `Space`, `Context` 같은 공통 추상 모델 도입
- polymorphic association 설계 확정
- 신고 queue와 `platform_moderator` 실제 구현
- 댓글을 공유 공간 사이에 복사하거나 합쳐 보여주는 기능
- 승인 동아리·비공개 동아리 원문의 외부 ReJjaek
- `book_friends`, `private_jjaek`의 동아리 공유
- nested ReJjaek
- 여러 group admin과 Group moderator 역할

---

## 미결정 사항

- 운영 중 동아리 총량 제한, 계정 연령과 고급 남용 방지 조건 (신규 승인 대기 1개 제한과 기본 요청 rate limit은 구현됨)
- 탈퇴 후 댓글 삭제를 제공하는 정확한 UI, 메시지와 동선 (권한 정책은 구현 완료, 접근 UX 개선 후보)
- 승인 동아리 또는 비공개 동아리 탈퇴 후 원문 조회 권한을 잃은 상태에서 자기 콘텐츠 관리 진입을 제공하는 방식 (접근 UX 개선 후보)

탈퇴 후 댓글의 보존·작성·수정·삭제 권한과 동아리 관리자의 moderation 책임,
일반 로그인 사용자가 Group을 신청할 수 있는 방향 자체는 미결정 사항이 아니다.
승인·운영 lifecycle은 현재 구현되어 있다.
탈퇴 후 동아리 Jjaek은 보존하며 작성자는 수정할 수 없고 자기 글을 삭제할 수 있다.

---

## 변경 전 확인할 정책 체크리스트

- 동아리의 현재 구현과 아직 미구현인 목표 정책을 구분했는가?
- 개인 Jjaek visibility와 동아리 접근 정책을 분리했는가?
- 공개·승인·비공개 동아리의 발견·가입·읽기·쓰기 권한을 각각 고정했는가?
- 홈 피드 자동 배포와 프로필의 권한 기반 노출을 구분했는가?
- 게시 공간보다 넓은 곳으로 콘텐츠가 자동 확산되지 않는가?
- 양방향 공유가 허용된 원문 범위를 지키는가?
- 원문 접근 권한을 공유나 프로필로 우회할 수 없는가?
- 공유된 공간에서 댓글과 토론이 새로 시작되는가?
- 동아리의 글·댓글 작성이 현재 멤버에게만 허용되는가?
- 탈퇴 후 확정된 댓글 권한을 지키는가?
- moderation 최소 요구와 미결정 세부 체계를 구분했는가?
- Group 정책을 Classroom에 자동 적용하지 않았는가?
- 제품 정책의 개념적 축을 DB 구조로 성급히 확정하지 않았는가?
