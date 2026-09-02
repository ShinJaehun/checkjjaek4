# Authorization Architecture

## 목적

이 문서는 checkjjaek4의 권한 구조를 정리하기 위한 architecture 문서다.

이 문서는 아래를 설명한다.

- Pundit 기반 권한 구조
- 관계 기준 용어
- 프로필 권한
- Jjaek 권한
- 댓글/좋아요 권한
- 관련 policy 파일 위치

이 문서는 새로운 정책을 정의하지 않는다.
현재 구현은 `docs/architecture/current_system.md`,
목표 상태와 제품 정책은 관련 spec 문서를 기준으로 읽는다.

---

## 권한 구조 개요

checkjjaek4의 서버측 권한 판단은 Pundit policy 중심으로 유지한다.

원칙:

- controller는 가능한 한 `authorize`, `policy_scope`를 호출하는 자리로 남긴다
- 단건 권한 판단은 policy에 둔다
- 목록 조회 범위 판단은 policy scope에 둔다
- view는 가능한 한 controller와 policy에서 정리된 결과를 소비한다

관련 위치:

- `app/policies/application_policy.rb`
- `app/policies/user_policy.rb`
- `app/policies/jjaek_policy.rb`
- `app/policies/bookshelf_policy.rb`
- `app/policies/bookshelf_entry_policy.rb`
- `app/policies/comment_policy.rb`
- `app/policies/like_policy.rb`
- `app/policies/home_policy.rb`
- `app/policies/book_policy.rb`
- `app/policies/book_activity_policy.rb`
- `app/policies/book_friendship_policy.rb`
- `app/policies/book_search_policy.rb`
- `app/policies/group_policy.rb`
- `app/policies/group_membership_policy.rb`

---

## 관계 기준 용어

이 문서에서 쓰는 관계 기준 용어는 아래와 같다.

- `self`
  - 현재 사용자와 프로필/콘텐츠 작성자가 같은 경우
- `follow`
  - 현재 사용자가 해당 사용자를 소식받는 관계인 경우
- `book_friend`
  - 책친구 신청/수락이 완료된 경우
- `stranger`
  - `self`, `follow`, `book_friend` 어느 쪽에도 해당하지 않는 경우

---

## 프로필 권한

### 현재 구현

현재 구현 기준 프로필 / Library 권한 요약:

- 프로필은 항상 공개 요약 화면으로 해석한다.
- Library는 책장 구조가 있는 깊은 서재 상세/관리 화면으로 해석한다.
- 로그인 사용자는 타인 프로필의 공개 가능한 콘텐츠를 볼 수 있다.
- 프로필 책 목록은 관계별 접근 범위에 따라 flat summary 형태로 표시한다.
- `stranger / follow`는 프로필에서 `public` 책 목록만 볼 수 있다.
- `self / accepted book_friend`는 프로필에서 접근 가능한 책 목록 요약을 볼 수 있다.
- 프로필에서는 누구에게도 책장 탭, 책장 정렬 UI, 책장 관리 UI, 책 이동 UI를 보여주지 않는다.
- `stranger / follow`는 프로필에서 Library 링크를 볼 수 없다.
- `self / accepted book_friend`는 프로필에서 Library 링크를 볼 수 있다.
- 프로필 책 목록은 `BookshelfPolicy` / `BookshelfEntryPolicy::ProfileScope`의 Bookshelf visibility 기준을 따른다.
- Bookshelf visibility는 `self`: 전체, `book_friend`: `public` + `book_friends`, `stranger/follow`: `public`만 허용한다.
- 로그인 사용자는 프로필 Jjaek 섹션을 볼 수 있다.
- `stranger / follow`는 `public_jjaek`만 볼 수 있다.
- `book_friend`는 `public_jjaek` + `book_friends`를 볼 수 있다.
- `self`는 전체 Jjaek을 볼 수 있다.
- `stranger / follow`는 프로필 책 목록에서 상태와 스티커를 볼 수 없다.
- `self / accepted book_friend`는 프로필 책 목록에서 상태와 스티커를 볼 수 있다.
- `self / accepted book_friend`는 프로필 최근 활동에서 BookActivity를 볼 수 있다.
- `self / accepted book_friend`는 profile-context Jjaek 작성 진입을 사용할 수 있다.
- Bookshelf 생성/수정/삭제/순서 변경은 Library에서 owner만 가능하며, 새 Bookshelf는 현재 사용자의 Bookshelf로만 생성한다.
- 기본 Bookshelf는 수정/삭제/순서 변경할 수 없고, 책이 들어 있는 일반 Bookshelf는 삭제할 수 없다.
- `BookshelfEntry`의 책장 이동은 Library에서 owner만 가능하며, 대상 Bookshelf도 현재 사용자의 Bookshelf여야 한다.
- Library Screen 접근은 `self / accepted book_friend`에게만 허용하며, follow-only / stranger는 프로필로 redirect한다.
 
### 목표 상태

프로필 목표 규칙은 `docs/specs/social_relationships_mvp.md`를 기준으로 본다.

목표 상태 기준 프로필 Jjaek 조회 권한 요약:

- `stranger`: `public_jjaek`
- `follow`: `public_jjaek`
- `book_friend`: `public_jjaek` + `book_friends`
- `self`: 전체

이 규칙은 Jjaek 조회 범위에 대한 정책이며,
홈 피드 편입 규칙과는 별도로 해석한다.

### Library 접근 정책

Library는 프로필보다 깊은 서재 화면이며, 별도 DB 모델이 아니라 `Bookshelf` / `BookshelfEntry`를 보여주는 사용자별 화면/라우팅 개념이다.

Library 접근 권한:

- `self`: 자신의 Library 전체 접근 가능
- `book_friend`: 상대의 Library 접근 가능
- `follow`: 상대의 Library 접근 불가
- `stranger`: 상대의 Library 접근 불가

Library 안에서 볼 수 있는 책장:

- `self`: `public` + `book_friends` + `private`
- `book_friend`: `public` + `book_friends`

`follow`의 추가 의미는 Library 접근 권한이 아니라 홈 피드 편입이다.
즉, `follow`는 상대의 public Jjaek을 홈 피드에서 받아보는 관계이며,
상대의 서재 구조까지 볼 수 있는 권한은 아니다.

---

## Jjaek 권한

### 조회

현재 구현 기준:

- `JjaekPolicy#show?`는 현재 사용자가 해당 Jjaek을 볼 수 있는지 판단한다
- quoted Jjaek이 있는 경우 quoted Jjaek도 현재 사용자에게 visible 해야 한다
- 동아리의 `짹`과 `책짹`은 개인 visibility보다 동아리 콘텐츠 접근 권한을 우선한다
- 공개 동아리는 로그인 사용자가 조회할 수 있고, 승인/비공개 동아리는 active member만 조회할 수 있다

목표 상태 기준 보완:

- 타인 프로필에서는 `stranger`도 `public_jjaek`을 조회할 수 있어야 한다
- `follow`의 추가 의미는 홈 피드 편입이며,
  프로필 조회 권한 자체는 `stranger`의 `public_jjaek` 조회와 구분한다

관련 위치:

- `app/policies/jjaek_policy.rb`

### 작성

현재 구현 기준:

- 로그인 사용자만 작성 가능하다
- 작성자는 현재 사용자 본인이어야 한다
- 책 문맥 작성은 현재 사용자의 `BookshelfEntry` 존재 여부와 연결된다
- profile-context 작성은 대상 사용자에 대한 권한 규칙을 함께 따른다
- 동아리의 `짹`과 `책짹`은 active member만 작성할 수 있다
- 동아리 책짹도 작성자의 `BookshelfEntry`가 있어야 한다

관련 위치:

- `app/policies/jjaek_policy.rb`
- `app/policies/user_policy.rb`

### 수정 / 삭제

현재 구현 기준:

- 일반 Jjaek의 수정과 삭제는 작성자 본인만 가능하다
- 동아리 Jjaek은 active 작성자만 수정할 수 있고, 작성자는 탈퇴 또는 내보내기 후에도 자기 기존 글을 삭제할 수 있다
- 동아리 관리자에게 타인 Jjaek 수정·삭제 권한은 아직 없다
- 삭제된 Jjaek은 다시 수정하거나 삭제할 수 없으며 새 댓글·좋아요·ReJjaek도 만들 수 없다
- 댓글이 없는 글은 hard delete하고, 댓글이 있는 글은 본문을 제거한 tombstone과 기존 댓글을 보존한다

관련 위치:

- `app/policies/jjaek_policy.rb`

### ReJjaek 가능 여부

현재 구현 기준:

- 현재 사용자가 원문 Jjaek을 볼 수 있어야 한다
- 원문이 `private_jjaek`이면 ReJjaek할 수 없다
- 원문 자체가 ReJjaek이면 다시 인용할 수 없다
- active 공개 동아리의 Jjaek·책짹은 membership 없이 개인 영역으로 ReJjaek할 수 있다
- 승인·비공개·inactive·pending 동아리 원문은 개인 영역으로 ReJjaek할 수 없다
- 같은 사용자가 같은 원문을 이미 ReJjaek했다면 새 ReJjaek 버튼을 보여주지 않는다
- MVP에서는 버튼 숨김만으로 충분하다

### ReJjaek 목록 조회

- 원본 Jjaek을 볼 수 있는 사용자만 ReJjaek 목록에 접근할 수 있다
- `private_jjaek` 원문은 ReJjaek 목록 접근 대상이 아니다
- ReJjaek 자체에 대해서는 ReJjaek 목록을 제공하지 않는다
- 목록에는 현재 사용자가 볼 수 있는 ReJjaek만 표시한다
- 상세 MVP 기준은 `docs/specs/requotes_mvp.md`를 따른다

관련 위치:

- `app/policies/jjaek_policy.rb`
- `app/models/jjaek.rb`

---

## FeedScope

현재 구현에는 홈 피드 전용 `JjaekPolicy::FeedScope`가 있다.

현재 구현 기준:

- 홈 피드는 일반 조회 scope와 별도 규칙으로 계산된다
- 내 Jjaek
- 현재 사용자를 대상으로 한 profile-context Jjaek
- 소식받는 사용자의 공개 Jjaek
- 책친구 공개 Jjaek
- 동아리 Jjaek은 현재 FeedScope에서 제외한다

이 scope는 프로필 조회 권한과 분리해서 읽어야 한다.
특정 사용자의 `public_jjaek`을 프로필에서 볼 수 있다고 해서
그 사용자의 글이 홈 피드에 자동으로 들어오지는 않는다.

관련 위치:

- `app/policies/jjaek_policy.rb`
- `app/controllers/homes_controller.rb`

---

## 댓글 / 좋아요 권한

현재 구현 기준:

- 댓글 읽기·작성·수정과 좋아요는 부모 Jjaek을 볼 수 있는 사용자만 가능하다
- 별도 관계 자체보다 부모 Jjaek 접근 가능 여부를 기준으로 판단한다
- 동아리 댓글은 기존 `Comment` 모델을 사용하고 부모 동아리 Jjaek의 열람 범위를 상속한다
- 공개 동아리 비회원은 댓글을 읽을 수 있지만 active member만 댓글을 작성하고 자기 댓글을 수정할 수 있다
- 탈퇴하거나 내보내진 사용자는 새 댓글 작성·수정은 불가하며 기존 자기 댓글은 삭제할 수 있다
- 동아리 좋아요는 active 동아리의 active member만 새로 만들 수 있다
- 기존 자기 좋아요는 현재 부모 Jjaek을 볼 수 있다면 동아리 운영 종료·membership 종료·Jjaek 삭제 후에도 철회할 수 있다
- 동아리 관리자의 타인 댓글 삭제 권한은 아직 구현하지 않는다

관련 위치:

- `app/policies/comment_policy.rb`
- `app/policies/like_policy.rb`
- `app/policies/jjaek_policy.rb`

---

## 동아리 기반 권한

현재 구현된 동아리 기반은 `GroupPolicy`와 `GroupMembershipPolicy`를 사용한다.

- 일반 사용자가 만든 동아리는 `pending_approval`이며 global admin만 `active`로 승인할 수 있다
- 신규 신청의 개설 목적은 동아리 관리자 관리 화면과 global admin 승인 화면에서만 노출한다
- `active` 동아리만 기존 group type에 따른 일반 발견·가입·초대·작성 흐름을 제공한다
- 동아리 관리자만 active 동아리를 `inactive`로 종료하고 inactive 동아리를 다시 승인 대기로 전환할 수 있다
- 운영 종료는 동아리 관리자가 사유를 입력해 lifecycle·종료 사유·종료 시각을 함께 저장하며, 재활성화 요청은 이 정보를 보존한다
- 동아리 관리자는 자기 동아리 관리 화면에서 목적·사유를 제외한 시각 중심 누적 운영 이력을 열람한다
- global admin은 전용 policy query와 admin inventory scope를 통해 전체 User와 모든 Group metadata를 검색·필터·정렬·페이지네이션하여 조회한다
- global admin은 admin 상세 화면에서 모든 동아리의 목적·사유를 포함한 운영 metadata·이력·내부 콘텐츠를 조사하고 pending 동아리를 승인한다
- global admin은 `JjaekPolicy::AdminInventoryScope`와 `CommentPolicy::AdminInventoryScope`를 통해 admin User·Group 운영 상세 안에서 private visibility, private Group, inactive Group과 작성자 삭제 tombstone을 포함한 관련 콘텐츠를 read-only로 조사한다
- User admin 상세는 작성자 기준의, Group 운영 상세는 Group 문맥 기준의 필터 가능한 chronological content inventory를 제공한다
- 일반 User와 group admin은 admin User·Group 상세 URL에 접근할 수 없으며, 이 운영 조회 권한은 일반 홈 feed scope를 넓히지 않는다
- `JjaekPolicy#show?`는 global admin이 admin 상세에서 발견한 특정 private·Group Jjaek을 직접 조사할 수 있게 하지만 타인의 update/destroy 권한은 부여하지 않으며 Comment의 author mutation 원칙도 유지한다
- global admin은 다른 사용자의 Jjaek만 정의된 사유로 숨기고 별도 공개 복구 사유로 복구할 수 있다. 일반 scope는 숨겨진 Jjaek과 숨겨진 원문을 참조하는 ReJjaek을 제외한다. 작성자는 숨겨진 원문·숨김 주체·공개 사유만 확인하고 수정과 새 interaction 없이 자기 삭제만 할 수 있다. 기존 Group read 경계 안의 해당 group admin은 숨겨진 원문·숨김 주체·공개 사유를 확인한다. 대상 작성자인 global admin에게도 작성자 권한이 우선한다
- global admin과 Group admin은 모두 hide/restore 시 선택적 내부 메모를 입력한다. global admin은 platform/group-origin 메모를 모두 열람하고, 현재 Group admin은 자기 Group의 group-origin 메모만 관리자 변경과 관계없이 열람한다. 작성자·일반 회원, 권한을 잃은 이전 Group admin에게는 노출하지 않으며 platform-origin과 다른 Group 메모도 Group admin에게 노출하지 않는다
- Group moderation history UI도 현재 Group admin 권한에 귀속한다. 현재 관리자는 자기 Group Jjaek 상세에서 이전 관리자의 조치를 포함한 group-origin hide/restore 이력만 누적 열람하고, 작성자·일반 회원·이전 관리자·다른 Group 관리자·비회원은 열람하지 못한다. platform-origin 이력은 이 영역에 포함하지 않으며 global admin UI의 추가·확장은 별도 후속 범위다
- group-origin hide는 기존 Group read boundary 안의 일반 사용자에게 Group 목록의 hidden 카드와 단건 상세 접근을 허용하되 원문 body 대신 authority별 placeholder와 공개 사유만 제공한다. 좋아요 관련 요약·댓글 수·댓글 보기·글 보기와 기존 댓글 읽기 맥락은 유지하지만 새 interaction 권한은 추가하지 않으며, 내부 메모와 Group moderation history는 노출하지 않는다. Group boundary 밖 사용자와 platform-origin hide의 일반 사용자 조회 정책은 변경하지 않는다
- global admin은 운영상 필요한 경우 active/inactive 동아리의 관리자를 다른 active member에게 이전할 수 있다
- global admin의 `GroupPolicy::Scope`는 public/approval/private 및 pending/active/inactive 상태와 관계없이 모든 동아리를 포함한다
- global admin의 `show?`와 `read_jjaeks?`는 이 전체 Group을 운영 목적으로 조사하기 위한 권한이다
- global admin 권한은 일반 동아리 수정·종료·재활성화·작성·membership 관리 권한을 부여하지 않는다
- pending 동아리는 동아리 관리자만 기본 상태를 확인하며 내부 콘텐츠를 읽거나 작성할 수 없다
- inactive 동아리는 active membership이 기본 정보와 기존 내부 콘텐츠를 읽을 수 있다
- pending/inactive 동아리에서는 membership accept/approve 등 active participation을 만드는 동작을 허용하지 않는다
- 공개 동아리와 승인 동아리는 로그인 사용자가 발견하고 기본 정보를 조회할 수 있다
- 비공개 동아리는 동아리 관리자와 active member가 목록과 기본 상세를 조회할 수 있다
- 일반 사용자는 공개·승인·비공개 동아리를 생성할 수 있다
- 공개 동아리는 즉시 active membership을 만들고, 승인 동아리는 pending 가입 요청을 만든다
- 동아리 관리자만 자기 동아리의 pending membership을 active로 승인할 수 있다
- 비공개 동아리 관리자만 membership이 없는 사용자를 `invited` 상태로 초대할 수 있다
- 초대받은 당사자만 초대를 수락해 `active`로 바꾸거나 거절해 삭제할 수 있다
- `invited`는 비공개 동아리의 목록·상세·내부 Jjaek 접근 권한을 부여하지 않는다
- 사용자는 자신의 pending 요청을 취소하거나 자신의 active 일반 membership에서 탈퇴할 수 있다
- 현재 동아리 관리자 membership은 탈퇴·삭제할 수 없다
- 동아리 관리자와 global admin은 active/inactive 상태에서 다른 active member에게 권한을 이전할 수 있고 pending 상태에서는 이전할 수 없다
- 이전 관리자는 일반 active member로 남아 기존 자발적 탈퇴 경로를 사용할 수 있다
- 동아리 관리자만 이름과 소개를 수정할 수 있고 동아리 종류는 수정할 수 없다
- 동아리 관리자만 active 일반 member를 직접 내보낼 수 있으며 관리자 membership은 대상이 될 수 없다
- 승인 동아리 관리자만 pending 요청을 거절할 수 있다
- 비공개 동아리 관리자만 아직 수락되지 않은 `invited` membership을 취소할 수 있다
- 일반 member의 자발적 탈퇴와 관리자의 내보내기는 membership을 즉시 삭제한다
- 내보내기·거절·초대 취소는 ban이 아니므로 이후 가입 또는 재초대를 영구 차단하지 않는다
- `GroupMembershipEvent`는 membership lifecycle 사건을 Group 단위 append-only history로 보존하며 membership 삭제 여부와 독립적이다
- `GroupMembershipRemoval`은 내보내기 후 stale private Group 접근 안내를 위한 현재 표식이며 history나 ban으로 사용하지 않는다
- 활동 정지·해제 감사는 `ModerationAction`에만 기록하고 membership lifecycle history에 복제하지 않는다
- GroupMembership 대상 moderation row의 `membership_group_id`/`membership_user_id`는 현재 membership이나 FK가 아니라 target hard delete 후에도 남는 역사적 attribution이다
- `GroupMemberBan`은 현재 Group/User 이용 제한 상태이며 membership 생성·승인·초대·수락을 차단한다. ban/unban 사유와 이력은 같은 Group/User attribution을 가진 `ModerationAction`으로 보존한다

동아리에서는 같은 `Jjaek` 모델과 optional `group` / `book` association으로 `짹`과 `책짹`을 제공한다.
동아리 콘텐츠 읽기는 공개 동아리의 로그인 사용자 또는 승인/비공개 동아리의 active member에게 허용하고,
작성은 모든 동아리 종류에서 active member에게만 허용한다.
동아리 Jjaek은 active 작성자가 수정·삭제할 수 있고, 탈퇴하거나 내보내진 작성자도 자기 기존 글은 삭제할 수 있다.
동아리 관리자의 타인 글 moderation, 개인 Jjaek의 동아리 공유와 동아리 안에서의 ReJjaek 작성은 아직 구현하지 않는다.
active 공개 동아리의 Jjaek·책짹을 개인 영역으로 ReJjaek하는 기능은 제공한다.
홈 `FeedScope`에는 현재 사용자가 active member인 active/inactive 동아리의 Jjaek만 포함하며,
public 동아리나 follow 관계만으로 가입하지 않은 동아리 콘텐츠를 포함하지 않는다.

동아리 권한의 제품 정책은 `docs/specs/groups_mvp.md`를 기준으로 본다.
global admin은 일반 Group 목록과 admin inventory에서 모든 Group을 볼 수 있고 각 `show?`로 단건 운영 조사를 수행한다.
Jjaek·Comment는 admin User·Group 상세의 전용 inventory scope에서 visibility와 Group 접근 관계없이 발견할 수 있다.
`private_jjaek`의 나만 보기와 `book_friends` visibility도 일반 사용자 사이의 공개 범위이며 global admin의 운영 조사를 차단하지 않는다.
global admin은 특정 User 프로필에서는 `ProfileScope`를 통해 그 작성자의 모든 visibility Jjaek을 조사한다.
BookshelfEntry와 BookActivity도 profile 전용 scope를 통해 대상 사용자가 자기 프로필에서 보는 범위를 운영 목적으로 조사한다.
이 권한은 full Library 접근이나 Bookshelf·BookshelfEntry mutation 권한을 부여하지 않는다.
일반 Jjaek scope와 홈 `FeedScope`에는 global admin 우회를 추가하지 않는다.
운영 조사 권한은 Comment·Like·ReJjaek 등 일반 사용자 상호작용 권한으로 이어지지 않는다.
group admin은 운영 정지되지 않은
active/inactive 자기 Group의 타인 짹·책짹만 숨김·복구하고, 같은 Group authority의 hide는 현재 관리자가 복구할 수 있지만
global admin hide는 복구할 수 없다. global admin 작성 글도 대상에서 제외하며 direct request에서 거부한다.
hide origin은 `ModerationAction`에 조치 당시 `platform`/`group` authority로 보존하며 actor의 현재 역할로 추론하지 않는다.
상세 경계는 `docs/specs/moderation_mvp.md`를 따른다.

global admin은 다른 active User를 명시적인 `suspend?` action으로 정지하고 suspended User를 `restore?` action으로 복구할 수 있다.
자기 자신 정지와 withdrawn User의 정지·복구는 허용하지 않으며 일반 User와 group admin에게 이 권한을 부여하지 않는다.
정지·복구 권한은 타인을 대신한 일반 작성·수정·삭제·reaction 권한으로 이어지지 않는다.
이 User 권한의 UI 용어는 **계정 정지 / 계정 복구**이며 서비스 전체 로그인과 신규 mutation에 적용된다.
group admin은 일반 active 회원의 `GroupMembership`에만 적용되는 **동아리 활동 정지 / 동아리 활동 복구**와 현재 membership을 종료하고 재참여를 막는 **동아리 이용 제한 / 해제** 권한을 가진다. global admin은 모든 Group의 회원·제한·감사 이력을 조사하지만 Group membership moderation을 실행하지 않는다. service-wide 제재는 별도 User 계정 정지·복구를 사용한다.
global admin은 active Group을 **동아리 운영 정지 / 동아리 운영 복구**할 수 있다. 이는 회원 제한 및 group admin의 자발적 `inactive` 운영 종료와 별도이며, 읽기와 기존 데이터는 유지하고 새 콘텐츠·membership·회원 moderation·Group lifecycle mutation만 차단한다.
세 상태는 서로 자동 전파되지 않는다.

## 계정 탈퇴 권한과 보존

- 로그인한 일반 사용자는 전용 확인 화면에서 현재 비밀번호를 검증한 뒤 자기 계정만 탈퇴할 수 있다
- global admin과 active Group 관리자는 직접 탈퇴할 수 없다
- 탈퇴는 hard delete가 아니라 `withdrawn_at` 설정과 User 익명화이며 Jjaek·Comment 작성자 연결을 보존한다
- `closed_at`이 없는 최초 pending Group은 관리자 외 membership·콘텐츠·예상 밖 event가 없을 때만 신청을 정리한다
- `closed_at`이 있는 재운영 pending Group은 삭제하지 않고 inactive로 복귀시키며 `group_admin_id`와 withdrawn User, 콘텐츠, lifecycle history로 역사적 관리자 attribution을 보존한다
- 탈퇴 사용자의 일반 membership과 사회적 관계·개인 독서 운영 데이터는 제거한다
- withdrawn user를 대상으로 Follow, BookFriendship, Group 초대와 profile-context Jjaek을 만들 수 없다

관련 위치:

- `app/policies/group_policy.rb`
- `app/policies/group_membership_policy.rb`
- `app/policies/jjaek_policy.rb`
