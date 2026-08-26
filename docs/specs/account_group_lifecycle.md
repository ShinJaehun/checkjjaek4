# 계정 탈퇴와 Group lifecycle

## 목적과 상태

이 문서는 계정 탈퇴와 Group 승인·운영 lifecycle의 canonical 목표 정책이다.
계정 탈퇴와 owner 양도는 아직 구현되지 않았다. Group 승인·운영 lifecycle은 구현되어 있으며,
현재 구현 사실은 `docs/architecture/current_system.md`와 `docs/architecture/authorization.md`를 따른다.

---

## 계정 탈퇴

계정 탈퇴는 단순한 `User` hard delete나 모든 콘텐츠 삭제가 아니다.

- 탈퇴 즉시 로그인할 수 없어야 한다.
- 이메일 등 개인 식별정보는 더 이상 서비스에서 사용자 신원으로 노출하지 않는다.
- 기존 작성자는 화면에서 “탈퇴한 사용자”처럼 익명으로 표시한다.
- 다른 사용자와 형성한 대화 맥락을 위해 기존 Jjaek과 Comment 본문은 익명 작성자의 콘텐츠로 보존한다.
- 탈퇴 전에 사용자가 개별 Jjaek이나 Comment를 직접 삭제했다면 기존 개별 콘텐츠 삭제 정책을 적용한다.
- 따라서 계정 탈퇴와 내 모든 콘텐츠 삭제는 같은 동작이 아니다.

관계성 데이터는 다음 방향으로 정리한다.

- Follow 관계를 종료한다.
- BookFriendship과 pending 요청을 종료한다.
- Like 등 탈퇴 사용자의 개인 반응 관계를 제거한다.
- GroupMembership에서 탈퇴 사용자가 더 이상 active member로 남지 않게 정리한다.
- active Group owner는 아래 owner lifecycle을 먼저 해결하지 않으면 탈퇴할 수 없다.

Notification 등 사회적 콘텐츠가 아닌 개인 운영 데이터는 구현 단계에서 정리 대상으로 본다.
정확한 보존·삭제 방식은 이 문서에서 확정하지 않는다.

`User` row 자체를 익명화할지, deleted-user placeholder를 둘지, soft-delete column을 둘지도
구현 설계에서 결정한다. 이 문서는 제품에 보이는 결과와 lifecycle만 확정한다.

---

## Group lifecycle과 membership 상태

Group lifecycle은 공간 자체가 운영 가능한지를 나타낸다. 사용자에게는 다음 의미로 보인다.

- 승인 대기
- 운영 중
- 운영 종료

구현에서는 `pending_approval` / `active` / `inactive`를 사용해
`GroupMembership.pending`과 Group 승인 대기를 구분한다.

반면 기존 `GroupMembership`의 `pending` / `invited` / `active` / `inactive`는
한 사용자가 특정 Group 안에서 어떤 상태인지를 나타낸다. 두 상태 축은 서로 독립적이다.

기존 Group의 public / approval / private도 접근·가입 방식이며 Group lifecycle과 독립적이다.
Group이 승인 대기 또는 운영 종료 상태라면 public Group이어도 정상 운영 활동을 허용하지 않는다.

---

## Group 생성과 승인 `(현재 구현)`

일반 사용자는 Group을 신청할 수 있으며 흐름은 다음과 같다.

> Group 생성 → 승인 대기 → global admin 승인 → 운영 중

- 승인 대기 Group은 일반 발견 대상에서 제외한다.
- 일반 회원 가입과 일반 Group Jjaek·Comment 활동을 허용하지 않는다.
- owner는 자신의 신청 상태를 확인할 수 있어야 한다.
- 신규 신청자는 일반 소개와 별도로 최대 500자의 동아리 개설 목적을 제출한다.
- 개설 목적은 owner의 관리 화면과 global admin 승인 화면에서만 확인한다.
- global admin만 Group을 승인해 운영 중으로 전환할 수 있다.
- global admin은 동아리 개설 목적을 포함한 신청 정보를 확인해 승인한다.

승인 거절 상태 또는 row 삭제 여부, 거절 사유, admin UI, 생성 횟수 제한,
spam/abuse scoring은 후속 결정으로 남긴다.

---

## active Group owner의 계정 탈퇴 `(목표 정책 · 일부 미구현)`

active Group owner는 Group을 그대로 둔 채 계정을 탈퇴할 수 없다.
탈퇴 전에 owner 양도 또는 Group 운영 종료 중 하나를 완료해야 한다.

### Owner 양도

- 현재 active member에게만 owner를 양도할 수 있다.
- 새 owner는 active membership을 가져야 한다.
- ownership과 owner membership 불변식은 원자적으로 유지해야 한다.
- 양도 후 기존 owner는 일반 member로 남거나 정상 membership 탈퇴 또는 계정 탈퇴 절차를 밟을 수 있다.

정확한 UI와 transaction 구현은 후속 구현 설계에서 결정한다.

### Group 운영 종료

- 운영 종료는 Group hard delete가 아니다.
- 기존 Jjaek, Comment와 독서 기록을 보존한다.
- 새 가입과 새 Jjaek·Comment 작성을 허용하지 않는다.
- 일반 발견·검색 대상에서 제외한다.
- 기존 참여자는 자신이 참여했던 과거 공간과 콘텐츠를 읽을 수 있는 방향으로 둔다.
- owner가 운영을 종료한 뒤에는 해당 Group 때문에 계정 탈퇴가 막히지 않는다.
- owner가 운영을 종료할 때 최대 500자의 종료 사유와 서버 기준 종료 시각을 기록한다.
- 운영 종료와 재활성화 요청은 동아리 상세이 아닌 동아리 관리 화면에서 수행한다.

운영 종료 후 정확한 read scope는 구현 전에 추가로 결정한다.
특히 과거 public Group이었다는 이유만으로 비회원 열람을 계속 허용한다고 전제하지 않는다.
Group hard delete는 이 lifecycle의 기본 동작이 아니다.

---

## 재활성화 `(현재 구현)`

운영 종료된 Group은 다음 승인 흐름을 거쳐 다시 운영할 수 있는 방향으로 둔다.

> 운영 종료 → 재활성화 요청 → 승인 대기 → global admin 승인 → 운영 중

최소한 기존 owner가 재활성화를 요청할 수 있는 방향을 둔다.
재활성화 요청은 기존 종료 사유·시각을 보존하며 global admin 승인 목록에서 신규 개설 신청과 구분한다.
정확한 요청 UI, 요청 가능 사용자의 예외와 admin 거절 처리는 후속 결정으로 남긴다.

---

## 콘텐츠·접근 정책과의 연결

- Group lifecycle은 group type과 GroupMembership 상태를 대체하지 않는다.
- 승인 대기 또는 운영 종료 Group에서는 group type과 관계없이 정상 가입·작성 활동을 허용하지 않는다.
- 기존 Group Jjaek visibility, 댓글 visibility와 membership 정책은 이 문서에서 변경하지 않는다.
- 계정 탈퇴로 보존된 Jjaek과 Comment는 익명 작성자의 콘텐츠로 남는다.
- 운영 종료 Group의 세부 read scope는 구현 전에 별도로 확정한다.

---

## Classroom 경계

Classroom은 이번 lifecycle 설계 범위가 아니다.

- Classroom은 Group에서 확립된 SNS·콘텐츠 접근 정책을 재사용할 수 있다.
- 생성·승인·종료, 교사 역할과 학생 membership은 Group과 성격이 다를 수 있다.
- 따라서 이 Group 승인 lifecycle을 Classroom에 자동으로 적용하지 않는다.
- Classroom 상세 정책은 실제 Classroom 작업 시 결정한다.

---

## 후속 결정

- Group 승인 거절 상태 또는 row 삭제 여부와 거절 사유
- global admin UI와 운영 절차
- Group 생성 횟수 제한과 spam/abuse 대응
- 운영 종료 Group의 정확한 read scope
- 재활성화 요청 UI, 요청 가능 사용자의 예외와 거절 처리
- 계정 익명화의 DB 구조와 개인 운영 데이터 정리 방식
