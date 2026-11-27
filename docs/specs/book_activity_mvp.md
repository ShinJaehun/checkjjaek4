# BookActivity MVP

## 목적과 책임

`BookActivity`는 개인 서재에 책을 추가하거나 독서 기록을 변경한 사건을 기록한다.
홈·프로필 피드는 추가 사건만 표시하고, 책 상세의 `책친구의 독서 활동`은 허용된 변경 사건도 표시한다.
`UserBook`과 `UserBookSticker`가 현재 독서 상태와 스티커를 보관하며,
본문 콘텐츠는 `Jjaek`이 담당한다. 개인 독서 관리와 책짹 작성은 별개 흐름이다.

## 생성과 삭제

- 검색 결과 또는 책 상세에서 개인 `BookshelfEntry` 배치를 새로 생성할 때 `added_to_shelf`를 한 건 기록한다. 제거 후 다시 담는 경우에도 새 배치의 추가 활동 한 건을 기록한다.
- 공용 `Book` 생성 자체는 활동 생성 기준이 아니다.
- 현재 배치가 있는 책의 중복 등록과 책장 이동은 활동을 만들지 않는다.
- 기존 등록 요청에 상태·스티커가 명시된 경우 첫 등록과 현재 배치의 중복 요청에서 기존 저장 동작을 유지한다. 제거한 책을 다시 담을 때는 저장된 `UserBook`을 그대로 연결한다.
- 상태 선택·비움과 스티커 추가·제거는 한 번의 저장에서 실제 변경이 있을 때 `bookshelf_entry_updated` 한 건으로 기록한다.
- 상태와 스티커를 함께 바꿔도 한 건만 기록하며, 변경이 없으면 기록하지 않는다.
- `UserBook` 상태·스티커 저장과 활동 기록은 같은 잠금·transaction에서 수행하고 실패하면 모두 롤백한다.
- 서재 등록과 활동 기록은 같은 transaction에서 수행한다. 등록 실패 시 활동도 남지 않는다.
- 서재 항목을 제거하면 기존 활동의 배치 연결을 해제하고 행과 metadata를 보존한다. 다시 담을 때도 이전 배치의 활동은 연결을 해제한 상태로 유지한다. 공용 Book과 책짹은 유지한다.
- 기존 상태·스티커 변경 action과 metadata는 유지하되 홈·프로필 피드에서 제외한다.
- 서재 항목에 연결되지 않은 과거 활동은 홈·프로필 피드와 책 상세의 책친구 활동에 표시하지 않는다.

## 조회 정책

관계 기반 허용 범위를 유지한 채 **현재 책장의 visibility**로 추가 제한한다.
활동 자체에 별도 visibility나 공개 범위 snapshot을 추가하지 않는다.

| 위치 | 허용 관계 | 현재 책장 조건 |
| --- | --- | --- |
| 홈 | 본인 | 모든 책장 |
| 홈 | 소식받는 accepted 책친구 | public 또는 book_friends |
| 프로필 | 본인 | 모든 책장 |
| 프로필 | accepted 책친구 | public 또는 book_friends |

- follow-only와 stranger에게는 public 책장의 활동도 표시하지 않는다.
- 책장을 private으로 변경하거나 항목을 private 책장으로 이동하면 과거 추가 활동도 다른 사용자에게 표시하지 않는다.
- 현재 관계와 현재 책장 공개 범위를 조회 시 policy/scope에서 함께 확인한다.
- `BookActivityPolicy::ProfileScope`에는 global admin 전체 조회 예외가 없다. 관리자가 타인 프로필을 보더라도 private 책장의 활동은 표시하지 않으며, 일반 홈·관계 scope의 권한도 확대하지 않는다.
- Jjaek과 BookActivity의 20개 단위 혼합 cursor 조회와 동일 시각 정렬은 `group_activity_feed.md`의 A12 Delta Specs를 따른다.
- 책 상세의 기존 책짹 목록에는 BookActivity를 합성하지 않는다.
- `책친구의 독서 활동`에는 accepted 책친구의 해당 책 BookActivity를 현재 public/book_friends 책장에 연결된 항목으로 제한해 표시한다.
  소식받기 여부는 확인하지 않으며 본인 활동과 비공개 책장의 과거 활동은 제외한다.
  관계 해제나 책장 비공개 변경은 조회 시 즉시 반영한다.
- `created_at` 내림차순, 동률이면 `id` 내림차순으로 최근 3건을 표시한다. 책친구가 작성한 읽을 수 있는
  책짹은 `이 책의 책짹`에 표시한다.

## 카드 표현

홈·프로필 카드는 아바타·활동 문장·날짜 아래에 작은 책 표지·제목·저자를 표시한다.
책 상세의 `책친구의 독서 활동` 카드는 아바타·활동 문장·날짜를 표시한다.
상태·스티커 변경은 활동 당시 metadata의 변경분을 공통 배지로 문장 안에 표시하고, 추가 활동에는 현재 독서 기록을 덧붙이지 않는다.
책짹 카드의 표현은 [통합 짹 명세](unified_jjaeks.md)를 따른다.

## 개인 영역과 향후 범위

BookshelfEntry와 BookActivity는 개인 영역으로 유지하며 `group_id`를 추가하지 않는다.
동아리에서 검색한 책을 개인 서재에 담아도 활동의 actor와 책장은 개인 소속이다.
책 검색 대상과 책짹 게시 대상은 구분한다. 동아리 게시 맥락은 책짹의 Group 권한으로 처리한다.
책 검색 단일 독립 페이지는 `docs/specs/book_search_mvp.md`를 따른다. 동아리 책장은 후속 검토 대상으로 두며 선행 모델을 추가하지 않는다.
BookActivity 자체에는 Notification, 댓글·좋아요·다시짹, 추천·랭킹, 활동 편집 UI를 추가하지 않는다.

## 구현과 Acceptance Criteria

- `BookActivities::RecordBookshelfEntryChange`는 신규 추가와 상태·스티커 통합 변경을 기록한다.
- 상태·스티커 update는 이전 값과 저장된 값을 비교해 저장 1회당 최대 한 건만 기록한다.
- `BookActivity.bookshelf_entry_id`의 FK에 `ON DELETE SET NULL`을 적용해 배치가 제거되어도 활동을 보존한다.
- `BookActivityPolicy`의 단건 권한과 홈·프로필 scope는 추가 action, 연결된 항목, 관계와 현재 책장 공개 범위를 적용한다.
- 책 상세 전용 `BookFriendScope`는 연결된 모든 변경 action을 accepted 책친구와 현재 공개 가능한 책장으로 제한한다.
- 등록 성공·재등록·등록 실패, 상태·스티커 동시 변경, 무변경, 실패 롤백 시 활동 수를 검증한다.
- 과거 모든 변경 action과 연결 없는 추가 활동의 피드 제외를 검증한다.
- public/book_friends/private 책장, 책장 공개 범위 변경과 이동, 기존 관계 경계를 검증한다.
- 항목 제거 후 기존 활동과 metadata를 보존하고, 다시 담아도 이전 활동은 노출되지 않으며 새 배치의 추가 활동만 기존 권한에 따라 노출되는지 검증한다.
- `책친구의 독서 활동`의 관계·책장 공개 범위·최근 3건 정렬과 책짹 목록의 가시성과 중복 없는 표시를 검증한다.

책 상세 UI·통합 저장 기준은 `docs/specs/bookshelf_ui.md`,
책장 도메인은 `docs/specs/bookshelf_foundation.md`,
책 검색은 `docs/specs/book_search_mvp.md`를 함께 따른다.
