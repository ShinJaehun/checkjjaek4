# 사용자별 상호작용 정책 설정

## 범위

사용자는 `/account/settings`의 “관계 및 초대”에서 다음 세 설정을 직접 변경한다.
`/users/:id`는 사용자 프로필 surface로 유지하고, `/account/...`는 로그인한
사용자의 self-management surface로 확장한다. 이번 단계에는 settings만 포함한다.

| 설정 | 기본값 | OFF일 때 새로 차단하는 행동 |
| --- | --- | --- |
| `accepts_book_friend_requests` | 허용 | 나에게 보내는 새 책친구 신청 |
| `accepts_group_invitations` | 허용 | 나에게 보내는 새 비공개 동아리 초대 |
| `allows_new_followers` | 허용 | 나를 향한 새 소식받기 |

설정은 `User`의 boolean 필드이며 모두 `default: true`, `null: false`다.
설정 변경은 이후 새 관계 생성에만 적용한다. 이미 존재하는 Follow,
pending·accepted BookFriendship, invited GroupMembership은 자동 삭제하거나
상태를 바꾸지 않는다. 기존 관계의 해제, 요청 수락·거절·취소, 초대 수락·거절·철회도
계속 가능하다.

생성 제한의 최종 경계는 각각 `UserPolicy#follow?`,
`BookFriendshipPolicy#create?`, `GroupMembershipPolicy#invite?`에 둔다.
소식받기 해제는 생성 권한과 분리한다. 프로필에서는 새 관계 버튼만 숨기고
기존 관계·요청의 후속 action을 유지한다.

이 설정은 Notification 수신 설정이 아니다. Notification on/off, 이메일·푸시
설정과 초대 Notification은 후속 범위다. 이번 단계는 프로필 동아리 초대 버튼이나
기존 회원 관리 초대 UI 구조를 변경하지 않는다.
