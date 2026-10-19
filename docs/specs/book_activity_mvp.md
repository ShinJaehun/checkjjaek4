# BookActivity MVP

## 목적과 책임

`BookActivity`는 개인 서재에 책을 추가한 사건을 홈·프로필 피드에 표시하는 이벤트다.
`BookshelfEntry`와 `BookshelfEntrySticker`가 현재 독서 상태와 스티커의 source of truth이며,
본문 콘텐츠는 `Jjaek`이 담당한다. 개인 독서 관리와 책짹 작성은 별개 흐름이다.

## 생성과 삭제

- 검색 결과 또는 책 상세에서 개인 `BookshelfEntry`를 처음 생성할 때만 `added_to_shelf`를 기록한다.
- 공용 `Book` 생성 자체는 활동 생성 기준이 아니다.
- 이미 담긴 책의 재등록, 상태 선택·비움, 스티커 추가·제거, 책장 이동은 활동을 만들지 않는다.
- 서재 등록과 활동 기록은 같은 transaction에서 수행한다. 등록 실패 시 활동도 남지 않는다.
- 서재 항목을 제거하면 그 항목에 연결된 모든 BookActivity를 함께 삭제한다. 공용 Book과 책짹은 유지한다.
- 기존 상태·스티커 변경 action과 metadata는 과거 데이터 호환을 위해 유지하되 홈·프로필 피드에서 제외한다.
- 서재 항목에 연결되지 않은 과거 활동도 피드에 표시하지 않는다.

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
- global admin의 운영 조사용 ProfileScope 예외는 유지한다. 일반 홈·관계 scope의 권한은 확대하지 않는다.
- Jjaek과 BookActivity의 20개 단위 혼합 cursor 조회와 동일 시각 정렬은 `group_activity_feed.md`의 A12 Delta Specs를 따른다.
- 책 상세 목록에는 BookActivity를 합성하지 않는다.

## 카드 표현

기존 책 표지 partial을 사용한 표지 중심 카드로 표시하고 일반 짹 카드와 배경·테두리로 구분한다.
책 제목, 저자, 활동 작성자와 작성 시각을 유지한다. 제목 위의 반복 문구 “서재에 담은 책”은 출력하지 않는다.
생성·삭제·공개 정책은 바꾸지 않는다.

## 개인 영역과 향후 범위

BookshelfEntry와 BookActivity는 개인 영역으로 유지하며 `group_id`를 추가하지 않는다.
동아리에서 검색한 책을 개인 서재에 담아도 활동의 actor와 책장은 개인 소속이다.
책 검색 대상과 책짹 게시 대상은 구분한다. 동아리 게시 맥락은 책짹의 Group 권한으로 처리한다.
책 검색 단일 독립 페이지는 `docs/specs/book_search_mvp.md`를 따른다. 동아리 책장은 후속 검토 대상으로 두며 선행 모델을 추가하지 않는다.
Notification, 댓글·좋아요·다시짹, 추천·랭킹, 활동 편집 UI도 추가하지 않는다.

## 구현과 Acceptance Criteria

- 기존 `BookActivities::RecordBookshelfEntryChange`는 신규 서재 추가 기록만 담당한다.
- 상태·스티커 update는 활동 recorder를 호출하지 않는다.
- `BookshelfEntry#book_activities`의 dependent destroy가 항목 제거 시 활동을 정리한다.
- `BookActivityPolicy`의 단건 권한과 홈·프로필 scope는 추가 action, 연결된 항목, 관계와 현재 책장 공개 범위를 적용한다.
- 등록 성공·재등록·등록 실패와 상태·스티커 변경 시 활동 수를 검증한다.
- 과거 모든 변경 action과 연결 없는 추가 활동의 피드 제외를 검증한다.
- public/book_friends/private 책장, 책장 공개 범위 변경과 이동, 기존 관계 경계를 검증한다.
- 항목 제거 시 연결 활동만 삭제되고 다른 활동과 공용 Book은 유지되는지 검증한다.

책 상세 UI·자동 저장 기준은 `docs/specs/bookshelf_ui.md`,
책장 도메인은 `docs/specs/bookshelf_foundation.md`,
책 검색은 `docs/specs/book_search_mvp.md`를 함께 따른다.
