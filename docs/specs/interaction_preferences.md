# 사용자별 상호작용 정책 설정

## 범위

사용자는 `/account/settings` 한 화면에서 자신의 이름을 편집하고,
“관계 및 초대”에서 다음 세 설정을 직접 변경하며, 계정 탈퇴 확인 화면으로 이동할 수 있다.
`/users/:id`는 사용자 프로필 surface로 유지하고, `/account/...`는 로그인한
사용자의 self-management surface로 사용한다. 별도 account 하위 화면은 만들지 않는다.

| 설정 | 기본값 | OFF일 때 새로 차단하는 행동 |
| --- | --- | --- |
| `accepts_book_friend_requests` | 허용 | 나에게 보내는 새 책친구 신청 |
| `accepts_group_invitations` | 허용 | 나에게 보내는 새 비공개 동아리 초대 |
| `allows_new_followers` | 허용 | 나를 향한 새 소식받기 |

설정은 `User`의 boolean 필드이며 모두 `default: true`, `null: false`다.
설정 변경은 이후 새 관계 생성에만 적용한다. 이미 존재하는 Follow,
pending·accepted BookFriendship, invited GroupMembership은 자동 삭제하거나
상태를 바꾸지 않는다. 기존 관계의 해제, 요청 수락·거절·취소, 초대 수락·거절·취소도
계속 가능하다.

생성 제한의 최종 경계는 각각 `UserPolicy#follow?`,
`BookFriendshipPolicy#create?`, `GroupMembershipPolicy#invite?`에 둔다.
소식받기 해제는 생성 권한과 분리한다. 프로필에서는 새 관계 버튼만 숨기고
기존 관계·요청의 후속 action을 유지한다.

이 설정은 Notification 수신 설정이 아니다. 초대 workflow Notification은
`docs/specs/notifications_mvp.md`를 따르며, 설정은 새 초대 생성 여부만 제어한다.
Notification on/off와 이메일·푸시 설정은 이번 범위가 아니다.
비공개 동아리의 새 초대와 기존 pending 초대 취소는 대상 사용자 프로필에서 가능하다.
회원 관리 화면에서도 이미 보낸 초대를 취소할 수 있다.
