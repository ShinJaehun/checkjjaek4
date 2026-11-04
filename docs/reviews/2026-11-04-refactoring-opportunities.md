# 책짹 리팩토링 후보 심층 감사

작성일: 2026-11-04. 대상: checkjjaek4 현재 작업 트리.
이번 변경은 이 보고서뿐이다. 기존 콘텐츠 무결성 변경과 테스트는 수정하지 않았다.
RSpec·브라우저·성능 테스트 및 commit·merge·push는 실행하지 않았다.
아래 예시는 설계 설명이며 적용된 코드가 아니다.

## 1. 종합 평가와 조사 방법

현재 구조는 전면 재설계할 상태가 아니다. Pundit 단건/목록 경계, Model의 정합성 규칙,
복잡한 목록의 Query Object, 감사 이력을 동반하는 moderation Service, 공통 책 표지와 콘텐츠
partial이 이미 분리되어 있다. 개선 효과가 큰 곳은 **동일 화면을 여러 요청 경로에서 준비하는 중복**,
**화면 Helper에 포함된 경로 검증**, **Controller에 남은 상태 변경·이력·알림의 결합**이다.

`AGENTS.md`와 앞서 읽은 `spec-driven-rails-development/SKILL.md`를 적용했다.
사용자가 이번 분석을 명시적으로 승인했으므로 저장소 탐색과 문서 작성을 진행했다.
`current_system.md`의 책 상세·서재·동아리·알림·데이터 책임·복귀 경로, authorization architecture,
관련 `library_screen.md`, `bookshelf_ui.md`, `bookshelf_foundation.md`, `groups_mvp.md`와 기존
콘텐츠 감사에서 확인한 추천짹/다시짹 명세를 필요한 부분만 대조했다. archive/legacy는 읽지 않았다.

### 선별 범위

- `app/controllers`의 Ruby 62개 파일 전체를 대상으로 선언 메서드 396개, 크기와 분기 키워드를
  기계적으로 조사했다. Concern 포함 수치다. 모든 파일을 동일한 깊이로 본문 검토한 것은 아니다.
- Helper 18개, View 파일 214개를 목록·크기·조회/가공 표현·render 참조로 선별했다.
  Model/Query/Service는 후보와 연결된 구현을 비교했다.
- 분기 키워드 수는 Ruby AST의 순환복잡도가 아니다. 문자열·주석 등 오차가 있는 선별 지표이며,
  최종 판단은 아래 실제 메서드와 호출 관계를 근거로 했다.
- 실행 시간·SQL 수·메모리 개선량은 측정하지 않았다. 효과는 책임 경계와 변경 지점 감소 관점의 예상이다.

| 선별된 파일 | 행 수 / 메서드 수 | 실제 판단 |
| --- | ---: | --- |
| `controllers/jjaeks_controller.rb` | 467 / 39 | 생성 문맥과 실패 화면이 복잡하지만 진행 중 변경과 겹쳐 후순위 |
| `controllers/bookshelf_entries_controller.rb` | 296 / 29 | 등록·독서 기록·이동이 함께 있음. 업무 단위로 구분할 가치 |
| `controllers/group_memberships_controller.rb` | 251 / 22 | 액션별 원자적 업무 절차가 Controller에 반복됨 |
| `controllers/groups_controller.rb` | 235 / 17 | 활동 피드와 카드 목록 준비를 분리할 여지 |
| `controllers/comments_controller.rb` | 234 / 18 | HTML 실패 상세 준비 중복. 모든 Turbo 분기를 통합할 이유는 없음 |
| `controllers/application_controller.rb` | 225 / 21 | 책 상세 전용 준비가 모든 Controller의 상속 표면에 있음 |
| `controllers/searches_controller.rb` | 161 / 6 | 서로 다른 결과 유형을 조율하는 책임은 타당. 단순 분기 수로 Service 추출하지 않음 |
| `controllers/bookshelves_controller.rb` | 139 / 14 | Library 정상 조회와 실패 렌더링 준비가 중복됨 |
| `controllers/users/libraries_controller.rb` | 133 / 12 | 위 중복의 다른 쪽. 이 작업의 최우선 대상 |
| `helpers/jjaeks_helper.rb` | 440행 | 링크 표현·권한을 동반한 URL 검증·카드 요약 조회가 공존 |
| `helpers/users_helper.rb` | 214행 | 상당 부분은 명시적 색상 표. 길이만으로 복잡하다고 보지 않음 |
| `views/users/_bookshelf_section.html.erb` | 202행 | 탭·정렬·목록·관리 modal의 입력 계약과 명명 정리 필요 |

경로는 표에서 `app/`을 생략했다. 아래 행 번호는 감사 당시 작업 트리 기준이다.

## 2. 우선순위

P1/P2/P3는 이번 **리팩토링 효과·비용** 분류이며 보안 결함의 심각도와 다르다.

| ID | 우선순위 | 후보 | 예상 효과 | 주요 위험 | 독립 작업 |
| --- | --- | --- | --- | --- | --- |
| R1 | P1 | Library 정상/실패 화면 준비 공통화 | 실제로 벌어진 화면 계약 차이 제거 | 실패 객체·책장 권한·정렬 기본값 | 가능 |
| R2 | P1 | 복귀 URL 검증과 링크 표현 분리 | 보안 경계를 한곳에서 읽고 검증 | allowlist·현재 권한·중첩 origin | 가능, 초기에는 호환 wrapper 유지 |
| R3 | P1 | ApplicationController의 책 상세 Context 분리 | 영향 범위·화면 의존성 명시 | 실패 화면의 변수와 preload 누락 | 가능, 첫 단계는 기계적 이동 |
| R4 | P1 | Membership 상태 전이 업무 절차 분리 | 상태·이력·알림의 원자성 검토 용이 | lock 재인가·stale action·commit 시점 | 승인 동작부터 단계별 |
| R5 | P2 | Library partial 입력 계약과 UI 경계 정리 | 오해되는 옵션·과거 화면 명명 축소 | 모바일 reorder/transfer DOM 계약 | R1과 별개 가능 |
| R6 | P2 | 서재 등록/독서 기록 저장 책임 정리 | 요청 처리와 저장 규칙 구분 | Book identity retry·활동 중복·rollback | update부터 가능 |
| R7 | P2 | Groups#index 조회 준비 구분 | 피드와 카드 조회를 독립 이해 | 과거 회원 카드·목록 순서·count | 가능 |
| R8 | P2 | Jjaek 생성 action 내부 단계 정리 | 문맥 확인·저장·응답 흐름 명료화 | A/B/C·추천·group lock·실패 입력 | 무결성 작업 검증 이후 |
| R9 | P2 | 댓글 HTML 실패 상세 준비 통일 | create/update/rate-limit 표시 차이 방지 | 수정 중 댓글 객체·hidden 이력 | 작은 단위로 가능 |
| R10 | P3 | 미사용 후보/과거 옵션 확인 후 제거 | 탐색 혼선 감소 | implicit/dynamic render 오판 | 개별 확인 후 가능 |
| R11 | P3 | 페이지 번호 계산의 표현 공통화 | 동일 계산 유지 지점 감소 | Turbo/복귀 query·페이지 객체 차이 | 필요할 때만 |
| R12 | P3 | moderation 폼/Service 대규모 통합 | 일부 중복 감소에 그침 | 권한 차이 은폐·설정 인자 증가 | 지금은 하지 않음 |

## 3. 상위 5개 작업의 구체적 범위

### R1. Library 조회와 실패 렌더링에 같은 화면 준비 계약 적용

**근거**

- `app/controllers/users/libraries_controller.rb:22` `prepare_library_bookshelf`, 70행
  `library_bookshelf_sort`, 76행 `selected_library_bookshelf`, 83행 `bookshelf_order_controls`.
- `app/controllers/bookshelves_controller.rb:91` `prepare_library_after_failure`, 114행
  `library_bookshelf_sort`, 118행 선택 메서드, 133행 순서 버튼 계산.
- `app/views/users/libraries/show.html.erb:12`는 `@library_bookshelf_count`, `@library_book_count`를
  항상 소비하지만 실패 준비에는 해당 집계가 없다. 정상 준비는 self/other 기본 정렬을 나누고,
  실패 준비는 항상 recent로 fallback한다. 조회 Scope 선택도 LibraryScope와 기본 Scope로 갈라져 있다.

**현재 → 제안 책임**

현재 두 Controller가 같은 화면의 권한 결과·조회·선택·관리 폼 상태를 각각 만든다.
`LibraryContext` Concern 하나가 공통 조회/화면 변수를 준비하고, Controller는 요청 인가와
실패한 `Bookshelf` 객체·modal 모드·선택 ID를 제공하도록 한다. 이미 `ProfileContext`,
`GroupShowContext`를 사용하는 저장소 관례와 일치한다. 독립 transaction이 없으므로 Service는 부적절하다.
Library는 화면 개념이므로 새 ActiveRecord Model도 만들지 않는다.

예시 계약:

```ruby
# 이름/인자는 제안이다. 실패한 객체를 새 객체로 덮어쓰지 않는다.
prepare_library_context(
  user: @user,
  selected_bookshelf_id: params[:bookshelf_id],
  new_bookshelf: @bookshelf,
  managed_bookshelf: nil
)
```

**범위**: 위 Controller 2개, 새 `app/controllers/concerns/library_context.rb`, 관련 request spec.
partial/UI 재분할과 transfer 조회는 첫 작업에서 제외한다. 순서 버튼/선택 fallback은 같은 Concern의
작은 private 메서드로 충분하다. Query Object와 presenter를 동시에 추가하지 않는다.

**위험/검증**: create 실패의 제출값과 errors, update 실패의 managed 객체, owner/친구/private 경계,
선택 책장, 정렬, 요약 수량을 함께 보존한다. 기존 `spec/requests/bookshelves_spec.rb`와
`users`/Library 요청 spec을 유지하며 실패 경로의 요약·정렬을 특성화한다.

**명세 주의**: `library_screen.md:167`의 recent 기본값 설명과
`bookshelf_ui.md:622` 및 `bookshelf_foundation.md:135`, 현재 architecture의 self=manual 설명이
충돌한다. 구현상 정상/실패 차이는 확실하나, 순수 추출 commit에서 이를 조용히 바꾸지 않는다.
공통화와 기존 canonical 설명 정렬/오류 동작 교정을 구분해서 리뷰해야 한다.

**효과/단위**: 화면 변수 추가 시 두 번째 실패 경로를 빠뜨리는 구조를 없앤다. 독립적인 P1 작업이다.

### R2. 복귀 URL 해석·인가를 표현 Helper에서 분리

**근거**: `app/helpers/jjaeks_helper.rb:107` `validated_jjaek_return_path`, 263행
`jjaek_return_destination`, 333행 `valid_tag_search_return_query?`는 URI 파싱, Rails route 인식,
DB 조회, Pundit, query allowlist, 중첩 search_origin을 처리한다.
`BooksController`, `BookshelfEntriesController`, `ApplicationController`가 `view_context`를 통해
이를 호출하며 `BookSearchesHelper`의 origin 계산과 여러 카드 링크도 의존한다.
`SearchesController#prepare_tag_scope!`와 태그 문맥 검증이 유사하지만 오류 계약은 다르다.

**현재 → 제안 책임**

Helper가 요청의 신뢰 경계와 링크 표현을 모두 맡는다. controller Concern `ContentReturnNavigation`에
검증 메서드군을 옮기고 검증 진입점을 `helper_method`로 노출하는 최소 변경을 우선한다.
Helper에는 경로를 이용한 링크·기본 위치·표시만 남긴다. policy/scope가 인가의 최종 기준인 점은 유지한다.
비즈니스 transaction이 아니므로 `ReturnPathService`는 만들지 않는다. 범용 URL resolver도 필요 없다.

```ruby
module ContentReturnNavigation
  extend ActiveSupport::Concern

  included do
    helper_method :validated_jjaek_return_path
  end

  private
  # 기존 URI/route/query/현재 권한 검사 전체를 함께 이동한다.
  # 메서드명과 nil fallback 계약은 첫 단계에서 유지한다.
end
```

**범위**: 새 Concern, `ApplicationController` include, `JjaeksHelper`, 현재
`view_context.validated_jjaek_return_path` 호출부. 기존 helper 호출 이름을 유지해 전 템플릿을
한꺼번에 바꾸지 않는다. `GroupContentReturnContext`는 moderation 복귀 문맥이라는 별도 책임을 유지한다.

**위험/검증**: 외부 URL, `//`, 제어문자, 중첩 query, GET allowlist, slug/handle, 사라진 레코드,
권한 상실, 관리 화면 필터, 검색 origin 재귀 제한. `spec/requests/jjaek_navigation_spec.rb`,
`book_navigation_spec.rb`, `spec/helpers/jjaeks_helper_spec.rb`의 검증을 보존한다.
request 내부 memoization은 별도 측정 후 고려하며 사용자 간 캐시는 금지한다.

**효과/단위**: 요청 인가를 위해 View를 생성하는 역방향 의존을 줄이고 보안 검토 지점을 명확히 한다.
독립 작업 가능. 태그 검증 통합은 예외/redirect 차이를 확인한 다음 후속 단계로 제한한다.

### R3. ApplicationController에서 책 상세 전용 준비를 명시적 Concern으로 이동

**근거**: `app/controllers/application_controller.rb:78` `prepare_book_show_read_context`,
102행 `prepare_book_show_form_context`, 118행 `prepare_book_friend_activities`.
호출자는 `BooksController#show`, `JjaeksController`의 책 게시 실패 2경로,
`BookshelfEntriesController#prepare_book_show_failure`다. `@book`, `@group`, `@bookshelf_entry`,
`@jjaek`, `@quoted_jjaek`의 선행 준비가 필요하다.

**현재 → 제안 책임**: 전역 Controller가 특정 화면을 구성 → `BookShowContext` Concern을 세
Controller에 명시적으로 include. 메서드와 변수 계약을 그대로 옮기고 전제 조건을 짧게 문서화한다.
Model에 화면 변수/route를 넣거나 `BookShowService`로 옮기지 않는다.

**범위**: 위 4개 Controller와 새 Concern. 첫 단계는 세 메서드의 이동만 수행한다.
`prepare_current_reading_states_for`, 추천 책 preload, 좋아요/댓글/다시짹 집계는 다수 화면에서
사용하므로 첫 단계에서 섞지 않는다. 후속 필요 시 `JjaekCardContext`로 응집시키되 조회 SQL은 유지한다.

**위험/검증**: `feed_only`, BookScope/GroupContentScope 분기, HTML 실패의 본문/독서 기록,
추천 책 및 인용 원문 preload, pagination redirect 포맷. `feed_pagination_spec.rb`,
`bookshelf_entries_spec.rb`, `jjaek_reading_state_spec.rb`, `recommendation_jjaeks_spec.rb`를 보존한다.

**효과/단위**: 책 화면 변경의 실제 의존 Controller를 드러내고 전역 상속 표면을 줄인다.
SQL 개선 주장은 없다. 무결성 변경 검증 후 기계적 이동으로 독립 수행할 수 있다.

### R4. Membership의 승인 업무 절차부터 독립 Service로 분리

**근거**: `app/controllers/group_memberships_controller.rb:34` update, 71행 accept,
87행 decline, 103행 reject, 118행 revoke, 134행 remove, 152행 destroy.
각 경로가 group lock → membership 재조회 → 재인가 → 상태 변경/삭제 → event → 알림 예약을 수행한다.
remove에는 `GroupMembershipRemoval` 저장도 있다. 공통화 없이 확장하면 이 순서와 수신자 선택을
액션마다 다시 검토해야 한다.

**현재 → 제안 책임**

- Model: `GroupMembership#status_transition_must_be_valid`, 관리자 탈퇴 방지, 관계 정합성을 유지.
- Service: 명시적 업무 하나의 lock·재조회·현재 권한 확인·변경·event·알림 예약을 소유.
- Controller: 최초 요청 authorize, ID/인가된 Group 전달, stale/validation/권한 실패의 HTTP 응답.

기존 `GroupMemberships::SuspendActivity`, `Jjaeks::Hide`처럼 업무 절차가 이미 Service인 관례에
맞춘다. 모든 전이를 `Transition.call(action:)`으로 합치거나 아홉 개 빈 wrapper를 일괄 생성하지 않는다.

```ruby
# 첫 번째 bounded 작업의 호출 예시
# Service 안에서도 group lock 이후 현재 membership과 권한을 다시 확인한다.
GroupMemberships::Approve.new(group: @group, membership_id: params[:id], actor: current_user).call!
redirect_to group_members_path(@group), notice: t("group_memberships.notices.approved"), status: :see_other
```

**범위**: 우선 update + 새 `GroupMemberships::Approve` + 해당 Service spec. 나머지 액션은 그대로 둔다.
승인/초대 수락이 모두 active!라고 같은 method로 합치지 않는다. 이력 종류·수신자가 다르다.
삭제 행에서도 event의 user/actor snapshot과 알림 인자가 보존되어야 한다.

**위험/검증**: stale 액션의 기존 redirect와 문구, lock 안 재조회·재인가, event 실패 시 rollback,
`Notifications::GroupMembershipNotifier.schedule`의 after-all-transactions-commit,
자기 알림 억제. `group_memberships_spec.rb`, `group_membership_notifications_spec.rb`,
`spec/models/group_membership_event_spec.rb`, notifier spec을 보존한다.

**효과/단위**: HTTP와 무관하게 업무 원자성을 직접 검증할 수 있다. 가장 위험한 후보이므로 R1~R3보다
늦게, 승인 하나씩 진행한다. 단지 Controller 행 수를 줄이는 목적이면 진행하지 않는다.

### R5. 서재 partial의 계약을 실제 현재 화면에 맞춰 축소

**근거**: `app/views/users/_bookshelf_section.html.erb:2`의 다수 local/default,
8행 `show_move_control`로 계산하는 reorder 상태, 25행 모바일 선택, 36행 desktop 탭,
86행 선택 책장, 148행 카드 종류 분기, 190행 관리 modal.
직접 호출부는 `users/libraries/show.html.erb:38`이며 현재 detail을 전달한다.
프로필은 `_profile_public_books`로 분리되어 있는데 partial 이름/옵션은 과거 profile 범용 계약을 남긴다.
`_profile_bookshelf_entry`와 `_compact_bookshelf_entry`의 모바일 순서 버튼도 유사하다.

**현재 → 제안 책임**: 전체 화면 shell 하나가 여러 UI 역할과 옵션 해석을 처리 → Library shell은
선택 책장/목록/관리 modal 배치를 소유하고, 모바일 select+desktop tabs를 `_bookshelf_navigation`이라는
응집된 한 partial로 분리한다. 작은 버튼·라벨까지 나누지 않는다.
`show_move_control`은 실제 역할인 `reorder_enabled`로 명확히 하고 사용되지 않는 card local은
호출부 확인 후 제거한다. 색상/상태 포맷은 기존 Helper에 유지한다.

```erb
<%= render "users/libraries/bookshelf_navigation",
           user: user, bookshelves: bookshelves, selected_bookshelf: selected_bookshelf,
           counts: bookshelf_entry_counts, sort: bookshelf_sort, can_create: can_create %>
```

**범위**: section, Library show 호출부, 새 navigation partial. 필요하면 경로를
`users/libraries/_bookshelf_section`으로 옮긴다. 카드 내부/transfer 구조 통합은 별도 작업이다.
공유를 위한 presenter 객체는 추가하지 않는다. conditional div의 들여쓰기도 함께 읽기 쉽게 정리한다.

**위험/검증**: `bookshelf-management-modal` ancestor, horizontal-scroll 선택 target,
`bookshelf-entries-sort`의 list/controls/actionBar 범위, 모바일 fixed bar, 폼 중첩.
`bookshelf_mobile_reorder_spec.rb`, `bookshelf_card_layout_spec.rb`, transfer system spec의 기존
동작을 보존해야 한다. 테스트 실행은 구현 후 사용자가 담당한다.

**효과/단위**: 한 화면 이해에 필요한 local 수와 잘못된 이름을 줄인다. R1과 독립적이나 R1 후에 하면
화면 입력 계약을 안정시키기 쉽다. desktop/mobile을 서로 다른 데이터 준비 경로로 나누지 않는다.

## 4. 추가 Controller / Model / Query 후보

### R6 — BookshelfEntriesController의 저장 절차 (P2)

- **근거/문제**: `create:10`, `update:62`, `assign_stickers:258`, Book identity retry 메서드군.
  import identity·책 저장·서재 항목 변경·BookActivity·HTML/Turbo/JSON 응답이 한 파일에 모여 있다.
- **제안/전후**: update의 항목 lock/이전 상태 snapshot/상태·스티커 저장/활동 기록을
  `BookshelfEntry#update_reading_state!` 같은 도메인 메서드로 이동하는 작은 작업부터 한다.
  Controller의 authorize/params/실패 응답은 남긴다. 기존 `BookActivities::RecordBookshelfEntryChange`
  호출을 재사용하며 새 Service가 기존 Service를 감싸기만 하게 만들지 않는다.
- **예상 파일/영향**: Controller, BookshelfEntry, 모델/request spec. create의 import는 별개 단위로
  검토한다. `Book.find_or_initialize_from_search`를 Model identity 규칙의 단일 기준으로 유지한다.
- **위험/효과/독립성**: 실패 시 DB 값 reload와 제출값 복원, 변경 없는 저장의 활동 미생성,
  sticker 미제출과 빈 배열의 차이를 보존한다. update만 독립 구현 가능. 여러 레코드 업무인 import를
  분리할 때에만 Service를 검토하고 unique-index retry의 트랜잭션 밖 재시도 경계를 유지한다.

### R7 — Groups#index의 피드와 카드 준비 (P2)

- **근거/문제**: `app/controllers/groups_controller.rb:10`은 12~22행 활동 피드와 이후 현재/과거
  membership 목록, 숨긴 카드, pending 수, 초대를 준비한다. Stream 조기 반환 뒤에만 필요한
  데이터가 무엇인지 액션 전체를 읽어야 한다.
- **제안/전후**: 우선 `prepare_group_activity_feed`, `prepare_group_list` private 메서드로 분리.
  재사용처가 없는 Concern은 만들지 않는다. 이후 목록 조합을 독립 검증할 필요가 생길 때만
  인가된 relation을 입력받는 `GroupListQuery`를 검토한다.
- **범위**: Controller와 groups 요청 spec. `GroupMembership.card_previews_for`, displayed_for,
  `GroupMembershipEvent.past_states_for`는 재사용한다.
- **위험/효과/단위**: 현재/과거 순서, 이미 로드한 배열, 카드당 회원 수 일괄 집계, 피드 요청의
  카드 조회 생략을 보존한다. private 메서드 추출만으로 독립 완료 가능하며 성능 변화는 목표가 아니다.

### R8 — JjaeksController의 생성 조율 (P2, 현재는 보류)

- **근거/문제**: `create:65`는 약 66행에 목적지 확인, attributes 축소, group lock, 중복 인용,
  추천 Book unique 충돌 재시도, 알림, 완료 Stream/redirect가 함께 있다. `render_failed_create:256`은
  추천/동아리/책/프로필/홈의 화면 준비를 조율한다.
- **제안/전후**: Controller 안에서 목적지 검증, 저장 시도, 성공 응답을 명확한 private 단계로 나눈다.
  요청 문맥과 render 선택을 Model에 넣지 않는다. 재시도 block이 중간 단계 추출로 달라지지 않게 한다.
  `RecommendationSelection`은 여러 Controller가 실제 공유하므로 유지한다.
- **범위**: Controller, 기존 생성/추천/다시짹 요청 spec. 필요 시 실패 화면 준비만 R3 Concern을 재사용.
- **위험/효과/단위**: 추천 작업에서 현재 수정한 실패 입력·revision 응답을 먼저 검증해야 한다.
  A/B/C와 HTML fallback 유지가 중요하다. 정책 분기를 제거하기 위한 범용 `PublishContent` Service는
  추천하지 않는다. 무결성 작업 안정화 이후 별도 단위로 진행한다.

### R9 — 댓글 실패 응답의 상세 준비 중복 (P2)

- **근거/문제**: `app/controllers/comments_controller.rb:48`, 83행, 123행 부근에서
  like summary/reading state/requote count를 준비한 뒤 `jjaeks/show`를 렌더한다.
  `JjaeksController#show/#prepare_comments`도 같은 화면의 일부 데이터를 다른 순서로 준비한다.
- **제안/전후**: 먼저 CommentsController의 세 실패 분기를 작은 private 준비 메서드로 묶는다.
  정말 같은 화면 계약이 확인된 부분만 `JjaekDetailContext`로 공유한다. 댓글 패널의
  `editing_comment` 대체/문맥별 DOM ID는 유지한다.
- **범위/위험**: CommentsController와 댓글 request spec. 숨김/삭제 상세는 JjaekPolicy 분기를
  거치므로 단순히 두 전체 준비 메서드를 합치지 않는다.
- **효과/단위**: 상세에 필요한 데이터 추가를 실패 응답에서 빠뜨리는 위험을 줄인다. 한 파일부터
  독립 진행 가능. 모든 respond_to 블록을 공통화할 필요는 없다.

## 5. View / Helper / 중복·간접 계층의 판단

### R10 — 사용되지 않을 가능성이 있는 과거 카드와 옵션 (P3)

`app/views/bookshelf_entries/_bookshelf_entry_compact.html.erb`, `_bookshelf_entry_preview.html.erb`는
app/spec/config의 명시적 호출 검색에서 사용처를 찾지 못했다. 실제 transfer는 이름 순서가 다른
`_compact_bookshelf_entry`를 사용한다. `_bookshelf_entry`는 Rails implicit render 대상이 될 수 있다.

**제안**: render 문자열뿐 아니라 collection implicit rendering, `to_partial_path`, 동적 선택과
관련 system spec을 확인한 뒤 미사용이 확정된 것만 삭제한다. 이번 결과는 삭제 확정 목록이 아니다.
예상 영향은 해당 partial과 호출 검증에 한정되고, 효과는 비슷한 이름의 카드 탐색 혼선 제거다.
카드별 독립 작업으로 가능하다. `show_move_control: false`를 받지만 읽지 않는 현행 카드 local도
R5 이후 같은 방식으로 검토한다.

반대로 `jjaek_option_card_classes`, `show_requote_book_link?`, `transfer_path_for`는 실제 호출부를
확인했다. 짧거나 간접 호출이라는 이유로 삭제하지 않는다.

### R11 — 페이지 번호 계산만 재사용할 여지 (P3)

`app/views/requotes/_pagination.html.erb:3`의 첫/끝/현재±2 번호 계산과
`app/helpers/admin/pagination_helper.rb:3`는 같은 표현 목적이다. 필요할 때 일반 Helper의 순수
번호 계산 함수로 옮길 수 있다. 변경 대상은 두 계산/호출부와 helper 검증에 한정한다.

그러나 `admin/shared/_pagination`, `shared/_pagination`, `feeds/_pagination`은 각각 번호/범위,
이전·다음, cursor 로딩이라는 계약이 다르다. 하나의 옵션 많은 pagination partial로 합치지 않는다.
재사용 효과가 작고 Turbo/return query 손실 위험이 있으므로 독립적으로 가능하되 우선순위는 낮다.

### R12 — 비슷한 moderation 코드의 과도한 통합 금지 (P3)

`app/services/jjaeks/hide.rb:14`와 `comments/hide.rb:14`는 매우 비슷하다. 그러나 policy와 대상,
복구 조건, 알림 경계가 명시적으로 읽힌다. 각각 43행이며 현재는 `Hide.call(record:, policy:, ...)`
기반 클래스/템플릿 메서드로 바꾸는 비용이 더 크다. state/audit/notification을 묶는 Service라는 위치는 적절하다.

`app/views/admin/jjaek_hides/_form`, `jjaeks/group_hides/_form`, `comments/group_hides/_form`의
중복도 확인했다. route, 번역, hint ID가 다르고 각각 짧다. 기존
`shared/_moderation_internal_note_field`가 의미 있는 공유 경계다. 같은 field가 반복 변경될 때만
사유 입력 부분의 공통화를 검토한다. 모든 권한의 전체 form을 설정 Hash로 통합하지 않는다.
예상 변경 영향은 moderation 네임스페이스 전체이므로 지금은 독립 리팩토링으로 권장하지 않는다.

### 표현과 조회의 구분

View 전체 검색에서 SQL 조립이 광범위하게 퍼진 형태는 확인하지 못했다.
`users/_profile_header:8`의 팔로워 count는 단일 프로필의 명시적 조회이고,
`books/_reading_state`의 선택 ID 변환, `_card_information`의 스티커 이름 요약은 표현 작업이다.
모두 Query Object로 옮길 이유는 없다.

실제 경계 문제는 R2의 Helper DB/인가 호출이다. `JjaeksHelper#current_user_like_for`와
`NotificationsHelper#notification_membership_group`의 fallback 조회는 controller에서 준비한
일괄 데이터가 없는 문맥을 지원한다. 최근 preload 개선과 연결되므로 호출 문맥 확인 없이 제거하지 않는다.
`UsersHelper`의 명시적 Tailwind 색상표도 build 시 탐지와 가독성에 도움이 되며 동적 문자열 생성으로
축약하지 않는다. 별도 BookshelvesHelper로 옮기는 것은 선택적인 정리로, 상위 작업은 아니다.

## 6. 유지하는 것이 더 적절한 구조

| 구조와 근거 | 유지 이유 |
| --- | --- |
| `Book.find_or_initialize_from_search` | ISBN/URL 충돌·기존 metadata 보존은 Model identity 규칙이다. controller별 복제나 범용 import 프레임워크 금지 |
| `BookshelfEntry`의 이동/정렬 도메인 메서드 | 소유권·위치 정합성은 Model 책임. Controller action마다 Service wrapper를 만들지 않음 |
| `FeedPage` | relation을 받아 SQL limit/cursor 적용 후 제한된 결과를 합친다. offset paginator와 억지 통합하지 않음 |
| `GroupContentThreadQuery` + `Groups::ContentThreadQuery` / `Admin::GroupContentThreadQuery` | thread pagination/hydration은 공유하고 일반/운영 검색 범위를 명시적으로 분리한다. 두 얇은 subclass는 권한 차이를 보이는 유용한 간접 계층 |
| `RelationshipsQuery` + `RelationshipManagement` | 조회/count와 여러 요청의 Turbo/HTML 응답 공유가 구분됨 |
| `BookSearchResults` | 일반 검색과 추천 선택 갱신이 실제 같은 준비를 재사용. DB/외부 조회가 있다고 Concern 자체를 없앨 필요 없음 |
| `Users::WithdrawAccount` | 계정·그룹·개인 자료 정리의 여러 레코드 transaction을 명시적으로 조율하는 Service가 적절 |
| `Notifications::*Notifier` | commit 이후 알림, 수신자 제외, 전달 오류 처리라는 독립 책임. 일반 model callback으로 흩뜨리지 않음 |
| `NotificationsController#prepare_notification_display_data` | 표시 단계에 한정한 preload와 policy cache를 명시한다. 표현 Helper와 현재 경계를 유지하고 전역 cache 금지 |
| `books/_thumbnail`, `bookshelf_entries/_card_information`, `shared/_content_field` | 표지·카드 정보·본문 입력이라는 응집된 UI. 이를 다시 작은 HTML 요소별 partial로 쪼개지 않음 |
| `GroupMembership.card_previews_for` | window count/rank와 최대 3명 preload라는 측정 가능한 목적을 가진 기존 조회. 이번에 generic Query로 이동할 이익이 작음 |

`SearchesController`의 유형별 조회나 `GroupPolicy`/`JjaekPolicy`의 개인·동아리 Scope를 단순히
분기가 많다는 이유로 합치지 않는다. 정책의 차이를 숨기는 공통화는 유지보수를 악화시킨다.
`Group#transfer_admin_to!`를 호출하는 작은 AdminTransfersController도 추가 Service가 필요하지 않다.

## 7. 권장 실행 순서와 완료 기준

1. **R1**: Library 정상/실패 경로를 특성화 → 공통 Context → 명세 설명 차이와 오류 동작을 별도로 정리.
2. **R3**: 책 상세 준비 세 메서드만 이동. 기존 추천/피드 변경을 검증한 뒤 수행.
3. **R5**: Library 입력 계약과 navigation partial만 정리. 모바일 DOM 구조를 별도로 검증.
4. **R2**: 보안 성격의 URL 검증을 이동. 현행 allowlist와 fallback의 동등성을 우선 확인.
5. **R4**: membership 승인 하나를 Service로 옮기고 lock/rollback/event/commit 알림을 확인.
6. 이후 R6 update, R7 private 조회 준비, R9 실패 상세 순으로 작은 작업을 검토.
   R8은 콘텐츠 무결성 작업이 끝난 뒤, R10~R12는 실제 변경 필요가 생길 때만 진행.

각 작업은 코드량 감소가 아니라 **수정 이유가 하나이고 동작 계약이 보존되는지**로 완료를 판단한다.
기존 request/policy/model/system 테스트를 삭제·약화하지 않는다. Model에는 도메인 invariant,
Concern에는 실제 공유되는 요청/화면 준비, Query에는 복잡한 조회, Service에는 독립적인 업무
transaction만 둔다. 제안 객체와 Concern을 모두 한 번에 도입하지 않는다.

이번 결과는 정적 설계 감사다. 사용하지 않는 코드의 제거 가능성, 실제 N+1/메모리 비용,
브라우저 상태와 성능 향상은 실행 검증으로 확정해야 하며 이번 보고서에서 통과했다고 주장하지 않는다.
