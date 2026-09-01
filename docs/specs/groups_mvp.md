# 동아리 MVP

## 목적

이 문서는 앞으로 구현할 일반 사용자용 동아리 기능의 제품 정책을 정리한다.

동아리는 일반 사용자가 함께 읽고 기록하고 토론하는 독서 공동체다.
내부적으로 `Group` 모델과 `GroupMembership` 모델로 구현한다.
현재 시스템 구조를 설명하는 architecture 문서가 아니라, 구현 전 기준이 되는 목표 spec이다.
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
- 일반 active member 탈퇴와 현재 관리자 membership 삭제 방지
- 비공개 동아리의 관리자/active member 조회 권한 기반
- 비공개 동아리 생성과 관리자의 기존 사용자 초대
- 받은 초대의 수락·거절
- 동아리 관리자의 이름·소개 수정과 다른 active member로의 관리자 권한 이전
- 동아리 관리자의 active 구성원 내보내기, 승인 요청 거절, 보낸 초대 취소
- membership 가입·신청·승인·거절·초대·수락·거절·취소·탈퇴·내보내기를 Group 단위 append-only 이력으로 보존
- 동아리 안의 `짹`과 `책짹` 작성·조회
- 권한 있는 사용자의 작성자 프로필에서 동아리의 `짹`과 `책짹` 조회
- 일반 사용자의 동아리 신청과 global admin 승인
- 동아리 관리자의 동아리 운영 종료와 재활성화 요청·재승인
- 신규 신청의 개설 목적과 운영 종료 사유·시각 기록
- 신청·승인·운영 종료·재활성화·재승인의 시각과 목적/사유 snapshot을 운영 이력으로 누적
- 동아리 관리자 화면은 운영 시각 중심으로, global admin 운영 상세는 목적·사유 snapshot을 포함해 이력을 표시

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
개인 Jjaek의 동아리 공유와 동아리 안에서의 ReJjaek 작성,
초대 알림, 이메일·링크 초대와 moderation 상세는 미구현이며,
이 문서의 해당 내용은 계속 목표 정책으로 읽는다.

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

## 가입·발견 정책

- 공개 동아리는 발견 가능하며 로그인 사용자가 즉시 가입할 수 있다.
- 승인 동아리는 발견 가능하지만 가입 승인이 필요하다.
- 비공개 동아리는 일반 발견 대상에서 제외하며 초대를 기본 진입점으로 삼는다.
- 일반 사용자의 생성을 운영 신청으로 보고, global admin 승인 전에는 정상 운영하지 않는다.
- global admin이 직접 생성한 동아리는 승인 대기를 거치지 않고 즉시 `active`로 시작한다. 이는 다른 사용자가 만든 pending 동아리의 자동 승인을 뜻하지 않는다.
- 신규 신청에는 일반 소개와 별도의 동아리 개설 목적을 제출하며 group admin과 global admin만 확인한다.
- 승인·운영 lifecycle의 상세 기준은 `docs/specs/account_group_lifecycle.md`를 따른다.
- 동아리 생성 횟수 제한, 계정 연령, 남용 방지 조건은 아직 결정하지 않는다.

---

## 동아리 Jjaek 작성·조회

현재 Jjaek의 `public_jjaek`, `book_friends`, `private_jjaek`은 사용자 관계를 기준으로 한 개인 Jjaek의 공개 범위다.
동아리는 별도의 게시 공간이므로, 동아리 접근 권한을 기존 visibility 값으로 표현하지 않는다.

- 동아리에서 새 Jjaek을 작성할 때 개인 Jjaek의 visibility 선택 UI를 그대로 제공하지 않는다.
- 동아리 Jjaek의 가시성은 해당 동아리의 접근 정책을 따른다.
- 공개 동아리에서는 동아리 비회원인 로그인 사용자도 글을 읽을 수 있지만 작성할 수 없다.
- 승인 동아리와 비공개 동아리에서는 현재 멤버만 글을 읽고 작성할 수 있다.
- 동아리 접근 권한이 없는 경로를 통해 동아리 Jjaek을 조회할 수 없어야 한다.

동아리 문맥을 기존 `visibility_rank`만으로 표현할 수 있다고 전제하지 않는다.

---

## 홈 피드와 프로필 노출

홈 피드 편입과 프로필에서의 조회 가능 여부는 서로 다른 정책이다.

### 홈 피드

- 동아리에 작성한 Jjaek은 해당 동아리 피드에 나타난다.
- 현재 사용자가 active member인 active/inactive 동아리의 기존 Jjaek은 종류와 작성자에 관계없이 홈 피드에 포함한다.
- active membership이 없는 동아리의 Jjaek은 public 동아리이거나 followee가 작성했더라도 홈 피드에 포함하지 않는다.
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
기존 ReJjaek의 현재 구현 기준은 `docs/specs/requotes_mvp.md`와 관련 architecture 문서를 함께 본다.

---

## 개인 영역에서 동아리로 공유

기존 개인 Jjaek을 동아리로 가져오는 것은 자동 복제가 아니라 명시적인 “동아리에 공유” 동작이다.

초기 MVP에서는 다음만 허용한다.

- `public_jjaek`은 동아리에 공유할 수 있다.
- `book_friends`는 동아리에 공유할 수 없다.
- `private_jjaek`은 동아리에 공유할 수 없다.

공유된 콘텐츠는 원문을 참조하는 crosspost/ReJjaek 계열의 개념으로 본다.
실제 DB 모델이나 association 방식은 이 문서에서 확정하지 않는다.

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
동아리 관리자의 타인 댓글 삭제와 moderation은 아직 구현하지 않는다.

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
- 동아리 관리자의 타인 Jjaek 수정·삭제 moderation은 아직 구현하지 않는다.

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

동아리 관리자는 자기 Group의 Jjaek·책짹·Comment를 사유와 함께 숨김·복구할 수 있어야 한다.
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

## MVP에서 하지 않는 것

- Classroom 구현 또는 상세 설계
- `Space`, `Context` 같은 공통 추상 모델 도입
- polymorphic association 설계 확정
- 동아리 문맥의 DB column, enum, association 확정
- 신고 queue와 `platform_moderator` 실제 구현
- 댓글을 공유 공간 사이에 복사하거나 합쳐 보여주는 기능
- 승인 동아리·비공개 동아리 원문의 외부 ReJjaek
- `book_friends`, `private_jjaek`의 동아리 공유
- nested ReJjaek
- 알림 정책 상세 설계
- 여러 group admin과 Group moderator 역할

---

## 미결정 사항

- 가입·승인·초대·공유와 moderation 관련 Notification inbox 정책
- 동아리 생성 횟수 제한, 계정 연령과 남용 방지 조건
- 탈퇴 후 댓글 삭제를 제공하는 정확한 UI, 메시지와 동선
- 승인 동아리 또는 비공개 동아리 탈퇴 후 원문 조회 권한을 잃은 상태에서 자기 콘텐츠 관리 진입을 제공하는 방식

탈퇴 후 댓글의 보존·작성·수정·삭제 권한과 동아리 관리자의 moderation 책임,
일반 로그인 사용자가 Group을 신청할 수 있는 방향 자체는 미결정 사항이 아니다.
승인·운영 lifecycle은 현재 구현되어 있다.
탈퇴 후 동아리 Jjaek은 보존하며 작성자는 수정할 수 없고 자기 글을 삭제할 수 있다.

---

## 구현 전 확인할 정책 체크리스트

- 동아리의 구현 범위와 아직 미구현인 목표 정책을 구현 문서에서도 구분했는가?
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
