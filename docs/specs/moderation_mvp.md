# Moderation MVP Policy

## 상태와 목적

이 문서는 Checkjjaek4의 SNS moderation MVP canonical spec이다.

현재 구현 상태는 `docs/architecture/current_system.md`, 현재 서버측 권한은
`docs/architecture/authorization.md`를 따른다. 이 문서는 이후 moderation과 Classroom 구현에서
지켜야 할 목표 정책과 상태 경계를 확정하며, 아직 존재하지 않는 schema·class·method 이름을 확정하지 않는다.

Checkjjaek4는 일반 사용자가 가입해 짹·책짹·댓글·동아리 콘텐츠를 작성하는 공개 SNS다.
Classroom의 실제 교사·학생 사용 전에 운영자가 검색·제한·복구하고 그 근거를 감사할 수 있는 최소 기반을 마련한다.

---

## 일반 사용자와 managed student account

- 일반 자가 가입 User는 기존 공개 SNS 기능을 계속 사용할 수 있다.
- 학생 계정은 나이나 실제 학생 신분을 추측한 일반 User가 아니라, 교사가 Classroom에서 생성·관리하는 별도 `managed student account`를 뜻한다.
- managed student account는 일반 공개 짹·책짹을 작성하지 않는다.
- 공개 프로필 활동, 동아리 생성·가입, 일반 사용자 대상 짹 작성에 참여하지 않는다.
- 작성과 상호작용은 소속 Classroom 문맥으로 제한한다.
- Classroom 콘텐츠를 공개 SNS로 자동 게시하지 않는다.
- 학생 결과물의 외부 공개나 일반 계정 전환은 동의·보호자·학교 정책을 포함한 별도 후속 정책으로 미룬다.
- 이번 문서에서는 학생 계정 schema나 인증 방식을 설계하지 않는다.

---

## 본인 탈퇴와 운영자 정지

### 본인 탈퇴

- 현재 `withdrawn_at` 기반 terminal withdrawal과 익명화 정책을 유지한다.
- 사용자가 요청하는 비가역적 lifecycle이다.
- 기존 withdrawal service의 관계 정리와 tombstone 의미를 운영자 제재에 재사용하지 않는다.

### 운영자 정지

- `suspended_at`으로 표현하며 `withdrawn_at` 탈퇴와 별개의 가역적 moderation 상태다.
- 정지 중에는 로그인과 모든 신규 mutation을 차단한다.
- 새 로그인은 차단하고, 이미 로그인된 session도 다음 일반 요청에서 종료한다.
- 올바른 비밀번호를 확인한 정지 사용자에게만 일반 인증 실패와 구분되는 상태와 현재 공개 사유를 안내한다.
- 기존 콘텐츠·관계·Group membership·Group 관리자 연결은 보존한다.
- 정지를 해제하면 기존 계정 상태로 돌아갈 수 있다.
- 정지만으로 기존 콘텐츠를 자동 숨김 처리하지 않는다.
- 정지된 사용자가 group admin이어도 Group을 자동 정지하거나 관리자 권한을 자동 이전하지 않는다.
- Group 정지나 관리자 이전은 global admin이 별도 조치로 판단한다.
- `withdrawn_at`을 정지 구현에 재사용하지 않는다.
- global admin의 정지·복구는 User row lock 안에서 상태 변경과 append-only `ModerationAction` 생성을 한 transaction으로 처리한다.
- 복구 감사 row는 현재 미복구 suspend row를 `reversal_of`로 참조한다.
- admin User 상세의 계정 운영 이력은 가입, 모든 정지·복구 감사 row와 탈퇴를 오래된 순으로 보존해 보여준다.

### moderation 범위와 용어

- **계정 정지 / 계정 복구**는 global admin이 `User` 전체의 서비스 로그인과 신규 mutation을 제한·복구하는 현재 구현 기능이다.
- **동아리 활동 정지 / 동아리 활동 복구**는 group admin이 특정 `GroupMembership` 범위에서만 회원 활동을 제한·복구하는 구현 기능이다. active membership과 읽기 권한은 유지하고 해당 Group의 Jjaek·책짹·Comment 생성·수정과 새 Like를 차단하되 자기 콘텐츠 삭제와 기존 Like 철회는 허용한다. 개인 프로필·개인 콘텐츠·다른 Group·서재·로그인에는 영향을 주지 않으며 `User#suspended_at`을 재사용하지 않는다.
- **동아리 운영 정지 / 동아리 운영 복구**는 global admin이 `Group#operation_suspended_at`으로 Group 자체의 새 운영 mutation을 제한·복구하는 기능이다. group admin의 기존 자발적 운영 종료 lifecycle과 별도이며 Group 대상 append-only `ModerationAction`에 사유와 복구 연결을 남긴다.

동아리 활동 정지·복구는 별도 `moderation_status`와 `GroupMembership` 대상 append-only 감사 row로 구현했다. 동아리 이용 제한은 `GroupMemberBan` 현재 marker와 ban/unban 감사 row로 구현하며 membership을 종료하고 재참여를 차단한다. 해제는 membership을 복구하지 않는다. 일반 membership의 탈퇴·내보내기와 Group의 자발적 운영 종료 lifecycle을 moderation 상태로 해석하지 않는다.
활동 정지는 현재 GroupMembership에만 적용된다. 자발적 탈퇴·내보내기·이용 제한으로 membership이 삭제되면 현재 정지 상태도 종료되며 감사 row는 보존한다. global admin은 Group membership moderation을 실행하지 않고 전체 이력을 조사하며 service-wide 제재는 User 계정 정지·복구로 수행한다.
계정 정지, 동아리 활동 정지와 동아리 운영 정지는 서로 자동 전파되지 않는다.

---

## 작성자 삭제와 운영자 숨김

### 작성자 삭제

- 현재 Jjaek의 hard delete/tombstone 정책과 Comment의 삭제 정책을 유지한다.
- 작성자가 자신의 콘텐츠 lifecycle을 종료한 상태다.

### 운영자 숨김

- 작성자가 아닌 운영자가 콘텐츠 내용을 수정하거나 작성자 대신 삭제하지 않는다.
- 원문을 보존한 별도의 가역적 moderation 상태로 처리한다.
- Jjaek hide는 글의 존재를 삭제하지 않고 본문을 가리는 조치다. platform-origin과 group-origin 모두
  기존 read boundary 안에서는 원문 대신 authority별 placeholder와 기존 읽기 맥락을 보존하되 새 mutation 권한은 추가하지 않는다.
- global admin은 조사와 복구를 위해 확인할 수 있다.
- 작성자는 자신의 콘텐츠가 제한됐다는 사실과 공개 가능한 조치 사유를 확인할 수 있다.
- 숨김을 해제해도 작성자가 이미 삭제했다면 작성자 삭제 상태가 유지된다.
- Jjaek의 `deleted_at`을 moderation 숨김에 재사용하지 않는다.
- Comment hard delete와 moderation 숨김을 같은 상태로 기록하지 않는다.

### global admin Jjaek 운영자 숨김·복구 구현 단위

현재 global admin Jjaek 숨김·복구와 제한된 숨김 콘텐츠 조회 정책은 구현되어 있다.
대상은 일반짹, 책짹, Group Jjaek 등 현재 Jjaek으로 표현되는 모든 게시물이다.

#### 정책과 불변 조건

- 현재 구현에서는 global admin만 다른 사용자가 작성한 Jjaek을 운영상 숨기고 복구할 수 있다.
- global admin도 자신이 작성한 Jjaek에는 hide와 restore를 실행하지 않는다.
- 자기 Jjaek은 작성자 lifecycle의 기존 삭제 기능을 사용한다.
- 다른 moderation 주체가 자기 Jjaek을 숨긴 경우에도 해당 Jjaek에서는 작성자 수준의 조회 권한만 적용한다.
  자기 원문, 실제 숨김 주체에 따른 숨김 상태와 현재 hide의 공개 사유는 볼 수 있지만
  내부 운영 메모와 moderation 전체 감사 상세는 운영자 권한으로 열람할 수 없다.
  hide/restore와 수정 및 새 Comment·Like·ReJjaek은 실행할 수 없고 기존 작성자 삭제만 가능하다.
- moderation 대상 Jjaek의 작성자인 global admin에게는 그 Jjaek에 한해 작성자 권한이
  moderation 운영자 권한보다 우선한다. 작성자 권한과 moderation 운영자 권한을 같은 Jjaek에서 혼용하지 않는다.
- 일반 사용자와 작성자는 자기 글이라는 이유로 hide/restore 권한을 얻지 않는다.
- 숨김은 작성자 삭제와 독립된 상태이며 `deleted_at`이나 기존 hard delete/tombstone 상태를 재사용하지 않는다.
- 숨김 시 원문과 기존 Comment·Like·ReJjaek 관계를 삭제하거나 변경하지 않는다.
- global admin은 자유 텍스트 공개 사유를 입력하는 대신 아래의 미리 정의된 숨김 사유 중 하나를 반드시 선택한다. 정의되지 않은 값은 허용하지 않는다.
  - 부적절한 내용
  - 스팸·광고
  - 개인정보 노출
  - 서비스 운영 방해
  - 기타
- `기타`를 선택해도 별도의 자유 텍스트 공개 사유를 요구하지 않는다. 내부 운영 메모는 필요할 때만 선택적으로 작성하며 작성자와 일반 사용자에게 노출하지 않는다.
- 숨김 상태 변경과 append-only `ModerationAction` hide 기록은 하나의 원자적 조치다. 어느 한쪽이 실패하면 둘 다 반영하지 않는다.
- 이미 숨겨진 Jjaek에는 hide를 중복 적용하지 않는다.
- platform-origin hidden Jjaek은 기존 read boundary 안의 feed, profile, Book, Group 목록과 direct 조회에서
  원문 대신 시스템 관리자 placeholder와 공개 사유를 표시한다.
- 작성자는 자신이 작성한 숨겨진 Jjaek의 원문, 숨김 상태, 숨김 주체와 현재 hide의 공개 사유를 볼 수 있다.
  내부 운영 메모는 볼 수 없으며 수정과 새 Comment·Like·ReJjaek은 금지하고 기존 작성자 삭제만 허용한다.
- 해당 Group의 group admin은 기존 Group read 권한과 lifecycle 경계 안에서 자기 Group의 숨겨진
  Jjaek 원문, 숨김 주체와 현재 hide의 공개 사유를 볼 수 있다. 목표 정책에서는 자기 Group의
  group-origin 내부 운영 메모도 볼 수 있지만 platform-origin 내부 운영 메모는 볼 수 없고,
  global admin의 hide를 복구할 수 없다. Group 밖 콘텐츠와 다른 Group 콘텐츠에는 이 조회 권한이 적용되지 않는다.
- Group admin Jjaek moderation의 확정된 목표 정책에서는 global admin이 작성한 Group Jjaek을
  Group admin의 hide/restore 대상에서 제외한다. Group admin은 해당 글을 direct request로도 moderation할 수 없다.
- global admin 작성자는 자기 Group Jjaek에 moderation hide/restore를 사용하지 않고,
  기존 작성자 권한 조건 안에서 자기 글을 수정·삭제하는 lifecycle을 따른다.
  다른 global admin은 기존 platform moderation 정책에 따라 해당 글을 숨기고 복구할 수 있다.
- 해당 Group의 group admin은 아래 목표 단위에 따라 자기 Group moderation 주체로서 조치를 수행하고,
  같은 Group authority에서 발생한 hide를 복구할 수 있다.
- 대상 Jjaek의 작성자가 아닌 다른 global admin은 서비스 전체 조사 권한으로 원문과 moderation 정보를
  확인하고 group-admin-originated hide를 복구할 수 있다.
- 숨겨진 Jjaek에는 새 Comment·Like·ReJjaek을 만들 수 없다. 화면 비노출뿐 아니라 서버 권한에서도 차단한다.
- 기존 ReJjaek이나 다른 조회 문맥을 통해 숨겨진 원문의 본문·책 정보 등 원문 내용이 우회 노출되지 않아야 한다.
- 대상 Jjaek의 작성자가 아닌 global admin은 운영 조사 문맥에서 숨겨진 원문,
  hide와 restore 각각의 공개 사유, 내부 운영 메모, 조치자와 시각 및 전체 감사 이력을 확인하고 복구할 수 있다.
- global admin의 조사·숨김 권한은 원문 수정, 작성자 삭제 대행이나 일반 사용자 interaction 권한을 부여하지 않는다.

#### 복구와 반복 cycle

- 현재 숨겨진 Jjaek만 복구할 수 있다.
- 복구는 Jjaek의 현재 숨김 상태를 해제하고 append-only restore `ModerationAction`을 새로 생성한다.
  기존 hide 감사 row는 수정하거나 삭제하지 않는다.
- global admin은 restore 실행 시 별도의 공개 복구 사유를 반드시 입력한다.
- restore row의 `public_reason`은 원 hide의 공개 사유를 복사하지 않고 “왜 숨김을 해제했는가”를 기록한다.
  선택적 `internal_note`도 기존 moderation 복구 패턴과 동일하게 허용한다.
- 원 hide row의 `public_reason`은 “왜 숨겼는가”를 나타내는 독립적인 감사 정보로 그대로 보존한다.
- restore row는 그 cycle의 현재 유효한 hide row를 `reversal_of`로 정확히 참조한다.
- 상태 변경과 restore 감사 기록은 하나의 transaction으로 처리하며 어느 한쪽이라도 실패하면
  모두 작업 전 상태를 유지한다.
- 작성자 삭제 상태는 복구하지 않는다. 이미 작성자가 삭제한 Jjaek은 숨김 해제 후에도 삭제 상태를 유지한다.
- 복구 후 노출 여부는 원래 visibility, Group 접근 권한과 현재 authorization을 따른다.
- restore 이후 일반 콘텐츠 화면에는 복구 사유를 계속 표시하지 않는다.
  global admin의 감사·조사 이력에서는 hide 사유와 restore 사유를 각각 확인할 수 있어야 한다.
- `hide A → restore A → hide B → restore B → hide C`처럼 반복할 수 있고 모든 감사 row를 보존한다.
- 현재 유효한 hide는 아직 restore되지 않은 최신 hide 하나다. 이미 restore된 과거 hide를 현재 hide로
  판단하거나 다시 복구할 수 없으며, 각 restore는 같은 cycle의 hide만 참조한다.

#### 사용자-facing 문구

- global admin이 숨긴 일반짹은 `시스템 관리자에 의해 숨겨진 짹입니다.`로 표시한다.
- global admin이 숨긴 책짹은 `시스템 관리자에 의해 숨겨진 책짹입니다.`로 표시한다.
- 향후 group admin 숨김 기능에는 `동아리 관리자에 의해 숨겨진 짹입니다.`를 사용한다.
- `동아리 관리자에게 숨겨진`처럼 노출 대상의 의미로 오해할 수 있는 표현은 사용하지 않는다.
- 작성자와 해당 Group의 group admin에게는 숨김 주체와 현재 hide의 공개 사유만 보여주며
  내부 운영 메모는 노출하지 않는다.
- global admin 조사 화면에는 hide와 restore 각각의 공개 사유, 내부 운영 메모,
  조치자와 시각을 포함한 전체 운영 정보를 표시할 수 있다.

#### Acceptance criteria

1. global admin은 자신이 작성한 Jjaek에 hide와 restore를 실행할 수 없다.
   다른 moderation 주체가 숨긴 자기 Jjaek에서는 작성자 권한이 우선하므로 원문, 숨김 상태와
   현재 hide의 공개 사유만 확인할 수 있다. 내부 운영 메모와 moderation 전체 감사 상세는
   운영자 권한으로 열람할 수 없고, 수정과 새 Comment·Like·ReJjaek은 불가하며
   기존 작성자 삭제 lifecycle만 사용할 수 있다.
2. global admin은 다른 사용자의 숨겨지지 않은 일반짹·책짹·Group Jjaek에 대해
   `부적절한 내용`, `스팸·광고`, `개인정보 노출`, `서비스 운영 방해`, `기타` 중 하나를 선택하고
   선택적 내부 운영 메모와 함께 기존처럼 숨길 수 있다.
   정의되지 않은 숨김 사유 값은 허용하지 않으며 `기타`에도 별도 자유 텍스트 공개 사유를 요구하지 않는다.
3. hide 성공 시 Jjaek의 숨김 상태와 대상·처리자·선택된 숨김 사유·선택적으로 작성된
   내부 운영 메모·시각을 가진 append-only 감사 기록이 함께 남는다.
4. hide 상태 변경 또는 감사 기록 중 하나가 실패하면 Jjaek과 감사 기록 모두 작업 전 상태를 유지한다.
5. 일반 사용자와 작성자는 Jjaek hide/restore를 실행할 수 없고, 이미 숨겨진 Jjaek에는 hide를 중복 실행할 수 없다.
6. global admin은 숨겨진 Jjaek을 restore할 수 있다. restore에는 원 hide 사유와 별개인 공개 복구 사유가
   필수이며 선택적 내부 운영 메모를 입력할 수 있다.
7. restore 성공 시 숨김 상태가 해제되고, 그 cycle의 현재 hide를 `reversal_of`로 정확히 참조하는
   restore 감사 row가 생성된다.
8. hide와 restore의 `public_reason`은 각각 “왜 숨겼는가”와 “왜 숨김을 해제했는가”를 기록하는
   독립적인 감사 정보이며 서로 복사하거나 덮어쓰지 않는다.
9. restore 상태 변경 또는 감사 기록 중 하나가 실패하면 상태와 감사 이력 모두 작업 전 상태를 유지한다.
10. 숨겨지지 않은 Jjaek, 이미 restore된 hide 또는 현재 cycle이 아닌 과거 hide에는 restore를 실행할 수 없다.
11. `hide → restore → hide → restore`를 반복할 수 있고 모든 감사 row가 보존되며,
    restore된 과거 hide를 현재 hide로 판단하지 않는다.
12. 작성자가 이미 삭제한 Jjaek을 restore해도 삭제 상태는 유지되며, 그 밖의 복구 후 노출은
    원래 visibility, Group 접근 권한과 현재 authorization을 따른다.
13. 일반 사용자는 feed, 목록, direct URL과 ReJjaek 등 우회 경로에서 숨겨진 원문을 볼 수 없다.
    group-origin hide는 기존 Group read boundary 안의 목록·상세에서 placeholder와 기존 읽기 맥락만 제공하는 아래 정책을 따른다.
14. 작성자는 자기 hidden Jjaek의 원문, 숨김 주체와 현재 hide의 공개 사유를 볼 수 있지만
    내부 운영 메모는 볼 수 없고 수정과 새 Comment·Like·ReJjaek은 불가하며 삭제는 가능하다.
15. 해당 Group의 group admin은 기존 Group read 권한과 lifecycle 경계 안에서 자기 Group의
    hidden Jjaek 원문, 숨김 주체와 현재 hide의 공개 사유를 볼 수 있다. 자기 Group의 group-origin
    내부 운영 메모만 볼 수 있으며 platform-origin 내부 운영 메모는 볼 수 없고 global admin hide를 restore할 수 없다.
16. 대상 Jjaek의 작성자가 아닌 global admin은 숨겨진 원문과 전체 감사 이력을 조사하고 restore할 수 있으며,
    hide와 restore 각각의 공개 사유, 내부 운영 메모, 조치자와 시각을 확인할 수 있다.
    이 권한은 작성자 대신 수정하거나 삭제하는 권한을 부여하지 않는다.
17. restore 후 일반 콘텐츠 화면에는 복구 사유를 계속 표시하지 않는다.
18. 사용자-facing 화면에는 `시스템 관리자에 의해 숨겨진 짹입니다.` 또는
    `시스템 관리자에 의해 숨겨진 책짹입니다.`를 사용한다.
19. Group admin Jjaek moderation의 목표 정책에서는 global admin이 작성한 Group Jjaek을
    Group admin의 hide/restore 대상에서 제외한다. 작성자인 global admin은 자기 글에 moderation 권한을 사용하지 않고
    기존 작성자 권한 조건 안에서 수정·삭제하며, 다른 global admin만 기존 platform moderation 정책에 따라 hide/restore할 수 있다.
20. 숨김·복구와 관계없는 일반 Jjaek visibility, Group 접근, 작성자 삭제 및
    기존 Comment·Like·ReJjaek 데이터는 회귀하지 않는다.

### Group admin Jjaek 숨김·복구 구현 단위

이 단위는 현재 구현되어 있다. 기존 global admin 숨김·복구의 상태·감사 구조와
interaction 경계를 재사용하되, Group admin에게는 자기 Group 안의 콘텐츠에 한정된 권한만 추가한다.

#### 대상과 Group 경계

- 현재 Group admin은 자신이 관리하는 Group에 속한 다른 사용자의 짹과 책짹만 숨기고 복구할 수 있다.
- personal Jjaek과 다른 Group의 Jjaek은 URL 직접 접근을 포함해 대상이 아니다.
- Group admin 자신이 작성한 Jjaek은 숨기거나 복구할 수 없고 기존 작성자 삭제 lifecycle을 사용한다.
- 작성자가 global admin이면 Group admin moderation 대상에서 제외한다. Group admin이 문제를 발견해도 직접 숨기지 않으며,
  신고나 escalation 경로는 이번 범위에서 새로 만들지 않는다.
- Group 관리자 이전 뒤에는 새 현재 Group admin이 같은 Group moderation authority를 승계한다. 이전 관리자는 권한을 잃는다.
- 권한은 policy와 action 처리 양쪽에서 현재 `group_admin_id`, 대상의 `group_id`, 작성자 불일치와 lifecycle 조건을 다시 확인해야 한다.
- policy와 action 처리는 대상 작성자의 global admin 여부도 다시 확인해 hide와 restore direct request를 명시적으로 거부해야 한다.

#### Group lifecycle과 운영 정지

- Group이 `active`이거나 `inactive`이고 운영 정지되지 않았다면 현재 Group admin은 숨김과 복구를 수행할 수 있다.
- `inactive`는 과거 콘텐츠의 읽기와 관리 책임을 보존하는 자발적 lifecycle이므로, 기존 콘텐츠 moderation도 유지한다.
- `pending_approval`에서는 숨김과 복구를 허용하지 않는다.
- global admin에 의해 Group 운영이 정지된 동안에는 Group admin의 숨김과 복구를 모두 차단한다.
- 콘텐츠 moderation은 새 Jjaek·Comment 같은 사용자 활동과는 구분하지만 Group 상태를 바꾸는 운영 mutation이다.
  따라서 global admin의 운영 정지가 유지되는 동안에는 작성자 삭제 같은 기존 cleanup 경계만 유지하고,
  Group admin moderation은 운영 복구 뒤 다시 허용한다.

#### hide origin과 restore authority

- Group admin hide도 현재 `hidden_at`과 `ModerationAction`을 사용하며 별도 상태 column이나 Group lifecycle 상태를 만들지 않는다.
- Group admin hide에는 기존과 같은 정의된 공개 사유가 필수이고 감사 row에는 실제 actor를 보존한다.
  목표 정책에서는 Group admin도 선택적 `internal_note`를 입력하며 `ModerationAction`에 그대로 저장한다.
- 각 Jjaek hide/restore 감사 row에는 조치 당시 authority를 `platform` 또는 `group`으로 보존한다.
  hide origin과 사용자-facing attribution 및 restore authority는 이 저장값만 사용하며 actor의 이후 역할 변경으로 바뀌지 않는다.
  `internal_note` 유무는 authority 판단에 영향을 주지 않는다.
- 현재 Group admin은 같은 Group moderation authority에서 발생한 현재 hide를 복구할 수 있다.
  정확히 같은 actor인지는 요구하지 않으므로 관리자 이전 전의 Group admin이 숨긴 글도 새 현재 Group admin이 복구할 수 있다.
- Group admin은 global-admin-originated hide를 복구할 수 없다. 숨겨진 원문을 조사할 권한과 복구 권한을 동일시하지 않는다.
- 대상 작성자가 아닌 global admin은 master operational authority에 따라 group-admin-originated hide도 복구할 수 있다.
- 복구에는 hide 사유와 별개의 공개 복구 사유가 필수다. 목표 정책에서는 Group admin restore와
  global admin restore 모두 선택적 내부 메모를 허용한다.
- restore는 현재 미복구 hide만 대상으로 하고 해당 hide를 `reversal_of`로 참조한다.
  `hide A → restore A → hide B → restore B → hide C`의 모든 row를 보존하며 현재 hide는 최신 미복구 hide 하나다.

#### 조회와 사용자-facing 정보

- group-admin-originated hide는 post 존재를 제거하는 조치가 아니라 본문 콘텐츠를 가리는 조치다.
- 기존 Group read boundary 안의 일반 사용자는 Group 상세 목록에서 group-origin hidden Jjaek 카드를 계속 본다.
  일반 짹과 책짹에 각각 기존 `동아리 관리자에 의해 숨겨진 짹입니다.`,
  `동아리 관리자에 의해 숨겨진 책짹입니다.` placeholder와 현재 hide의 공개 사유를 표시하고 원문 body는 HTML에 포함하지 않는다.
- group-origin hidden 카드에는 기존 좋아요 관련 요약, 댓글 수, 댓글 보기와 글 보기 맥락을 유지한다.
  다시짹 등 요구되지 않은 action을 새로 노출하지 않고, 새 Comment·Like·ReJjaek을 비롯한 hidden 상태의 기존 mutation 금지는 유지한다.
- 기존 Group read boundary 안의 일반 사용자는 글 보기로 group-origin hidden Jjaek 상세에 진입할 수 있다.
  상세에서도 원문 body 없이 placeholder와 공개 사유만 표시하고, 기존 댓글은 현재 읽기 권한 범위 안에서 유지한다.
  내부 메모와 Group moderation history는 HTML에 포함하지 않는다.
- 이 placeholder/detail 허용은 Group 자체의 read boundary를 넓히지 않는다. 다른 Group 사용자와 접근할 수 없는
  private Group 비회원 등 기존 비권한 사용자에게는 hidden post의 존재를 노출하지 않는다.
- platform-origin hidden Jjaek의 일반 사용자 목록·상세 정책은 아래 global admin history/visibility 구현 단위를 따른다.
- 작성자는 자기 hidden 원문, 현재 hidden 상태, 숨김 authority와 현재 hide의 공개 사유를 확인하고 자기 삭제만 수행할 수 있다.
- 현재 Group admin은 기존 Group read 권한과 lifecycle 경계 안에서 자기 Group의 hidden 원문,
  현재 hidden 상태, 숨김 authority와 현재 hide의 공개 사유를 조사할 수 있다.
- 사용자-facing 숨김 authority는 실제 actor 이름이 아니라 `시스템 관리자` 또는 `동아리 관리자`로 구분한다.
  실제 actor와 전체 hide/restore 이력은 내부 감사에 보존한다.
- 목표 정책에서 현재 Group admin은 자기 Group의 group-origin internal moderation note만 열람할 수 있다.
  이전 Group admin이 남긴 메모도 현재 운영 권한을 승계한 Group admin이 열람하며, 관리 권한을 잃은 이전 관리자는 더 이상 열람할 수 없다.
  다른 Group의 메모, platform-origin internal moderation note와 platform 전체 moderation audit는 노출하지 않는다.
- 대상 작성자가 아닌 global admin은 기존 운영 조사 권한으로 원문, 실제 actor, 공개 사유,
  platform-origin과 group-origin 내부 메모 및 전체 감사 이력을 확인할 수 있다.
- 목표 정책의 Group admin hide/restore form에는 공개 사유와 명확히 구분된 선택적 `내부 메모` 필드를 제공한다.
  이 메모는 작성자와 일반 회원에게 노출하지 않는다.
- Group admin이 숨긴 일반 짹은 `동아리 관리자에 의해 숨겨진 짹입니다.`로 표시한다.
- Group admin이 숨긴 책짹은 `동아리 관리자에 의해 숨겨진 책짹입니다.`로 표시한다.
  `동아리 관리자에게 숨겨진` 표현은 사용하지 않는다.

#### Acceptance criteria

1. 현재 Group admin은 운영 정지되지 않은 active/inactive 자기 Group의 타인 짹·책짹만 숨길 수 있다.
2. 자기 글, personal Jjaek, 다른 Group Jjaek, pending Group Jjaek과 운영 정지된 Group Jjaek은 direct request에서도 거부한다.
3. global admin 작성 Group Jjaek은 Group admin moderation 대상이 아니며 hide/restore direct request를 모두 거부한다.
   작성자는 기존 작성자 권한 조건 안에서 수정·삭제하고 다른 global admin만 기존 platform moderation 정책을 사용할 수 있다.
4. Group admin hide/restore는 공개 사유를 필수로 받고 선택적 internal note를 허용하며, 기존 hidden 상태와 append-only 감사를 원자적으로 기록한다.
   실제 actor, 공개 사유, internal note, `moderation_authority` snapshot과 restore의 `reversal_of` 연결을 보존한다.
5. 현재 Group admin은 같은 Group authority에서 발생한 현재 hide를 actor 변경과 관계없이 복구할 수 있지만 global admin hide는 복구할 수 없다.
6. 대상 작성자가 아닌 global admin은 group-admin-originated hide를 복구할 수 있으며 각 restore는 별도 공개 복구 사유와 `reversal_of` 연결을 남긴다.
7. hidden 원문의 조회 권한과 restore 권한을 별도로 판단한다. 현재 Group admin은 자기 Group의 group-origin internal note만
   관리자 변경과 관계없이 열람하고, 다른 Group 또는 platform-origin internal note와 platform 전체 감사 이력은 열람하지 못한다.
8. group-admin-originated hide도 기존 작성자 조회·삭제, 새 interaction 차단과 반복 hide/restore 규칙을 그대로 따른다.
9. 사용자-facing 문구는 Jjaek 종류에 따라 `동아리 관리자에 의해 숨겨진 짹입니다.` 또는
   `동아리 관리자에 의해 숨겨진 책짹입니다.`를 사용한다.
10. 기존 Group read boundary 안의 일반 사용자는 Group 상세에서 group-origin hidden Jjaek 카드를 보지만 원문 body는 HTML에서 볼 수 없다.
11. group-origin hidden 카드와 상세에는 placeholder와 공개 사유가 표시되고, 카드에는 좋아요 관련 요약·댓글 수·댓글 보기·글 보기를 유지한다.
12. 일반 사용자는 group-origin hidden 상세에 진입해 기존 댓글을 현재 읽기 범위 안에서 볼 수 있지만 원문 body, 내부 메모와 운영 이력은 볼 수 없다.
13. hidden 상태의 새 interaction 권한은 추가하지 않고, Group read boundary 밖 사용자에게 post 존재를 노출하지 않는다.
14. 현재 Group admin, global admin과 작성자의 기존 특별 권한 및 platform-origin hide 동작은 변경하지 않는다.

#### Group moderation history UI 구현 단위

- Group Jjaek과 Group Book Jjaek 상세에는 현재 Group admin을 위한 작은 `운영 이력` 영역을
  기존 `동아리 콘텐츠 관리` 영역 안이나 바로 인접한 위치에 제공한다. 별도 route, page, dashboard는 만들지 않는다.
- 대상 Jjaek의 `ModerationAction` 중 `moderation_authority == "group"`이고 `action_type`이
  hide 또는 restore인 모든 row를 오래된 조치부터 최신 조치 순서로 표시한다.
- 현재 hidden 여부와 관계없이 과거 이력을 누적 표시한다. 반복 hide/restore cycle에서도 기존 row를
  수정하거나 덮어쓰지 않고 모든 hide와 restore를 보존한다.
- 각 항목은 global admin 운영 이력과 같은 정보 구조와 시각적 문법으로 authority source(`동아리 관리자`),
  조치 종류(숨김/복구), 실제 actor 이름, `public_reason`, present인 `internal_note`, 조치 시각을 표시한다.
  `internal_note`는 공개 사유와 같은 일반 본문으로 이어 붙이지 않고 별도 memo 표현을 사용한다.
  `reversal_of` 연결은 보존하되 ID를 UI에 표시하지 않는다.
- 열람 권한은 개인 actor가 아니라 현재 Group 운영 권한에 귀속한다. 현재 Group admin은 이전 관리자가 남긴
  group-origin 이력도 볼 수 있고, 이전 Group admin은 권한을 잃은 뒤 볼 수 없다.
- 작성자, 일반 Group 회원, 이전 Group admin, 다른 Group의 Group admin과 비회원에게는 이력 HTML 자체를 노출하지 않는다.
- `moderation_authority == "platform"`인 hide/restore의 공개 사유, 내부 메모, actor와 시각은
  Group 운영 이력에 포함하지 않는다.
- Group admin이 볼 수 있는 이력은 기존 권한대로 group-origin action뿐이므로 authority source는
  `동아리 관리자`로 표시한다. 이 표시는 이력 조회 범위를 확대하지 않는다.

Acceptance criteria:

1. group-origin hide 뒤 현재 Group admin에게 hide 이력이 표시된다.
2. restore 뒤와 visible 상태에서도 이전 hide와 restore 이력이 모두 표시된다.
3. 반복 hide/restore cycle의 모든 group-origin action을 오래된 순서로 표시한다.
4. 현재 Group admin은 이전 Group admin이 남긴 이력도 볼 수 있고, 이전 관리자는 권한 상실 뒤 볼 수 없다.
5. 작성자, 일반 회원, 다른 Group의 Group admin과 비회원에게 운영 이력을 노출하지 않는다.
6. platform-origin moderation history를 Group admin에게 노출하지 않는다.
7. 별도 dashboard, route 또는 history page를 만들지 않는다.

#### global admin Jjaek moderation history와 platform-origin hidden visibility 구현 단위

이 단위는 현재 구현되어 있다. 기존 `ModerationAction`, immutable
`moderation_authority`, hidden placeholder와 comments Turbo/read actions를 재사용하고 새 model, migration,
별도 history route·dashboard는 만들지 않는다.

##### global admin moderation history

- 대상 작성자가 아닌 global admin은 일반 Jjaek, Book Jjaek, Group Jjaek과 Group Book Jjaek 상세에서
  해당 Jjaek의 hide/restore 전체 이력을 조사할 수 있다.
- master operational authority에 따라 `moderation_authority == "platform"`인 action뿐 아니라
  `moderation_authority == "group"`인 action도 함께 표시한다. 각 action에는 사용자-facing 표현으로
  `시스템 관리자` 또는 `동아리 관리자` authority source를 구분해 표시하고 내부 enum 값은 노출하지 않는다.
- 각 항목은 조치 종류(숨김/복구), 실제 actor, `public_reason`, 조치 시각과 present인 `internal_note`를 표시한다.
  `created_at ASC, id ASC` 순서로 모든 반복 hide/restore cycle을 누적 표시하며 `reversal_of` ID는 UI에 노출하지 않는다.
- 대상 작성자인 global admin에게는 author-first 경계를 적용해 자기 글의 내부 메모, moderation history와
  hide/restore control을 운영자 권한으로 우회 제공하지 않는다.
- 현재 Group admin의 이력 영역은 기존대로 자기 Group의 group-origin 이력만 표시한다.
  platform-origin history/internal note와 다른 Group 이력은 노출하지 않는다.
- 작성자, 일반 사용자, 이전 Group admin과 관련 없는 Group admin에게 moderation history와 internal note를 노출하지 않는다.

##### Jjaek moderation 운영 UI consistency

- 같은 Jjaek moderation 개념은 운영자 종류와 관계없이 동일한 정보 구조와 시각적 문법을 사용한다.
- 현재 상태와 현재 가능한 조치는 `콘텐츠 관리` 카드에 표시하고 과거 조치 정보는 중복 표시하지 않는다.
  카드에는 현재 상태(`공개`/`숨김`), 현재 가능한 action form, `public_reason`, 선택적 `internal_note`, action button을 둔다.
- 상태 용어는 `공개`/`숨김`, action button은 `숨김`/`숨김 해제`, 운영 이력의 action은 `숨김`/`복구`로 구분한다.
- 과거 조치는 별도 `운영 이력` 카드에 `created_at ASC, id ASC` 순서로 표시하고 반복 hide/restore cycle을 모두 보존한다.
- Group admin과 global admin의 각 history entry는 authority source(`시스템 관리자`/`동아리 관리자`),
  조치 종류, 실제 처리자, `public_reason`, present인 `internal_note`, 처리 시각을 같은 순서와 디자인 문법으로 표시한다.
- `internal_note`는 `public_reason`과 같은 일반 본문으로 이어 붙이지 않고, 현재 Group admin UI의 별도 memo 시각 표현을 공통으로 사용한다.
- 이 문법은 일반 짹, 책짹, Group 짹, Group 책짹에 동일하게 적용한다.
- UI 일관성은 권한 통일을 뜻하지 않는다. global admin, 현재 Group admin, 작성자, 일반 사용자의 기존 조회·조치 범위,
  internal note/history 노출 범위, platform-origin restore 제한과 author-first 경계를 그대로 유지한다.

##### platform-origin hidden visibility와 읽기 맥락

- platform-origin hide도 글의 존재를 삭제하지 않고 본문을 가린다. 기존 read boundary 안의 사용자는
  feed, profile, Book과 Group 문맥에서 원래 볼 수 있었던 Jjaek의 hidden 카드를 계속 볼 수 있다.
- 일반 짹에는 `시스템 관리자에 의해 숨겨진 짹입니다.`, 책짹에는
  `시스템 관리자에 의해 숨겨진 책짹입니다.` placeholder와 현재 hide의 공개 사유를 표시한다.
  원문 body는 목록 HTML에 포함하지 않는다.
- hidden 카드에는 좋아요 수/요약, 댓글 수, 댓글 보기와 글 보기를 유지한다. 기존 댓글은 보존하고 읽을 수 있지만
  새 Like·Comment·ReJjaek과 기타 hidden mutation 권한은 추가하지 않는다.
- 기존 read boundary 안의 사용자는 글 보기로 hidden 상세에 진입할 수 있다. 상세에서도 원문 body 대신
  placeholder와 공개 사유를 표시하고 기존 댓글 읽기를 유지하되 internal note, moderation history와 admin control은 노출하지 않는다.
- private Group 비회원, 원래 visibility 밖 사용자와 그 밖의 기존 비권한 사용자에게 hidden post 존재를 새로 노출하지 않는다.
- 작성자는 자기 hidden 원문, 숨김 주체와 공개 사유를 확인하고 기존 삭제 lifecycle을 사용할 수 있지만
  edit와 새 interaction은 계속 제한된다. 현재 Group admin의 조사·복구·이력 권한은 확대하지 않는다.
- hide authority는 actor의 현재 role이 아니라 action 시점의 immutable `moderation_authority` snapshot으로 판단한다.

Acceptance criteria:

1. 대상 작성자가 아닌 global admin은 Jjaek 상세에서 platform-origin과 group-origin hide/restore 전체 이력을 본다.
2. history의 각 action은 authority source, action type, 실제 actor, public reason, optional internal note와 시각을 표시한다.
3. history는 `created_at ASC, id ASC`로 정렬하고 반복 hide/restore cycle 전체를 보존한다.
4. 기존 read boundary 안의 일반 사용자는 platform-origin hidden 카드를 보지만 목록과 상세 HTML에서 원문 body를 볼 수 없다.
5. 시스템 관리자 placeholder와 공개 사유, 좋아요 요약, 댓글 수, 댓글 보기와 글 보기를 유지한다.
6. hidden 상세 접근과 기존 댓글 읽기는 허용하되 새 Like·Comment·ReJjaek 등 mutation 권한은 확대하지 않는다.
7. 일반 사용자에게 internal note, moderation history와 admin control을 노출하지 않는다.
8. 작성자의 기존 hidden lifecycle과 author-first 경계를 유지한다.
9. 현재 Group admin의 group-origin history/internal note 범위와 platform-origin restore 금지를 변경하지 않는다.
10. 기존 visibility와 Group read boundary 밖 사용자에게 hidden post 존재를 새로 노출하지 않는다.
11. authority source는 immutable `moderation_authority` snapshot으로 판단한다.
12. Comment moderation은 이 구현 단위에 포함하지 않는다.

#### 후속 범위

- 별도 후속 브랜치의 Comment 숨김·복구, authority/history/placeholder, hidden parent Jjaek의 Comment UI와
  댓글이 없고 작성할 수도 없을 때 빈 comments panel을 표시하지 않는 정책
- teacher/Classroom moderation
- 신고 queue, notification, rate limit

이번 구현 단위에는 Comment moderation, 신고, notification,
Classroom 역할, 새로운 moderation framework와 작성자 삭제 lifecycle 변경을 포함하지 않는다.

이 구현 단위는 새 moderation schema나 framework를 추가하지 않는다.

---

## 책임과 권한 범위

### global admin의 master operational authority

global admin은 서비스 전체에 대한 최종 운영 책임과 운영 개입 권한을 가진다. 이는 전체 User·Group·Jjaek·Comment와
일반 사용자가 볼 수 없는 비공개 콘텐츠를 조사하고, 현재 또는 향후 마련되는 명시적인 운영 조치를 수행할 근거다.
현재 Group 기능에서는 승인과 운영 정보 조사뿐 아니라 운영상 필요한 active/inactive Group 관리자 이전을 포함한다.

이 권한은 모든 사용자 action을 대신 수행하는 superuser 권한이 아니다. 타인 이름의 Jjaek·Comment 작성, 타인의 원문
수정이나 작성자 삭제를 가장한 hard delete, 타인을 대신한 Like, 개인 Library·Bookshelf 관리 대행은 허용하지 않는다.
`ApplicationPolicy`에 모든 action을 허용하는 global admin bypass를 두지 않고 action별 운영 목적을 명시한다.
Group 자체를 탐색하는 일반 Group scope와 특정 User를 조사하는 profile scope는 global admin에게 해당 문맥 전체를 제공한다.
반면 일반 Jjaek scope와 홈 feed scope는 UI 의미를 보존하기 위해 넓히지 않으며 전체 사용자 콘텐츠 조사의 기본 진입점은
admin inventory, 특정 User·Group 상세와 거기서 발견한 Jjaek 단건 상세다.

| 역할 | 책임 범위 | 허용되는 목표 권한 | 허용하지 않는 범위 |
| --- | --- | --- | --- |
| global admin | 서비스 전체 | 전체 User·Group·Jjaek·Comment 조회, 운영 목적의 비공개 Group 및 향후 Classroom 콘텐츠 확인, User 정지·복구, Jjaek·Comment 숨김·복구, Group 운영 정지·복구와 관리자 이전 판단, moderation 이력과 platform/group-origin 내부 메모 확인 | 운영자가 작성자 대신 원문을 수정하거나 작성자 삭제로 처리하는 행위 |
| group admin | 자신이 관리하는 Group | 구성원·가입 요청·초대와 기존 lifecycle 관리, 자기 Group의 타인 Jjaek·책짹·Comment를 사유와 함께 숨김·복구, 자기 Group의 group-origin Jjaek moderation 내부 메모 입력·열람 | 서비스 전체 User 정지, 다른 Group이나 일반 공개 프로필 콘텐츠 관리, 원문 수정·hard delete, 신고자 신원·platform-origin 및 다른 Group 내부 메모 열람 |
| teacher | 자신이 담당하는 Classroom과 managed student account | 담당 학생·콘텐츠·상호작용 관리, 담당 Classroom 콘텐츠를 사유와 함께 숨김·복구 | 공개 SNS 전체, 일반 User, 다른 교사의 Classroom 관리 |
| platform moderator | 향후 위임받을 공개 SNS 운영 범위 | User·Group·Jjaek·Comment 조사와 정해진 moderation 조치를 위임받을 수 있다는 원칙만 확정 | global admin 지정·해제, 서비스 핵심 설정, 소유권·교사 권한 관리 |

global admin의 비공개 콘텐츠 접근은 일반 사용자 열람 권한이 아니라 조사·안전·복구를 위한 운영 권한이다.
`private_jjaek`의 나만 보기와 `book_friends` visibility를 포함한 사용자 공개 설정은 이 운영 조사를 차단하지 않는다.
group admin은 현재와 같이 Group당 정확히 한 명이며 이번 MVP에서 cardinality를 변경하지 않는다.

teacher/Classroom policy는 Classroom 도메인이 만들어질 때 연결한다. 교사와 학생이 실제 사용하기 전에는
teacher의 자기 Classroom 관리 기능이 반드시 완성되어야 한다.

`platform_moderator`는 global admin의 공개 SNS moderation 병목을 줄이기 위한 미래 위임 역할이다.
이번 MVP에서는 role, DB 필드, UI, 권한을 구현하지 않는다. 이후 도입할 때 global admin 조건을 여러 policy에
복사하지 않고 공통 platform moderation 권한으로 분리할 수 있어야 하며 `p_moderator` 같은 축약어를 사용하지 않는다.
운영 기능을 다른 역할에 위임할 수 있지만 global admin 자체 권한 부여는 global admin만 수행한다.

---

## Moderation 조치 기록

공통 감사 기반인 `ModerationAction`은 append-only action log로 구현되어 다음 정보를 보존한다.

- 대상 종류와 대상 ID
- 조치 종류(`suspend`, `hide`, `restore`)
- 공개 가능한 사유
- 필요한 경우 공개 사유와 분리된 내부 운영 메모
- 처리자와 `created_at` 조치 시각
- 복구는 원 조치 row를 변경하지 않고 별도 row로 추가하며 `reversal_of`로 원 조치와 연결

정지·숨김 row는 복구 연결을 갖지 않으며 같은 원 조치를 두 번 복구할 수 없다.
이미 저장된 감사 row는 수정·삭제할 수 없고 대상이 hard delete되더라도 target type/ID와 감사 정보는 보존한다.
운영자는 콘텐츠 원문을 수정하지 않는다.

User 정지/복구, Jjaek 숨김·복구와 Group 운영 정지/복구는 이 감사 기반에 연결되어 있다.
Group admin의 Jjaek 숨김·복구는 구현되어 있고 Comment 숨김·복구는 아직 구현되지 않았다.

---

## 사용자에게 보이는 정보

- 정지된 사용자는 로그인 시 일반 인증 실패와 구분되는 제한 상태를 확인할 수 있어야 한다.
- 숨겨진 콘텐츠 작성자는 제한 상태와 공개 가능한 사유를 확인할 수 있어야 한다.
- 신고자 신원과 내부 운영 메모는 대상 사용자에게 공개하지 않는다.
- 최소 MVP에서는 상태와 공개 사유를 해당 계정·콘텐츠 화면에서 확인할 수 있어야 한다.
- 별도 Notification inbox 알림 여부는 moderation action UI가 확정될 때 결정한다.

---

## 기본 남용 예방

Classroom의 실제 교사·학생 사용 전에 다음 경로에 기본 rate limit을 둔다.

- 회원가입
- 로그인 실패
- Jjaek·책짹 작성
- Comment 작성
- Like 등 반복 mutation
- Group 생성·가입 요청·초대

정확한 횟수와 시간창은 구현 브랜치에서 운영 환경과 사용자 흐름을 확인해 결정한다.
rate limit은 환경별로 조정할 수 있어야 하며 정상적인 한 교실의 동시 사용을 악성 트래픽으로 오인하지 않아야 한다.

---

## 운영 모니터링과 inventory

### 목적

- moderation 관리 도구는 발견, 조사, 조치, 복구, 감사의 흐름을 지원한다.
- inventory는 단순 전체 목록이 아니라 운영자가 많은 자료를 빠르게 훑는 고밀도 관리 화면이다.
- 카드 중심의 일반 사용자 UI가 아니라 표, 상태 badge, 검색, 조합 가능한 필터, 정렬, 페이지네이션을 사용한다.
- 기본 정렬은 최근 생성 또는 최근 활동 우선으로 한다.
- 목록에서 대상의 핵심 상태와 짧은 내용 일부를 확인하고 상세 조사 화면으로 이동할 수 있어야 한다.
- 필터와 페이지 위치는 query parameter로 표현해 새로고침과 뒤로 가기에서도 유지할 수 있어야 한다.
- 필터 초기화 수단을 제공한다.
- pagination 없이 전체 레코드를 한 번에 렌더링하지 않는다.

### 권한 경계

- global admin은 서비스 전체 inventory를 조회한다.
- group admin은 자신이 관리하는 Group 내부의 구성원과 콘텐츠만 모니터링한다.
- teacher는 향후 자신이 담당하는 Classroom과 managed student account만 모니터링한다.
- `platform_moderator`가 도입되면 위임받은 플랫폼 범위에서 같은 monitoring 기반을 재사용한다.
- 서버측 권한 scope를 먼저 적용한 뒤 그 결과 안에서 검색·필터·정렬한다.
- URL query parameter를 조작해 다른 Group·Classroom·비공개 콘텐츠로 조회 범위를 넓힐 수 없어야 한다.
- 필터링은 client 화면에서 항목을 감추는 방식만으로 구현하지 않는다.

### 대상별 최소 검색·필터

| 대상 | 검색 | 최소 필터 | 최소 정렬·표시 |
| --- | --- | --- | --- |
| User | 이름·이메일 | 정상·향후 정지·탈퇴 상태, global admin 여부, 가입 기간, 향후 일반 계정·managed student account 구분 | 최근 가입·오래된 가입, 계정 상태, 가입 시각 |
| Group | 이름·group admin | Group 종류, pending/active/inactive lifecycle, 향후 운영 정지 상태, 생성 기간 | 최근 생성·최근 갱신, group admin, 구성원 수와 상태 |
| Jjaek·책짹 | 본문 일부·작성자·관련 책 | 개인·Group·향후 Classroom 문맥, 짹·책짹·ReJjaek 종류, visibility, 작성자 삭제·향후 운영 숨김 상태, 작성 기간 | 최신·오래된 순, 작성자, 문맥, 상태, 짧은 내용 |
| Comment | 본문 일부·작성자·원 Jjaek | 개인·Group·향후 Classroom 문맥, 정상·향후 운영 숨김 상태, 작성 기간 | 최신·오래된 순, 작성자, 원 Jjaek, 상태, 짧은 내용 |
| Moderation 이력 | 대상·처리자 | 조치 종류, 대상 종류, 유효·복구 상태, 처리 기간 | 최근 조치·복구 순, 처리자, 사유, 상태 |

표에서 현재 schema에 없는 정지·운영 숨김·managed student account·Classroom·moderation 이력 상태는
각 moderation 또는 Classroom 구현 후 제공할 필터다. 이 표는 query class, scope, gem이나 DB 구조를 확정하지 않는다.

### 기본적인 활동 관찰

- 최근 일정 기간에 생성된 User·Group·Jjaek·Comment를 좁혀 볼 수 있다.
- 특정 사용자, Group 또는 작성 기간을 기준으로 콘텐츠를 연속해서 확인할 수 있다.
- 최근 작성량이 많은 사용자를 확인할 필요가 있지만 초기에는 기존 데이터로 안전하고 효율적으로 계산할 수 있는 범위에서 제공한다.
- 신규 가입 직후 반복 작성처럼 운영자가 직접 확인할 가치가 있는 패턴을 필터 조합으로 좁힐 수 있어야 한다.
- 자동으로 악성 사용자라고 판정하거나 제재하지 않는다.
- 의심 활동 표시만으로 정지·숨김이 실행되지 않으며 운영자의 개별 확인과 사유 입력이 필요하다.

### 과도한 감시 방지

moderation monitoring에는 다음을 포함하지 않는다.

- 일반 사용자의 모든 페이지 열람 기록 수집
- 독서 시간이나 클릭 경로 추적
- 기기 fingerprinting
- 필요 이상의 IP·위치 정보 보존
- 사용자별 위험 점수나 비공개 평판 점수
- 실시간 전면 감시 dashboard
- AI에 의한 자동 유해 판정과 자동 제재
- monitoring을 위한 새로운 개인정보의 무제한 수집

운영 모니터링은 이미 서비스 운영에 필요한 계정·콘텐츠·상태·작성 시각을 중심으로 하며,
새로운 행동 추적 시스템을 의미하지 않는다.

### 안전성과 성능

- 검색어와 필터 값은 서버에서 검증한다.
- 잘못된 필터 값은 권한 범위를 넓히거나 오류 정보를 노출하지 않아야 한다.
- 목록 query에서 N+1을 피한다.
- 구성원 수·콘텐츠 수 같은 집계는 전체 row를 메모리에 올리지 않는 방식이어야 한다.
- 검색·필터를 위해 필요한 index는 실제 구현 브랜치에서 query와 데이터 규모를 확인한 뒤 결정한다.
- 초기 MVP에서는 저장된 filter preset, 복잡한 분석 chart, export, bulk action을 추가하지 않는다.

---

## Classroom 구현 전 최소 완료 범위

다음은 Classroom의 본격적인 교사·학생 운영 전에 완료할 필수 기반이다.

- global admin의 User 모니터링 목록: 검색·상태 필터·가입 기간·정렬·페이지네이션
- global admin의 Group 모니터링 목록: 검색·종류·lifecycle 필터·정렬·페이지네이션
- global admin의 Jjaek·Comment 모니터링 목록: 검색·작성자·문맥·종류·상태·작성 기간 필터·정렬·페이지네이션
- User 정지·복구
- Jjaek·책짹·Comment 숨김·복구
- group admin의 자기 Group 콘텐츠 검색·필터와 숨김·복구
- 모든 moderation 조치의 사유·처리자·시각 기록
- 가입·로그인·작성의 기본 rate limit

teacher의 자기 Classroom moderation은 Classroom 구조가 존재해야 구현할 수 있으므로 Classroom 개발과 함께 연결하되,
실제 교사·학생 배포 전 필수 release gate로 둔다.

---

## 상태 분리

| 대상 | 정상 상태 | 사용자 lifecycle | 운영 moderation | 재사용하면 안 되는 상태 |
| --- | --- | --- | --- | --- |
| User | 정상 | 본인 탈퇴 | 운영자 정지 | `withdrawn_at`을 정지로 재사용 금지 |
| Group | 운영 중 | group admin 종료·비활성 | 플랫폼 운영 정지 | `inactive`를 운영 정지로 재사용 금지 |
| Jjaek·Comment | 정상 | 작성자 삭제 | 운영자 숨김 | `deleted_at`을 숨김으로 재사용 금지 |
| GroupMembership | 참여 상태 | 탈퇴·내보내기 | 향후 별도 제한 | membership 종료를 ban으로 해석 금지 |

이 표는 의미와 불변 조건만 고정하며 schema 설계를 확정하지 않는다.

---

## 이번 MVP에서 제외하는 기능

- `platform_moderator` 실제 role과 관리 UI
- 사용자 신고 접수와 신고 queue
- 대량 bulk moderation
- AI 자동 moderation
- strike 또는 점수 시스템
- shadow ban
- 완전한 appeal workflow
- 외부 moderation 서비스
- 학생 콘텐츠 자동 공개
- 여러 group admin
- Classroom schema·PIN 인증·학생 명단
- 정교한 운영 분석 dashboard

---

## 권장 구현 순서

각 단계는 가능한 한 별도 기능 브랜치로 나눈다.

1. global admin 공통 navigation과 User·Group 읽기 전용 monitoring inventory
   - 고밀도 표
   - 검색
   - 조합 가능한 기본 필터
   - 정렬
   - 페이지네이션
2. Jjaek·Comment 읽기 전용 monitoring inventory
   - 작성자·문맥·종류·상태·기간 필터
   - 짧은 내용 표시
   - 상세 조사 진입
3. 공통 moderation action 감사 기반
4. User 정지·복구
5. Jjaek·Comment 숨김·복구
6. group admin의 자기 Group 콘텐츠 moderation
7. 가입·로그인·작성 rate limit
8. Classroom 도메인과 managed student account
9. teacher의 자기 Classroom moderation 연결
10. 교사·학생 실제 사용 검증
11. 필요성이 확인되면 신고 queue와 `platform_moderator`

첫 구현 브랜치 `feature/admin-moderation-inventory`의 목적은 단순 조회 화면이 아니라 global admin의
User·Group monitoring과 filtering 기반을 구축하는 것이다. 정지·숨김·복구·bulk action·신고·
`platform_moderator`·자동 판정은 이 브랜치에서 제외한다.
