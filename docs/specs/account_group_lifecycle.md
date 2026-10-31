# 계정 탈퇴와 Group lifecycle

## 목적과 상태

이 문서는 계정 탈퇴와 Group 승인·운영 lifecycle의 canonical 목표 정책이다.
계정 탈퇴, Group 승인·운영 lifecycle과 단일 동아리 관리자 이전은 구현되어 있으며,
현재 구현 사실은 `docs/architecture/current_system.md`와 `docs/architecture/authorization.md`를 따른다.

---

## 계정 탈퇴 `(현재 구현)`

계정 탈퇴는 단순한 `User` hard delete나 모든 콘텐츠 삭제가 아니다.

- 탈퇴 즉시 로그인할 수 없어야 한다.
- 이메일 등 개인 식별정보는 더 이상 서비스에서 사용자 신원으로 노출하지 않는다.
- 기존 작성자는 화면에서 “탈퇴한 사용자”처럼 익명으로 표시한다.
- 다른 사용자와 형성한 대화 맥락을 위해 기존 Jjaek과 Comment 본문은 익명 작성자의 콘텐츠로 보존한다.
- 탈퇴 전에 사용자가 개별 Jjaek이나 Comment를 직접 삭제했다면 기존 개별 콘텐츠 삭제 정책을 적용한다.
- 따라서 계정 탈퇴와 내 모든 콘텐츠 삭제는 같은 동작이 아니다.
- `users.withdrawn_at`을 terminal 상태로 사용하고 User row를 익명화해 보존하며 복구·유예 기간은 두지 않는다.
- 이름은 “탈퇴한 사용자”, 이메일은 원본을 보존하지 않는 비전송 placeholder로 교체하고 Devise 로그인을 차단한다.
- 기존 avatar identity도 제거하고 모든 탈퇴 사용자를 동일한 공통 anonymous avatar로 표시한다.
- 탈퇴 User row와 id는 과거 Jjaek·Comment의 역사적 reference로 계속 유지한다.
- 공개 handle은 예외적으로 User row에 비공개 보존한다. 과거 주소가 다른 사용자의 프로필로 연결되지 않도록 영구 재사용을 막기 위한 목적이며, 탈퇴자의 공개 URL 생성이나 handle 조회에는 사용하지 않는다.
- 탈퇴자의 과거 `/users/:handle`은 조회되지 않는다. 기존 `/users/:id`는 익명화된 User를 표시하는 정책을 유지한다. 보존된 handle은 화면에 노출하지 않는다.
- 원래 이메일은 해제되므로 같은 이름·이메일·비밀번호로 다시 가입할 수 있지만, 이는 기존 계정 복구가 아니라 새로운 User row와 id 생성이다.
- 자발적 탈퇴 시 해당 User와 연결된 가입 초대 및 같은 이메일의 과거 만료·취소 초대도 일반 30일 정리를 기다리지 않고 즉시 이메일을 초대별 비식별 주소로 교체하고 User 연결을 해제한다. 기존 종료 상태·시각은 유지하고, 예외적으로 활성 초대가 남아 있다면 취소한다. 원래 이메일을 복원할 값은 남기지 않는다. 미사용 초대의 일반 보존기간은 `docs/specs/registration_invitations_c08.md`를 따른다.
- 재가입 후에도 과거 Jjaek·Comment는 새 User가 아니라 기존 withdrawn User id를 계속 참조한다.
- 재가입에는 새 이메일 초대가 필요하며, 과거 책친구·팔로우·GroupMembership·독서 기록·관리자 권한을 승계하지 않는다.
- 재가입한 새 User는 기존 탈퇴 계정과 무관한 새 avatar identity를 가진다.

관계성 데이터는 다음 방향으로 정리한다.

- Follow 관계를 종료한다.
- BookFriendship과 pending 요청을 종료한다.
- Like 등 탈퇴 사용자의 개인 반응 관계를 제거한다.
- GroupMembership에서 탈퇴 사용자가 더 이상 active member로 남지 않게 정리한다.
- active Group의 동아리 관리자는 아래 관리자 lifecycle을 먼저 해결하지 않으면 탈퇴할 수 없다.
- Notification과 개인 Bookshelf, BookshelfEntry, BookActivity도 정리한다.

탈퇴한 사용자를 대상으로 새 Follow, BookFriendship, Group 초대와 profile-context Jjaek을 만들 수 없다.

현재 구현은 Notification, Bookshelf, BookshelfEntry와 BookActivity를 삭제하고,
공용 Book과 익명화된 User에 연결된 Jjaek·Comment는 보존한다.

global admin의 self-withdrawal과 다른 사용자를 강제 탈퇴시키는 기능은 제공하지 않는다.
정지 회원의 이메일과 계정 복구 정책은 그대로 유지한다. 영구 제재자의 재가입 제한과 식별정보 보존·파기 절차는 `docs/specs/moderation_mvp.md`의 후속 설계 방향을 바탕으로 별도 구현에서 확정한다.

---

## Group lifecycle과 membership 상태

Group lifecycle은 공간 자체가 운영 가능한지를 나타낸다. 사용자에게는 다음 의미로 보인다.

- 승인 대기
- 운영 중
- 운영 종료
- 최초 개설 신청 거절
- 최초 개설 신청 취소

구현에서는 `pending_approval` / `active` / `inactive`와 신규 신청의 종료 상태인 `rejected` / `cancelled`를 사용해
`GroupMembership.pending`과 Group 승인 대기를 구분한다.

반면 `GroupMembership`의 `pending` / `invited` / `active`는
한 사용자가 특정 Group 안에서 어떤 상태인지를 나타낸다. 두 상태 축은 서로 독립적이다.

기존 Group의 public / approval / private도 접근·가입 방식이며 Group lifecycle과 독립적이다.
Group이 승인 대기·운영 종료·개설 거절·개설 취소 상태라면 public Group이어도 정상 운영 활동을 허용하지 않는다.

---

## Group 생성과 승인 `(현재 구현)`

일반 사용자는 Group을 신청할 수 있으며 흐름은 다음과 같다.

> Group 생성 → 승인 대기 → global admin 승인 → 운영 중

- 승인 대기 Group은 일반 사용자 발견 대상에서 제외하지만 global admin의 Group 목록과 admin inventory에는 포함한다.
- 일반 회원 가입과 일반 Group Jjaek·Comment 활동을 허용하지 않는다.
- 동아리 관리자는 자신의 신청 상태를 확인할 수 있어야 한다.
- 신규 신청자는 일반 소개와 별도로 최대 500자의 동아리 개설 목적을 제출한다.
- 개설 목적은 동아리 관리자 관리·신청 결과 화면과 global admin 승인·관리 화면에서만 확인한다.
- global admin만 Group을 승인해 운영 중으로 전환할 수 있다.
- global admin은 동아리 개설 목적을 포함한 신청 정보를 확인해 승인한다.
- 개설 신청·최초 승인·개설 거절·개설 취소·운영 종료·재활성화 요청·재승인·재운영 거절·철회는 처리자와 발생 시각을 운영 이력에 누적한다.
- 개설 신청에는 당시 개설 목적, 운영 종료에는 당시 종료 사유를 snapshot으로 보존한다.

Group 생성 요청의 기본 rate limit은 `docs/specs/basic_rate_limiting.md`에 따라 구현되어 있다.

### 신규 신청 제한·거절·취소

- 일반 사용자의 동시 신규 개설 승인 대기는 최대 1개다. `pending_approval`이면서 `closed_at`이 없는 최초 신청만 집계한다. 운영 중·운영 종료·거절·취소·재활성화 승인 대기와 다른 동아리 membership은 집계하지 않는다. global admin의 직접 생성은 예외다.
- 새 신청 화면과 생성 POST에서 검사하며, POST는 신청자 User 행 잠금 아래 제한 확인·생성·event 기록을 하나의 transaction으로 처리해 동시 요청의 우회를 막는다. 기존 사용자당 5회/24시간 rate limit은 별도로 유지한다. 제한 시 이유와 기존 신청 링크를 제공한다.
- global admin만 최초 개설 승인 대기 신청을 거절할 수 있다. 거절 사유는 필수이며 최대 500자다. `rejected`로 전환하고 `opening_rejected` event의 detail에 사유를 보존한다. 신청자에게 결과와 사유를 알린다.
- 현재 group admin 본인만 최초 개설 승인 대기 신청을 확인 절차 후 취소할 수 있다. 취소 사유는 요구하지 않는다. `cancelled`로 전환하고 `opening_cancelled` event로 처리자·시각을 보존하며 유효한 global admin에게 취소를 알린다.
- 승인·거절·취소는 Group 행 잠금과 transaction 안에서 권한·현재 상태를 다시 검사한다. 상태와 event는 함께 commit/rollback되며 알림은 기존 notifier로 commit 후 전달한다. 승인 완료 후에는 거절·취소할 수 없다.
- `rejected` / `cancelled`는 신규 개설 신청의 종료 상태다. 기존 `inactive` 의미를 재사용하지 않으며 같은 Group의 승인·재활성화·수정·운영을 허용하지 않는다. 다시 신청하려면 새 Group을 생성한다.
- Group과 기존 이력을 삭제하지 않는다. 일반 내 동아리 목록·발견·활동 피드에서 제외하며, 신청자와 global admin만 신청 결과 및 운영 이력을 확인한다. 신청 화면의 최근 결과 10건에서 과거 신청으로 진입할 수 있다. 다른 일반 사용자에게 신청 내용·거절 사유를 노출하지 않는다.
- 일반 취소는 계정 탈퇴용 `cancel_pending_application_for_withdrawal!`과 별도 처리한다. 탈퇴 시 최초 pending Group 정리·재운영 pending 취소 정책은 그대로 유지하며 이미 거절·취소된 Group과 이력은 보존한다.

운영 중 Group 총량 제한과 고급 spam/abuse scoring은 미구현이다.

---

## active Group 관리자의 계정 탈퇴 `(현재 구현)`

active Group 관리자는 Group을 그대로 둔 채 계정을 탈퇴할 수 없다.
탈퇴 전에 관리자 권한 이전 또는 Group 운영 종료 중 하나를 완료해야 한다.

### 동아리 관리자 권한 이전 `(현재 구현)`

- Group에는 정확히 한 명의 동아리 관리자(`group_admin`)가 있으며 내부적으로 `Group.group_admin_id`가 이를 가리킨다.
- active/inactive Group의 현재 관리자 또는 global admin은 다른 active member에게 권한을 이전할 수 있다.
- pending, invited member나 Group 밖 사용자는 대상이 될 수 없고 pending Group에서는 이전할 수 없다.
- 이전은 Group row lock 안에서 현재 관리자와 대상 membership을 재검증한다.
- 이전 후 새 관리자는 active membership을 유지하고 기존 관리자는 일반 active member로 남아 정상 탈퇴할 수 있다.

### Group 운영 종료 `(현재 구현)`

- 운영 종료는 Group hard delete가 아니다.
- 기존 Jjaek, Comment와 독서 기록을 보존한다.
- 새 가입과 새 Jjaek·Comment 작성을 허용하지 않는다.
- 일반 발견·검색 대상에서 제외한다.
- active membership이 있는 기존 참여자는 과거 공간과 콘텐츠를 읽을 수 있다.
- 동아리 관리자가 운영을 종료한 뒤에는 해당 Group 때문에 계정 탈퇴가 막히지 않는다.
- 동아리 관리자가 운영을 종료할 때 최대 500자의 종료 사유와 서버 기준 종료 시각을 기록한다.
- 운영 종료와 재활성화 요청은 동아리 상세이 아닌 동아리 관리 화면에서 수행한다.

현재 구현에서 운영 종료된 Group은 active membership이 있는 사용자만 기본 정보와 기존 콘텐츠를 읽을 수 있다.
과거 public Group이었다는 이유만으로 비회원 열람을 계속 허용하지 않는다.
Group hard delete는 이 lifecycle의 기본 동작이 아니다.

계정 탈퇴 시 `closed_at`이 없는 최초 개설 승인 대기 Group은 관리자 외 membership, 운영 콘텐츠 또는 예상 밖 lifecycle
event가 없는 정상 신청만 정리하며, 예상 밖 데이터가 있으면 전체 탈퇴를 중단한다. `closed_at`이 있는 재운영 승인 대기
Group은 삭제하지 않고 재운영 신청만 취소해 inactive로 되돌린다. 이때 `group_admin_id`, 기존 콘텐츠, 종료 metadata,
`reactivation_requested`를 포함한 lifecycle history와 `group_admin_id`가 가리키는 익명화된 역사적 관리자를 보존한다.

---

## 재활성화 `(현재 구현)`

운영 종료된 Group은 다음 승인 흐름을 거쳐 다시 운영할 수 있다.

> 운영 종료 → 재활성화 요청 → 승인 대기 → global admin 승인 → 운영 중

승인 대기의 종료 경로는 다음과 같다.

> 재운영 승인 대기 → global admin 거절 또는 현재 group admin 본인의 신청 철회 → 운영 종료

기존 동아리 관리자는 동아리 관리 화면의 전용 Action page에서 재활성화를 요청할 수 있다.
재활성화 요청은 기존 종료 사유·시각을 보존하며 global admin 승인 목록에서 신규 개설 신청과 구분한다.
동아리 관리자는 자기 Group의 시각 중심 운영 이력을 관리 화면에서 열람한다. 개설 목적과 종료 사유 snapshot은
global admin의 운영 상세에서 확인하며 admin 목록에는 운영 이력을 직접 표시하지 않는다. global admin은 모든 Group의
운영 metadata·이력·내부 콘텐츠를 운영 목적으로 조사하고 필요한 관리자 이전을 수행할 수 있다. 이 권한은 일반 Group
수정·종료·재활성화 요청·membership 관리 권한을 자동으로 부여하지 않는다.
현재 동아리 관리자만 요청할 수 있고 global admin이 승인한다.

### 재운영 신청 거절·철회 `(현재 구현)`

- `pending_approval`이면서 `closed_at`이 존재하는 재운영 승인 대기만 대상이다. `closed_at`이 없는 신규 개설 신청과 구분한다.
- global admin만 거절할 수 있으며 사유는 필수이고 최대 500자다. `reactivation_rejected` event의 detail에 당시 사유를 보존하고 신청자인 현재 Group admin에게 거절 결과와 해당 사유를 알린다.
- 현재 group admin 본인만 관리 화면의 확인 절차를 거쳐 철회할 수 있다. 철회 사유는 요구하지 않는다. `reactivation_withdrawn` event를 남기고 사건 시점에 탈퇴·정지되지 않은 유효한 global admin에게 철회 사실을 알린다. 각 알림에서 actor 본인은 제외한다.
- 두 경로 모두 기존 `inactive`로 복귀한다. 신규 개설 거절·취소의 `rejected` / `cancelled`를 사용하거나 별도 Group 상태를 추가하지 않는다.
- `closed_at`과 `closure_reason`, 기존 콘텐츠·membership·운영 이력을 그대로 보존한다. 새 event에 처리자·발생 시각을 기록하며, 거절 사유는 다른 운영 종료 사유를 덮어쓰지 않는다.
- 승인·거절·철회는 Group 행 잠금과 transaction 안에서 권한과 현재 상태를 다시 검사한다. 상태 변경과 event 저장은 함께 commit/rollback되며 알림은 기존 notifier를 통해 commit 이후 전달한다. 이미 승인·거절·철회된 대기를 중복 처리할 수 없다. 재운영 신청 생성도 잠금 안에서 권한·상태를 다시 검사한다.
- 거절·철회 후에는 같은 Group의 기존 재운영 신청 경로를 다시 사용할 수 있다. 과거 신청·처리 이력은 새 신청과 함께 보존한다.
- 사유와 운영 이력은 기존 현재 Group admin의 관리 화면과 global admin 운영 상세에서만 표시한다. 일반 회원은 기존 inactive 콘텐츠 읽기 권한만 유지하며, 비회원에게 Group·사유·이력 접근을 새로 허용하지 않는다. 알림의 수신자·내용·목적지는 `docs/specs/notifications_mvp.md`를 따른다.

---

## 콘텐츠·접근 정책과의 연결

- Group lifecycle은 group type과 GroupMembership 상태를 대체하지 않는다.
- 승인 대기 또는 운영 종료 Group에서는 group type과 관계없이 정상 가입·작성 활동을 허용하지 않는다.
- 기존 Group Jjaek visibility, 댓글 visibility와 membership 정책은 이 문서에서 변경하지 않는다.
- 계정 탈퇴로 보존된 Jjaek과 Comment는 익명 작성자의 콘텐츠로 남는다.
- 운영 종료 Group은 active membership이 있는 사용자만 기존 콘텐츠를 읽는다.

---

## Classroom 경계

Classroom은 이번 lifecycle 설계 범위가 아니다.

- Classroom은 Group에서 확립된 SNS·콘텐츠 접근 정책을 재사용할 수 있다.
- 생성·승인·종료, 교사 역할과 학생 membership은 Group과 성격이 다를 수 있다.
- 따라서 이 Group 승인 lifecycle을 Classroom에 자동으로 적용하지 않는다.
- Classroom 상세 정책은 실제 Classroom 작업 시 결정한다.

---

## 후속 결정

- 운영 중 Group 총량 제한과 고급 spam/abuse 대응 (신규 승인 대기 1개 제한과 기본 요청 rate limit은 구현됨)
