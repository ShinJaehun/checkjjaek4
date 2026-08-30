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
- **동아리 운영 정지 / 동아리 운영 복구**는 global admin이 향후 `Group` 자체의 서비스 운영 상태를 제한·복구하는 개념이다. group admin의 기존 자발적 운영 종료 lifecycle과 별도 상태로 구현한다.

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
- 일반 사용자 조회와 댓글·Like·ReJjaek 등 후속 상호작용을 차단한다.
- global admin은 조사와 복구를 위해 확인할 수 있다.
- 작성자는 자신의 콘텐츠가 제한됐다는 사실과 공개 가능한 조치 사유를 확인할 수 있다.
- 숨김을 해제해도 작성자가 이미 삭제했다면 작성자 삭제 상태가 유지된다.
- Jjaek의 `deleted_at`을 moderation 숨김에 재사용하지 않는다.
- Comment hard delete와 moderation 숨김을 같은 상태로 기록하지 않는다.

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
| global admin | 서비스 전체 | 전체 User·Group·Jjaek·Comment 조회, 운영 목적의 비공개 Group 및 향후 Classroom 콘텐츠 확인, User 정지·복구, Jjaek·Comment 숨김·복구, Group 운영 정지·복구와 관리자 이전 판단, moderation 이력 확인 | 운영자가 작성자 대신 원문을 수정하거나 작성자 삭제로 처리하는 행위 |
| group admin | 자신이 관리하는 Group | 구성원·가입 요청·초대와 기존 lifecycle 관리, 자기 Group의 타인 Jjaek·책짹·Comment를 사유와 함께 숨김·복구 | 서비스 전체 User 정지, 다른 Group이나 일반 공개 프로필 콘텐츠 관리, 원문 수정·hard delete, 신고자 신원·global admin 내부 메모 열람 |
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

User 정지/복구는 이 감사 기반에 연결되어 있다. Jjaek·Comment 숨김/복구, Group 운영 정지/복구와
그에 대응하는 authorization, action endpoint와 UI는 아직 구현되지 않았다.

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
