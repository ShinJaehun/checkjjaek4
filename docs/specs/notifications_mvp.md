# Notifications MVP

## 목적

이 문서는 checkjjaek4에서 `Notification` 모델을 도입한 이후의
통합 알림 기준을 정리한다.

이 문서는 Notification의 canonical spec이다.
기존에는 `BookFriendship.pending` 기반 badge로 관계 요청 알림을 처리했지만,
Notification 모델 도입 후에는 `book_friendship_requested` action으로 통합한다.

---

## Notification의 역할

`Notification`은 사용자의 알림 inbox와 읽음 상태를 담당한다.

`Notification`은 각 도메인 객체의 source of truth를 대체하지 않는다.

- `BookFriendship`은 관계 요청과 수락/거절 상태의 source of truth다.
- `Jjaek`은 사용자가 남긴 글과 ReJjaek 문맥의 source of truth다.
- `Comment`는 Jjaek 댓글의 source of truth다.
- `GroupLifecycleEvent`, `GroupMembershipEvent`, `ModerationAction`은 각각의 lifecycle/moderation 사건을 기록하는 source of truth다.

즉, Notification은 "사용자가 확인해야 할 일"의 진입점이며,
도메인 상태 자체를 저장하거나 판정하는 모델이 아니다.
Lifecycle/moderation 알림의 `notifiable`은 가능한 한 User/Group 같은 현재 대상이 아니라
실제 사건을 기록한 audit/event row를 가리킨다. 새 generic event system이나
별도 notification framework는 만들지 않는다.

---

## 기존 관계 요청 알림과의 관계

기존 받은 책친구 요청 badge는
`BookFriendship.pending` 데이터를 직접 세는 초기 MVP였다.

`Notification` 모델 도입 후에는 받은 책친구 요청도
`Notification`으로 생성한다.

다만 두 상태는 분리한다.

- 알림을 읽음 처리해도 `BookFriendship`의 `pending` 상태는 바뀌지 않는다.
- 책친구 요청 수락/거절은 여전히 `/relationships`에서 처리한다.
- 관계 요청 처리 권한은 기존 `BookFriendshipPolicy`와 controller 흐름을 따른다.

---

## 관계 알림의 soft rejection 원칙

상대방이 불쾌하게 느낄 수 있는 관계 이벤트는
상대에게 `Notification`으로 직접 알리지 않는다.

아래 이벤트는 상대방에게 `Notification`을 생성하지 않는다.

- 책친구 요청 거절
- 내가 보낸 책친구 요청 취소
- 책친구 관계 해제
- 소식받기 해제

이 이벤트들은 action을 수행한 현재 사용자에게만 flash로 안내한다.

예:

- "책친구 요청을 거절했습니다."
- "책친구 신청을 취소했습니다."
- "책친구 관계를 해제했습니다."

책친구 요청 수락 알림은 후속 기능으로 검토할 수 있지만,
초기 `Notification` MVP 필수 범위에는 포함하지 않는다.

---

## 현재 구현된 social action 범위

현재 구현된 `Notification` action은 아래 네 가지다.

- `book_friendship_requested`
- `profile_jjaek_created`
- `comment_created`
- `requote_created`

좋아요, follow, feed성 활동은 이 범위에 포함하지 않는다.

책친구 요청 거절, 보낸 요청 취소, 책친구 관계 해제,
소식받기 해제도 알림 action으로 만들지 않는다.

---

## notifiable 매핑

각 action의 `notifiable`은 아래처럼 둔다.

- `book_friendship_requested` -> `BookFriendship`
- `profile_jjaek_created` -> `Jjaek`
- `comment_created` -> `Comment`
- `requote_created` -> `Jjaek`

`requote_created`의 notifiable은 새로 생성된 ReJjaek이다.
원문 Jjaek이 아니다.

아래 Platform moderation 정책의 8개 action은 각각 해당 조치의
`ModerationAction` row를 `notifiable`로 둔다.
GroupMembership 활동 정지·복구도 이번 조치의 `ModerationAction`을 사건 source로
사용한다. 아래 확정된 Group lifecycle Notification은 실제
`GroupLifecycleEvent` row를, 관리자 이전 Notification은 실제
`GroupMembershipEvent` row를 `notifiable`로 사용한다. 그 밖의 membership
lifecycle은 `GroupMembershipEvent`, 회원 이용 제한·해제는 `ModerationAction`을
사건 source 후보로만 두며 recipient 정책이 확정되기 전에는 생성하지 않는다.

---

## Platform moderation Notification 정책 `(확정·구현)`

| 사건 | recipient | 사용자에게 공개할 정보 |
| --- | --- | --- |
| User 계정 정지 | 대상 User | 정지 사실과 `public_reason` |
| User 계정 복구 | 대상 User | 복구 사실. 복구 사유를 표시한다면 해당 조치의 `public_reason`만 사용 |
| Group 운영 정지 | 조치 시점의 active GroupMembership User | Group 이름, 운영 정지 사실, `public_reason` |
| Group 운영 복구 | 조치 시점의 active GroupMembership User | Group 이름, 운영 복구 사실, 해당 restore 조치의 `public_reason` |
| Jjaek 숨김 | 작성자 | 숨김 사실과 `public_reason` |
| Jjaek 복구 | 작성자 | 복구 사실. 복구 사유를 표시한다면 해당 조치의 `public_reason`만 사용 |
| Comment 숨김 | 작성자 | 숨김 사실과 `public_reason` |
| Comment 복구 | 작성자 | 복구 사실. 복구 사유를 표시한다면 해당 조치의 `public_reason`만 사용 |

Group 운영 정지·복구의 recipient는 상태 변경 transaction 안에서 확정한
**조치 시점의 active membership 사용자 ID 집합**이다. Group admin도 active
membership을 통해 포함하며 중복 ID를 제거한다. 다음 사용자는 포함한다.

- membership은 active이나 `activity_suspended`인 사용자
- User 계정은 suspended이나 membership은 active인 사용자

pending, invited, 자발적 탈퇴·내보내기로 membership이 없어진 사용자,
`GroupMemberBan`으로 이용 제한되어 membership이 종료된 사용자는 제외한다.
모든 사건에서 actor와 recipient가 같으면 알림을 생성하지 않는다.

`internal_note`와 platform 내부 감사 상세는 어떤 Notification에도 노출하지 않는다.
Moderation 사유로 사용자에게 보여줄 수 있는 것은 해당 `ModerationAction`의
`public_reason`뿐이다. 미리 정의된 공개 사유 key는 기존 공개 label로 표시하고,
legacy 자유 텍스트는 별도 내부 메모와 혼동하지 않는다.

실제 처리자는 audit row와 `Notification.actor`에 보존한다. 다만 platform
moderation의 사용자용 메시지에는 global admin의 실명·avatar를 노출하지 않고
"운영팀"처럼 권한 주체를 표시한다. Lifecycle/moderation 알림 UI는 actor avatar를
필수 요소로 가정하지 않는다. 기존 댓글·다시짹 등 social 알림의 actor 이름·avatar
표시는 유지할 수 있다. 향후 system actor가 필요하면 별도 정책으로 정한다.

계정 정지 중에는 대상 User가 Notification inbox에 접근할 수 없다.
따라서 정지 알림은 서비스 내부 전달 기록이며, 올바른 비밀번호 확인 후
로그인 차단 화면에서 현재 공개 사유를 안내하는 기존 흐름을 대체하지 않는다.

---

## GroupMembership 활동 정지·복구 Notification `(확정·구현)`

`suspend_activity`와 `restore_activity`는 각각 대상 membership의 User 한 명에게
알린다. `notifiable`은 이번 조치에서 생성된 `ModerationAction`이며, actor와
recipient가 같으면 생성하지 않는다. 상태 변경과 audit row의 기존 원자성을 유지하고
Notification은 commit 후 기존 best-effort delivery로 생성한다.

사용자 메시지에는 Group 이름, 활동 정지·복구 사실과 해당 action의
`public_reason`만 표시한다. `internal_note`와 실제 group admin 이름·avatar는
노출하지 않고 항상 "동아리 운영진"으로 표시한다. 이 사건의
`moderation_authority`는 기존 모델대로 `nil`이며 별도 snapshot을 추가하지 않는다.
Group 이름과 목적지 확인에는 audit row의 `membership_group_id` attribution을
사용한다. 클릭 시점에 Group read policy를 다시 확인하여 접근 가능하면 Group
상세로, membership 종료·Group 삭제 등으로 접근할 수 없으면 안전한 Group 목록으로
연결한다. 알림 자체는 새 읽기 권한을 부여하지 않는다.

---

## Group lifecycle Notification 정책 `(확정·구현 전)`

아래 7개 사건의 recipient와 공개 범위는 확정한다. Notification은 기존
`GroupLifecycleEvent` 또는 관리자 이전의 `GroupMembershipEvent`를 전달하는
inbox record다. 두 관리자 이전 event를 새 generic transfer event로 합치거나
새 schema를 만들지 않는다. 실제 actor는 event row와 `Notification.actor`에
보존한다.

| event_type | notifiable | recipient | 사용자 메시지에 표시할 정보 |
| --- | --- | --- | --- |
| `opening_requested` | 해당 `GroupLifecycleEvent` | 현재 `global_admin`이고 `withdrawn_at`·`suspended_at`이 모두 없는 User, actor 제외 | Group 이름과 새 개설 신청 사실 |
| `opening_approved` | 해당 `GroupLifecycleEvent` | Group admin, actor 제외 | Group 이름과 개설 승인 사실 |
| `operations_closed` | 해당 `GroupLifecycleEvent` | 종료 사건 시점의 모든 active `GroupMembership` User, actor 제외 | Group 이름과 운영 종료 사실 |
| `reactivation_requested` | 해당 `GroupLifecycleEvent` | 현재 `global_admin`이고 `withdrawn_at`·`suspended_at`이 모두 없는 User, actor 제외 | Group 이름과 재운영 신청 사실 |
| `reactivation_approved` | 해당 `GroupLifecycleEvent` | 승인 사건 시점의 모든 active `GroupMembership` User, actor 제외 | Group 이름과 재운영 승인 사실 |
| `admin_role_revoked` | 해당 `GroupMembershipEvent` | 이전 Group admin, actor 제외 | Group 이름과 자신의 관리자 권한 해제 사실 |
| `admin_role_granted` | 해당 `GroupMembershipEvent` | 새 Group admin, actor 제외 | Group 이름과 자신의 관리자 권한 부여 사실 |

`opening_requested`는 일반 사용자의 개설 신청에서 생긴다. global admin이
자기 Group을 직접 만들면 `opening_approved`가 생성되지만 actor와 Group admin이
같으므로 self Notification은 없다. 개설·재운영 신청을 받는 global admin은 각
신청 사건 시점의 계정·권한 상태를 기준으로 선정한다. `reactivation_approved`에서는
Group admin도 active membership을 통해 포함한다. 운영 종료와 재운영 승인의
recipient ID는 중복 제거하고 pending·invited membership을 제외하며, 상태 변경
transaction 안에서 사건 시점에 snapshot한다.

`opening_requested.detail` / `application_purpose`는 admin 전용 신청 정보다.
Notification 본문에 복사하지 않고, 권한이 있는 global admin이 현재 admin 상세에서
확인한다. `operations_closed.detail` / `closure_reason`은 audit에 보존하지만
일반 active 회원 Notification에는 표시하지 않는다. 현재 일반 회원 Group 화면보다
정보 공개 범위를 넓히지 않는다. 나머지 사건에도 존재하지 않는 공개 사유를
추정하거나 다른 event의 detail을 가져와 표시하지 않는다. 관리자 이전 알림은
각 수신자의 권한 변화만 표현하며 두 event를 시각·순서로 묶어 상대 관리자 이름을
추정하지 않는다.

Lifecycle 알림의 사용자-facing 표시에는 실제 actor 이름·avatar를 기본적으로
노출하지 않는다. 기존 social 알림의 actor 표시나 moderation authority 표시를
기계적으로 재사용하지 않고 사건별로 표현한다.

- `opening_requested`: "새 동아리 개설 신청"처럼 사건 중심
- `opening_approved`, `reactivation_approved`: "운영팀" 중심
- `operations_closed`: "동아리 운영진" 중심
- `reactivation_requested`: "동아리 재운영 신청"처럼 사건 중심
- `admin_role_revoked`, `admin_role_granted`: "관리자 권한 변경"처럼 사건 중심

관리자 이전 event에는 authority snapshot이 없다. 표시 시점의 actor 역할이나
`global_admin` 현재 값을 사용해 과거 조치의 authority를 추정하지 않는다.
actor와 recipient가 같으면 관리자 이전에도 예외 없이 생성하지 않는다.
따라서 이전 관리자가 직접 실행한 정상 이전에서는 새 관리자에게만 grant 알림을
보내고, 별도 global admin이 실행한 recovery에서는 이전 관리자에게 revoke,
새 관리자에게 grant 알림을 보낸다. recovery actor 자신은 수신자일 때 제외한다.

신청·재운영 신청 알림은 클릭 시점의 admin 상세 접근 권한이 있으면
`admin_group_path`로, 권한 상실·대상 소멸 시 `groups_path` 등 안전한 화면으로
연결한다. 승인·운영 종료·재운영 승인과 관리자 이전 알림은 현재
`GroupPolicy#show?`가 허용하면 `group_path`, 아니면 `groups_path`로 연결한다.
이전 관리자가 권한 이전 직후 members 관리 권한을 잃을 수 있으므로
`group_members_path`를 관리자 이전의 공통 목적지로 사용하지 않는다.
Notification 자체는 read/admin 권한을 부여하지 않는다.

이 정책은 후속 구현 기준이며 현재 Group lifecycle Notification을 생성한다는
뜻은 아니다.

---

## Lifecycle/moderation delivery 경계

핵심 lifecycle/moderation 조치의 성공 조건은 **상태 변경과 audit/event row 생성**이다.
이 둘의 기존 원자성을 유지한다. Notification은 commit 이후의 파생 delivery다.
알림 생성 실패 때문에 이미 성공한 조치를 rollback하거나 사용자에게 핵심 조치가
실패한 것처럼 응답하지 않는다. 나중에 "현재 최신 audit row"를 재조회해 사건을
추측하지 않고, 실제 생성된 event/audit row를 알림 source로 전달한다.

Group 운영 정지·복구는 앞서 정의한 active recipient ID 집합을 상태 변경 transaction 안에서
확정하고, commit 후 중복 제거된 수신자에게 생성한다. 초기 소규모 MVP에서는
synchronous best-effort delivery가 가능하며 background job은 필수가 아니다.
규모·응답시간·재시도 요구가 생기면 background delivery를 후속 검토한다.

Group lifecycle Notification 구현도 실제 생성한 event row를 전달하며,
commit 후 recipient별 best-effort로 생성한다. rollback 시에는 생성하지 않고
전달 실패로 핵심 lifecycle action을 실패시키지 않는다. 별도 background job은
도입하지 않는다.

---

## 그 밖의 GroupMembership lifecycle·moderation recipient 후보 `(미확정·구현 대상 아님)`

아래는 현재 사건의 의미와 접근 경계를 바탕으로 검토할 후보일 뿐이다.
알림 생성 여부, recipient, 공개 범위, 목적지는 별도 승인 전까지 확정하지 않는다.

| 사건 | recipient 후보 / 검토 사항 |
| --- | --- |
| 최초 관리자 가입·일반 가입 | 일반 가입은 group admin에게 후보. 최초 관리자 본인의 `joined`는 self 알림 제외 |
| 가입 신청 | group admin: 심사 작업 |
| 가입 신청 취소 | 알림 없이 심사 목록 갱신만으로 충분한지 검토 |
| 가입 승인 | 신청자: 참여 권한 획득 |
| 가입 거절 | 신청자에게 결과를 알릴지 TBD; soft-rejection 원칙과 비교 |
| 초대 | 초대받은 사용자: 수락 작업 |
| 초대 수락 | group admin: 회원 참여 |
| 초대 거절 | group admin에게 알릴지 TBD; soft-rejection 원칙과 비교 |
| 초대 철회 | 초대받은 사용자: 기존 초대 무효화 |
| 자발적 탈퇴 | group admin: 회원 구성 변화 |
| 내보내기 | 대상 사용자: 접근 상실. 사유 필드를 새로 추정하지 않음 |
| 이용 제한·해제 | 대상 사용자: 재참여 제한 변화와 공개 사유. 해제는 membership 자동 복구가 아님 |

가입 거절·초대 거절과 그 밖의 soft-rejection 성격 사건의 알림 여부는 모두 TBD다.
기존 책친구 관계의 soft-rejection 정책을 Group 사건에 자동 적용하지 않는다.

---

## 제외 범위

이번 MVP에서 하지 않는다.

- 좋아요 알림
- follow 알림
- 일반 책짹 작성 알림
- 책 서재 추가 알림
- 책 상태/스티커 변경 알림
- `BookActivity`
- 실시간 ActionCable
- 이메일 알림
- 푸시 알림

---

## 읽음 처리

`Notification`은 `read_at`을 가진다.

- `read_at`이 `nil`이면 unread다.
- `read_at`이 있으면 read다.
- 알림은 읽었다고 삭제하지 않는다.

`/notifications` 목록에 들어가면 현재 사용자의 unread 알림에
`read_at`을 기록하여 읽음 처리한다.

읽은 알림도 알림 목록에는 계속 남는다.
읽은 알림은 읽지 않은 알림보다 시각적으로 약하게 표시한다.

navbar badge에는 읽지 않은 알림만 카운트한다.

MVP에서는 자동 만료, 자동 삭제, pruning, archive,
사용자 직접 삭제 기능을 제공하지 않는다.

관계 요청 알림의 `read_at`과 `BookFriendship.pending`은 별개다.
알림을 읽어도 관계 요청은 pending으로 남고,
사용자는 `/relationships`에서 수락하거나 거절해야 한다.

---

## 클릭 / 이동 경로

알림 항목 클릭 시 이동 경로는 아래처럼 둔다.

- `book_friendship_requested`
  - `/relationships#received-book-friend-requests`
- `profile_jjaek_created`
  - 생성된 Jjaek 상세
- `comment_created`
  - 댓글이 달린 Jjaek 상세
- `requote_created`
  - 생성된 ReJjaek 상세

알림 목록은 처리 화면이 아니라 진입점이다.
관계 요청 처리는 `/relationships`,
Jjaek / Comment / ReJjaek 확인은 관련 Jjaek 상세에서 한다.

Moderation 알림은 `ModerationAction`을 `notifiable`로 갖더라도
조치 row 자체가 아닌 수신자가 이해하고 접근할 수 있는 현재 화면으로 연결한다.

- Group 운영 정지·복구: 현재 접근 가능하면 `group_path`
- GroupMembership 활동 정지·복구: 현재 접근 가능하면 `group_path`, 아니면 `groups_path`
- Jjaek 숨김·복구: 현재 접근 가능하면 `jjaek_path`
- Comment 숨김·복구: 현재 접근 가능하면 부모 Jjaek의 댓글 문맥
- User 계정 정지·복구: 정지 중 inbox 접근이 불가능하므로 Notification 클릭이
  로그인 차단 안내를 대신하지 않음

대상이 hard delete되었거나 클릭 시점의 policy/visibility상 접근할 수 없으면
권한을 우회하지 않고 안전한 fallback으로 이동한다. 대상·관계가 이후 바뀌어도
알림의 존재만으로 비공개 콘텐츠 접근 권한을 부여하지 않는다.

---

## 생성 조건

기존 social 알림과 새 lifecycle/moderation 알림 모두 actor와 recipient가 같으면
Notification을 생성하지 않는다. 조치 실행자 본인에게 같은 사건을 inbox로
다시 전달하지 않는다. 향후 system actor는 별도 정책으로 다룬다.

기존 social self-action 예:

- 내가 내 프로필에 남긴 Jjaek은 알림을 만들지 않는다.
- 내가 내 Jjaek에 단 댓글은 알림을 만들지 않는다.
- 내가 내 글을 ReJjaek한 경우 알림을 만들지 않는다.

각 action별 생성 조건:

- `book_friendship_requested`
  - 책친구 요청 수신자에게만 생성한다.
- `profile_jjaek_created`
  - `target_user`가 있고, 작성자와 `target_user`가 다를 때 생성한다.
- `comment_created`
  - 댓글이 달린 Jjaek의 작성자에게 생성한다.
  - 댓글 작성자와 Jjaek 작성자가 같으면 생성하지 않는다.
- `requote_created`
  - 원문 Jjaek 작성자에게 생성한다.
  - ReJjaek 작성자와 원문 작성자가 같으면 생성하지 않는다.
  - 수신자가 볼 수 없는 private/book_friends ReJjaek은 알림으로 누설하지 않는다.

---

## 중복 방지

같은 이벤트에 대한 중복 알림은 만들지 않는다.

기본 기준:

- `recipient`
- `actor`
- `action`
- `notifiable`

위 조합을 기준으로 중복 생성을 막는다.
Group 운영 fan-out에서는 동일한 사용자 ID를 먼저 중복 제거한다.

동일 사용자가 같은 Jjaek에 여러 댓글을 남기는 경우에는
각 댓글이 별도 `Comment`이므로 별도 알림으로 볼 수 있다.

---

## 기존 관계 badge MVP와의 관계

초기 구현은 별도 `Notification` 모델 없이
`BookFriendship.pending`을 직접 세어 받은 책친구 요청 badge를 표시했다.

이 문서는 Notification 모델 도입 이후의 통합 기준이다.
받은 책친구 요청, profile-context Jjaek, 댓글, ReJjaek 알림과
Platform moderation 8개 사건과 GroupMembership 활동 정지·복구 2개 사건의
현재 구현을 함께 다룬다.

---

## 테스트 기준

### Model spec

- `Notification`은 `recipient`, `actor`, `action`, `notifiable`이 필요하다.
- `read_at`이 `nil`이면 unread로 판정한다.
- unread scope가 unread 알림만 반환한다.
- recent scope가 최신 알림부터 반환한다.

### Request spec

- 책친구 요청 생성 시 notification이 생성된다.
- profile-context Jjaek 생성 시 notification이 생성된다.
- comment 생성 시 notification이 생성된다.
- ReJjaek 생성 시 notification이 생성된다.
- self-action은 notification을 생성하지 않는다.
- navbar에 unread notification count가 표시된다.
- `/notifications`에서 현재 사용자의 알림 목록을 볼 수 있다.
- `/notifications` 목록 진입 시 unread 알림이 read 처리된다.
- `/notifications`에서 책친구 요청 알림을 read 처리해도 `BookFriendship`은 pending 상태로 남는다.
- 각 알림 링크가 올바른 목적지로 이동한다.

### Platform moderation 구현 검증 기준

- 8개 action이 각각 실제 `ModerationAction` row를 `notifiable`로 사용하고
  확정된 recipient에게만 생성된다.
- actor 본인에게 생성되지 않고, Group 운영 알림의 active 수신자를 사건 시점에
  확정·중복 제거하며 pending/invited/탈퇴·내보내기/이용 제한 사용자를 제외한다.
- activity-suspended membership과 계정 정지 User의 active membership도
  Group 운영 알림 recipient에 포함한다.
- 공개 사유만 보이고 `internal_note`·platform actor 신원은 사용자용 메시지와
  avatar에 노출되지 않는다. 기존 social 알림의 actor 표시는 유지된다.
- 알림 저장 실패가 핵심 상태·audit 성공을 rollback하거나 실패 응답으로
  바꾸지 않는다.
- 삭제·권한 변경으로 목적지에 접근할 수 없으면 안전한 fallback으로 이동하고,
  정지 계정의 기존 로그인 차단 사유 안내를 유지한다.
