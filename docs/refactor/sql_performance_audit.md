# SQL 성능 감사와 단계별 최적화 계획

## 상태와 조사 범위

- 조사일: 2026-11-02. 브랜치: `perf/query-optimization`, 기준 HEAD: `9de9814`.
- **감사 결과와 개선 후보**를 기록한다. 새 정책이나 구현 완료를 뜻하지 않는다.
- 홈/프로필 → 검색/태그 → 발견 → 서재/책 상세/독서 활동 → 동아리/댓글/회원 → 알림 → 관리자 순으로 핵심 조회와 호출부를 추적했다. 전체 파일 전수 검토는 아니다.
- 기존 `app/queries/group_content_thread_query.rb`, `spec/requests/admin/groups_spec.rb`의 미커밋 변경을 포함해 검토하고 그대로 보존했다. 이번 단계에서는 애플리케이션·테스트·마이그레이션 코드를 변경하지 않았다.
- RSpec, 전체 테스트, 브라우저 검증, 운영 DB 접근, 데이터 생성, Git commit/merge/push는 수행하지 않았다.

기준 문서는 [현재 시스템](../architecture/current_system.md), [권한 구조](../architecture/authorization.md), [Jjaek visibility](../architecture/jjaek_visibility.md), [테스트 전략](../testing/rspec_strategy.md)다. 기능별로 [통합 검색](../specs/unified_search.md), [해시태그](../specs/hashtags_mvp.md), [발견](../specs/discovery_page_mvp.md), [서재](../specs/library_screen.md), [동아리 콘텐츠 관리](../specs/group_content_management.md), [moderation](../specs/moderation_mvp.md), [다시짹 공유](../specs/group_sharing_requotes.md), [다시짹 목록](../specs/requotes_mvp.md), [알림](../specs/notifications_mvp.md)을 확인했다. 이 문서는 canonical 정책을 대체하지 않는다.

### 판단과 측정의 한계

- P1: 자주 쓰는 화면에서 전체 데이터 또는 연결 데이터 증가가 요청 비용에 직접 반영되는 우선 개선 후보.
- P2: 특정 사용자·동아리·이력의 증가나 깊은 페이지에서 위험이 커지는 후속 후보.
- P3: 현재 구조가 대체로 제한되어 있고 추가 측정 후 판단할 영역. 아래 상위 10개 밖의 보류 항목으로 구분한다.
- 개발 DB `checkjjaek4_development`의 로컬 소켓에만 연결했다. PostgreSQL **14.24**, ActiveRecord **8.1.3.1**이다.
- DB 조회는 `BEGIN READ ONLY`, `statement_timeout = 3s`, `lock_timeout = 1s` 안에서 수행하고 rollback했다. EXPLAIN은 `EXPLAIN (FORMAT JSON)`만 사용했다. `ANALYZE`, 데이터/인덱스/통계 변경은 수행하지 않았다.
- 기존 데이터의 소규모 COUNT, ID 집합 비교 및 권한 함수의 SQL 발생 횟수도 읽기 전용으로 확인했다. 이는 RSpec 실행이나 요청 시간 벤치마크가 아니다.
- 실제 COUNT: User 31, Jjaek 141, Comment 13, BookActivity 45, Book 42, BookshelfEntry 40, Group 12, GroupMembership 20, Notification 95, Tag/JjaekTag 각 0건. 이런 작은 테이블의 Seq Scan 자체는 결함의 증거가 아니다. 태그 계획은 특히 비어 있는 테이블의 추정이다.
- 아래 비용은 planner의 임의 단위이고 시간이 아니다. SQL 실행 시간, p95, 메모리/할당량, 버퍼 읽기 및 대규모 개선율은 측정하지 않았다. [PostgreSQL EXPLAIN 문서](https://www.postgresql.org/docs/14/using-explain.html)의 의미에 따라 해석한다.

## 우선 검토할 조회 10개

### 1. P1 — 피드 카드의 연결 데이터 전체 로딩과 공유 권한 반복 조회

- **파일·메서드/화면:** [HomeFeedContext#prepare_home_feed](../../app/controllers/concerns/home_feed_context.rb), [ProfileContext#resolve_profile_jjaeks](../../app/controllers/concerns/profile_context.rb), [GroupShowContext#prepare_group_jjaek_context](../../app/controllers/concerns/group_show_context.rb), [GroupsController#index](../../app/controllers/groups_controller.rb), [ApplicationController#prepare_book_show_read_context](../../app/controllers/application_controller.rb). 홈·프로필·동아리·책 상세의 공통 카드에 해당한다. [JjaekPolicy#group_share_destinations/#share_to_group?](../../app/policies/jjaek_policy.rb), [JjaeksHelper#current_user_like_for](../../app/helpers/jjaeks_helper.rb), [Jjaek#safe_association_count](../../app/models/jjaek.rb), [카드 actions](../../app/views/jjaeks/_jjaek_actions.html.erb)까지 추적했다.
- **구조적 문제:** root는 최대 21개지만 `includes(:likes, :comments)`는 해당 root의 좋아요·댓글 전부를 객체로 만든다. 카드는 건수와 내 좋아요만 필요하고 댓글 본문은 별도 panel에서 읽는다. 여러 피드는 `:moderation_actions` 전체도 preload하지만 `current_hide_action`은 별도 relation을 만들어 다시 SQL을 실행하므로 이것만으로 현재 숨김 조회가 해결되지 않는다. 공개 개인 원본마다 `share_to_group?`가 active membership·Group을 다시 가져오고, 목적지마다 활동 가능 membership과 기존 다시짹의 EXISTS를 실행한다. 책짹이면 책 등록 여부 확인도 더해진다.
- **근거:** 코드 분석 + **SQL 발생 횟수 실측**. actor ID 2의 공개 개인 원본 일반 짹에 대해, 작성자/책을 미리 로드한 후 `JjaekPolicy.new(actor, post).share_to_group?`만 호출했다. `ActiveRecord::Base.uncached`와 `sql.active_record`로 SCHEMA/TRANSACTION을 제외해 집계했다. 1개 카드 **10회**, 3개 **30회**였다. 이 actor의 active membership은 7개이고 이 경로에서 쓰기 검사를 통과하는 목적지 4개에 대해 membership/중복 EXISTS가 반복되었다. SQL 캐시가 켜진 실제 요청의 DB 왕복 수나 전체 렌더링 시간으로 해석하지 않는다. 게시물·목적지 조합별 중복 EXISTS는 서로 다른 SQL이다.
- **증가 영향:** 카드 수 P, 목적지 수 G에 따른 `P×G` 권한 조회와, 페이지 글들의 전체 댓글·좋아요 수에 비례한 전송·객체 생성. 인기 글 하나만 있어도 root page size로 메모리 사용을 제한할 수 없다.
- **최소 개선:** 페이지 root ID에 한정한 댓글/좋아요 `GROUP BY COUNT`, 내 좋아요 일괄 조회, 현재 숨김 조치 일괄 조회를 준비한다. 작성 가능한 목적지는 요청 안에서 한 번 계산하고 `(원문 ID, 목적지 ID)`의 기존 공유도 일괄 조회하여 policy가 소비하게 한다. policy를 view 조건문으로 복제하지 않는다. 전체 목록 preload를 제거할 때는 상세·panel에서 실제 필요한 연관은 유지한다.
- **보존 조건:** 숨김 댓글도 개수에 포함, unsaved form 객체는 개수에서 제외한다. 개인/동아리 다시짹의 목적지별 중복, 책 등록, 현재 membership·활동 정지·운영 상태와 단건 GET/POST 재인가를 보존한다. 요청 간 권한 캐시는 만들지 않는다. 검색의 읽기 전용 preview는 actions를 렌더링하지 않으므로 여기에 likes/comments preload를 추가할 이유가 없다.
- **수정 범위·필요 테스트:** 공통 controller 준비/기존 policy·helper·count 소비부와 피드 preload. `homes_spec`, `feed_pagination_spec`, `group_sharing_requotes_spec`, `group_jjaek_policy_spec`, `books_spec` 등을 대상으로 동일 버튼·건수·HTML/Turbo 결과와 SQL 증가 양상을 검증한다. 동일 SQL 문자열보다 카드·목적지 수가 늘어도 조회 횟수가 곱으로 증가하지 않는지 확인한다.

### 2. P2 — 홈·프로필·동아리 피드의 권한 scope와 정렬 인덱스

- **파일·메서드/화면:** [JjaekPolicy::Scope/FeedScope/ProfileScope/GroupContentScope/GroupActivityScope](../../app/policies/jjaek_policy.rb), [BookActivityPolicy::FeedScope](../../app/policies/book_activity_policy.rb), [FeedPage#records_after](../../app/queries/feed_page.rb), [BookFriendship.connected_ids_for](../../app/models/book_friendship.rb). 홈·개인 활동·동아리 소식과 책 상세 목록.
- **구조적 문제:** 권한 OR, 원문 ID subquery, 현재 hide와 restore 제외 조건이 중첩된다. `FeedScope`는 원문에 일반 `Scope`를 적용하고, 그 안에서 다시 인용 원문의 가시성 조건을 구성한다. followee와 friend ID를 Ruby 배열로 읽는 작업도 여러 scope에서 반복한다. DB에는 Jjaek의 `created_at`, user/group/book/target 단독 인덱스가 있지만, 대상을 좁히고 `created_at DESC, id DESC` 순서로 반환하는 복합 인덱스는 없다. BookActivity도 user/book과 시각은 단독 인덱스다.
- **근거:** 코드 분석 + EXPLAIN. actor 2 기준 홈 17노드/58.74, 자기 프로필 22/61.69, group 1 피드 30/93.41, BookActivity 홈 10/10.32. Jjaek 조회에 Sort 및 원문/Group/membership subplan이 나타났다. 복잡성 자체로 비효율을 단정하거나 각 subplan이 outer row마다 실행된다고 해석하지 않는다.
- **증가 영향:** 전체 글 중 읽을 수 있는 비율이 낮으면 최신 21개를 찾기 위해 더 많은 행과 권한 조건을 검사할 수 있다. 사용자별 이력·가입 동아리·소식받기 수가 커지면 작은 결과와 별개로 필터와 ID 배열 비용이 증가한다.
- **최소 개선:** 기존 커서는 유지하고 user/group/book 단위 시간 복합 인덱스를 먼저 비교한다. 공유 가능한 관계 ID는 요청 안에서 재사용하거나 SQL subquery로 표현한다. OR/IN을 JOIN/UNION으로 바꾸는 작업은 실행 계획과 중복 제거 필요성을 확인한 다음 별도 작은 변경으로 진행한다. 다시짹이 원본을 인용하지 못하는 validation만 근거로 원문 권한 subquery를 삭제하지 않는다.
- **보존 조건:** 홈의 Group 제외, target_user 예외, accepted 관계와 follow의 차이, 플랫폼 숨김 placeholder, 살아 있는 원문 접근 재검사, 삭제 원문 A/B/C 예외를 유지한다. 커서 동률 `(created_at, 타입, id)`와 소스별 21개/최종 20개를 유지한다.
- **수정 범위·필요 테스트:** 우선 인덱스 후보 검증, 이후 해당 policy scope와 관계 조회만 수정. `jjaek_feed_policy_spec`, `book_activity_policy_spec`, `group_jjaek_policy_spec`, `feed_pagination_spec`의 권한·동시각·다음 페이지 경계를 보존한다. 추가 데이터 분포별 계획 비교가 필요하다.

### 3. P1 — 통합 문자열 검색의 부분 일치·정확한 COUNT·OFFSET

- **파일·메서드/화면:** [SearchesController#results_for/#show](../../app/controllers/searches_controller.rb), [Admin::InventoryPage#initialize](../../app/queries/admin/inventory_page.rb). `/search` 사용자·짹·책짹·동아리 문자열 결과와 개별 탭.
- **구조적 문제:** `%검색어%` ILIKE로 `jjaeks.content`, `users.name/handle`, `groups.name`을 검색한다. 기존 이름/handle 식별용 B-tree는 이 부분 일치를 직접 해결하는 인덱스가 아니다. 개별 탭은 권한·검색 조건을 COUNT하고 다시 정렬/limit/offset한다. 전체 탭은 COUNT 없이 유형별 5건이지만 드문 검색어라면 후보 탐색이 많이 필요하다.
- **근거:** 코드 분석 + EXPLAIN. actor 2, 일반 짹, `%독서%`, 첫 30개: page 16노드/50.73, COUNT 15/50.73. Jjaek Seq Scan과 권한 subplan, page Sort를 확인했다. `pg_indexes`와 schema에 trigram 인덱스는 없다. 2글자 검색어의 계획은 향후 trigram 효율을 입증하지 않는다.
- **증가 영향:** 선택도가 낮거나 일치가 드문 검색에서 전체 문서/사용자 탐색, 결과가 많은 검색에서 정확한 COUNT와 깊은 OFFSET 비용이 커진다. 100건 선택은 연관 preload와 응답량도 늘린다.
- **최소 개선:** 검색 의미를 그대로 두고 적절한 컬럼의 `pg_trgm` GIN 후보를 평가한다. 한글·영문, 1~2글자·긴 문자열, 흔한 값·드문 값, `%/_/\\` 리터럴을 구분한다. 추출 가능한 trigram이 없으면 전체 인덱스 탐색으로 퇴화할 수 있다. [PostgreSQL pg_trgm 문서](https://www.postgresql.org/docs/14/pgtrgm.html)에 따른 제약이며 효과는 미측정이다. COUNT 생략·상한·근사치 또는 cursor 전환은 현재 정확한 페이지 수/번호 정책을 바꾸므로 별도 결정 사항이다.
- **보존 조건:** 검색은 기존 SearchScope 결과 안에서 게시물 **자신의 본문**만 검색하고 숨김·삭제·접근 불가 원문을 제외한다. 원문 subquery에 검색어/글 종류 필터를 밀어 넣지 않는다. 사용자 이메일 검색 금지, 비공개 Group의 이름 검색 예외와 내부 정보 비노출을 유지한다.
- **수정 범위·필요 테스트:** 우선 인덱스 설계 및 추후 승인된 migration, 필요하면 해당 relation 구성만 수정. `searches_spec`에서 네 유형·한글·이스케이프·권한·정확한 건수/페이지·preview 5개를 검증하고, 인덱스 적용 전후 대표 계획과 실제 요청 시간을 별도로 비교한다. 검색 엔진 교체는 필요하지 않다.

### 4. P2 — 인기 태그의 전체 가시 게시물 집계

- **파일·메서드/화면:** [SearchesController#prepare_popular_tags](../../app/controllers/searches_controller.rb). 검색어 없는 `/search` 첫 화면. 정확한 태그 검색은 `#results_for`의 Tag/JjaekTag ID subquery다.
- **구조적 문제:** 전체 SearchScope의 글 ID와 태그 연결을 결합하고 `GROUP BY`, `COUNT(DISTINCT jjaek_id)`, HAVING, count 정렬 후 8개를 제한한다. LIMIT 8은 집계 입력을 8개로 제한하지 않는다. `(jjaek_id, tag_id)` unique가 중복 연결을 막으므로 현재 JOIN 형태의 DISTINCT는 불필요할 가능성이 있다.
- **근거:** 코드 분석 + EXPLAIN 24노드/187.51. Aggregate와 count Sort가 나타나지만 **Tag/JjaekTag는 0건**이므로 비용·카디널리티의 신뢰도가 낮고 실측 효과는 없다. 정확한 태그 검색은 `tags.name` unique와 `jjaek_tags.tag_id` 인덱스가 이미 있다.
- **증가 영향:** 태그 연결과 읽을 수 있는 과거 게시물이 늘면 첫 검색 진입마다 집계해야 할 입력이 늘어난다. 유저별 가시성이 달라 전역 인기 태그 캐시로 단순 대체할 수 없다.
- **최소 개선:** 중복을 만드는 JOIN이 없다는 것을 확인하고 DISTINCT 없는 COUNT의 동등성을 작은 변경으로 검토한다. `(tag_id, jjaek_id)` covering 후보는 정확한 태그 결과/집계 계획을 보고 선택한다. DISTINCT 제거/인덱스만으로 전체 집계의 증가 비용이 사라지지는 않는다. 기간 제한·미리 계산한 전역 상위 N개 필터링·권한 무효화 없는 캐시는 현재 정책을 바꾼다.
- **보존 조건:** 현재 사용자에게 보이는 글만 집계, 글당 동일 태그 1회, 2개 이상 글에 쓰인 태그가 3개 이상일 때만 표시, 최대 8개·건수 DESC/이름 ASC. 숨김·원문 접근 상실도 집계에 반영한다.
- **수정 범위·필요 테스트:** 집계 표현과 필요 시 연결 인덱스. `searches_spec` 및 태그 관련 기존 model/request scenario에서 중복 태그·동률·임계값·private/Group/다시짹을 검증한다. 충분한 연결 데이터의 계획은 후속 측정 과제다.

### 5. P1 — 발견의 날짜별 MD5 정렬과 작성자별 반복 선정

- **파일·메서드/화면:** [DiscoveriesController#daily_order/#varied_jjaeks/#prepare_book_jjaeks/#prepare_recommended_library/#prepare_recommended_group](../../app/controllers/discoveries_controller.rb). `/discover`의 책·짹·서재·동아리 추천.
- **구조적 문제:** `ORDER BY md5('발행일:' || id::text), id`는 일반 ID/시각 인덱스로 그 순서를 공급할 수 없다. LIMIT 1/3이어도 적격 후보의 해시를 계산해 상위 후보를 결정해야 한다. 작성자 최대 3명을 먼저 뽑고 작성자마다 같은 후보 relation을 다시 해시 정렬한다. 부족분 조회와 미가입 Group이 없을 때의 재조회도 있다. 쿼리 횟수는 작성자 최대 3명으로 제한되지만 입력 크기는 제한되지 않는다.
- **근거:** 코드 분석 + EXPLAIN. 2026-11-02 KST 발행 기준 책 선정 20노드/57.96, 일반 짹 작성자 선정 20/55.41, 단일 작성자 짹 17/49.98. 앞의 두 계획에 후보 집계와 `md5(...)` Sort를 확인했다. 대규모에서의 시간은 추정만 가능하다.
- **증가 영향:** 공개 원본·작성자·공개 책장 소유자·Group이 늘수록 매 요청 여러 후보 집합을 탐색한다. 매일 seed가 달라지는 표현식에 고정 인덱스 하나를 추가하는 방식으로 해결하기 어렵다. top-N 정렬이어도 전체 후보 평가가 필요한 점이 핵심이다.
- **최소 개선:** 우선 고정된 공개 원본 조건 하에서 중복되는 범용 권한 subquery를 동등하게 단순화할 수 있는지 확인한다. 이어 선정된 작성자 ID에 한정한 window/LATERAL 조회로 작성자별 왕복을 합치되 날짜 해시·ID 순서와 부족분 보충을 유지한다. 이것은 왕복 감소 후보이며 전체 후보 해시 비용 제거를 보장하지 않는다. 일일 결과 저장소/잡/장기 캐시 도입은 현재 spec의 “저장소·정기 작업 없음, 매 요청 권한 반영”과 다르므로 별도 설계가 필요하다.
- **보존 조건:** 같은 날 결정성, KST 자정과 오늘 글 제외, 작성자 다양성/부족분, 자기 일반 짹 제외, 전체 공개 책장만의 수량, 미가입 Group 우선, 권한·숨김 변경의 즉시 반영. 임의 sampling이나 최신 N개만 먼저 제한하는 방식은 같은 결과를 보장하지 않는다.
- **수정 범위·필요 테스트:** 해당 controller 조회 또는 기존 policy에 좁은 scope 추가 여부 검토. `discoveries_spec`의 날짜·권한·후보 부족·다양성·미가입 우선 결과를 보존하고 후보 조회 횟수를 비교한다. 후보 수별 시간/CPU 측정 후 별도 저장 설계 필요성을 판단한다.

### 6. P2 — 프로필 책 carousel과 Library/이동 화면의 무제한 로딩

- **파일·메서드/화면:** [ProfileContext#profile_summary_bookshelf_entries](../../app/controllers/concerns/profile_context.rb), [Users::LibrariesController#prepare_library_bookshelf/#prepare_bookshelf_transfer](../../app/controllers/users/libraries_controller.rb), [BookshelfEntry.profile_sorted](../../app/models/bookshelf_entry.rb), [프로필 책 목록](../../app/views/users/_profile_public_books.html.erb), [JjaeksHelper#book_navigation_params/#jjaek_return_destination](../../app/helpers/jjaeks_helper.rb).
- **구조적 문제:** 프로필은 접근 가능한 책 전부를 가져와 Ruby에서 `each_slice(4)`로 모든 carousel 페이지 HTML을 만든다. Library는 선택한 책장 전체, transfer는 두 책장 전체와 책·스티커를 가져온다. carousel의 첫 4개 표시는 SQL LIMIT가 아니다. 카드별 `book_navigation_params`도 동일 현재 URL의 user/책장 접근 검사를 반복할 수 있다. `recent`는 `updated_at DESC`만 지정하고 title/author는 Book JOIN 후 정렬한다.
- **근거:** 코드 분석 + 자기 프로필 책 조회 EXPLAIN 5노드/3.53, Sort/Bookshelf JOIN, LIMIT 없음. 전체 화면의 메모리·렌더링 시간과 링크 검증 쿼리 수는 미측정. Book/스티커는 이미 preload하므로 단순히 N+1을 고치는 문제로 한정하면 안 된다.
- **증가 영향:** 개인 장서 B와 스티커 수에 비례한 전송·객체·HTML 증가. 책 이동 중에도 두 장서 전체가 필요해진다. 큰 장서는 적은 사용자 수로도 비용을 만든다.
- **최소 개선:** 우선 동일 URL의 검증 결과를 **현재 요청 안에서** 재사용하고, 상태 미표시 문맥에서 불필요한 스티커 로딩 여부를 확인한다. 이후 carousel/선택 책장에 지연 조회를 적용하려면 순서와 전체 탐색을 유지하는 설계가 필요하다. transfer의 전체 ID 비교·수동 정렬·DnD 경계를 확인하기 전 단순 LIMIT를 넣지 않는다. recent에 ID tie-breaker 추가는 기존 동률 동작을 확인한 뒤 처리한다.
- **보존 조건:** self/accepted 책친구 Library 접근, 타인 private 책장 비노출, 공개 책 수, 현재 정렬과 선택 책장, 전체 이동/순서 계약. `ProfileScope`에 global admin 전체 장서 조회 우회를 추가하지 않는다.
- **수정 범위·필요 테스트:** 우선 helper/표시 문맥별 preload, 이후 controller·목록/이동 UI의 별도 작은 작업. `users_spec`, `users_libraries_spec`, `bookshelf_entries_spec`, `bookshelf_entry_policy_spec`의 private 책장/정렬/이동 경계와 전체 탐색을 검증한다. 인덱스만 추가해 전체 객체 로딩 문제를 해결했다고 보고하지 않는다.

### 7. P2 — 동아리 회원·댓글 전체 조회와 댓글 감사 이력 N+1

- **파일·메서드/화면:** [GroupMembersController#index/#membership_history](../../app/controllers/group_members_controller.rb), [CommentsController#prepare_comments_panel](../../app/controllers/comments_controller.rb), [CommentModerationHistory#prepare_comment_moderation_histories](../../app/controllers/concerns/comment_moderation_history.rb), [JjaeksController#show](../../app/controllers/jjaeks_controller.rb). 동아리 회원 관리, 글 상세와 inline 댓글 panel.
- **구조적 문제:** active/pending/invited/ban membership 및 lifecycle/moderation 이력을 모두 로드하고 과거 사건을 Ruby에서 합쳐 정렬한다. 댓글 panel도 전체 댓글·avatar를 로드한다. `prepare_comment_moderation_histories`는 조사 권한이 있는 **각 댓글**마다 hide/restore 이력과 actor를 개별 조회한다. 일반 회원에게 감사 이력을 조회하지 않는 경계는 있으나, 관리자의 큰 thread에서 N+1이 생긴다.
- **근거:** 코드 분석. 이 화면들의 요청별 SQL 횟수·시간은 실측하지 않았다. parent 댓글에 인덱스가 있다는 사실은 반환 행 수와 per-comment 이력 조회를 제한하지 않는다.
- **증가 영향:** Group 회원/사건 수, 인기 글 댓글 수 증가에 따라 메모리·HTML이 늘고 관리자 댓글 이력은 쿼리 횟수도 늘어난다. CommentPolicy의 parent/Group/현재 조치 확인도 연관이 준비되지 않으면 추가 조회를 발생시킬 수 있다.
- **최소 개선:** 우선 현재 조회 대상 댓글 ID를 권한별로 나눠 moderation action/actor를 일괄 조회하고 ID별로 묶는다. 해당 조회를 위해 전체 연관을 무조건 preload하기보다 허용된 action/authority만 읽는다. 회원·사건·댓글의 페이지 분리는 그 다음 작업으로 설계한다. 댓글 작성·수정·삭제 후 전체 panel 교체 및 anchor 동작도 함께 고려해야 한다.
- **보존 조건:** author-first 경계, global admin 전체 조사와 현재 group admin의 group-origin 이력 차이, platform 내부 메모 비노출, hidden parent/child 독립 상태와 placeholder·개수, 신규 interaction 금지. 회원 조회를 일반 회원에게 넓히지 않는다.
- **수정 범위·필요 테스트:** 우선 concern과 controller 연관 준비. `comment_moderation_display_spec`, `group_comment_moderation_spec`, `comments_spec`, `group_memberships_spec` 등에서 HTML/Turbo·권한별 이력·빈 panel·마지막 댓글 삭제를 보존하고 댓글 수 대비 감사 조회 횟수를 확인한다. 페이지 분리는 별도 request/UI 테스트가 필요하다.

### 8. P1 — 알림 inbox 전체 이력 로딩·읽음 ID 배열·다형 연관 후속 조회

- **파일·메서드/화면:** [NotificationsController#index/#mark_notifications_as_read](../../app/controllers/notifications_controller.rb), [NotificationPolicy::Scope](../../app/policies/notification_policy.rb), [NotificationsHelper](../../app/helpers/notifications_helper.rb), [Notification.broadcast_badge_to](../../app/models/notification.rb). `/notifications`와 badge.
- **구조적 문제:** 수신자 전체 알림을 `recent.to_a`로 로드한 뒤 unread ID를 Ruby 배열에 모아 `UPDATE ... id IN (...)`한다. `includes(:notifiable, actor: ...)`는 다형 객체 자체만 준비하므로 comment의 jjaek, 다시짹의 source/Group, event의 Group 및 policy의 관계 확인은 추가 조회가 된다. 현재 정렬은 created_at만이고 기존 `(recipient_id, read_at, created_at)`는 read_at 조건 없는 전체 inbox 최신순과 정확히 맞지 않는다. unread badge COUNT에는 이 인덱스의 선두 조건을 쓸 수 있다.
- **근거:** 코드 분석 + SELECT EXPLAIN 2노드/3.77, recipient filter → Sort, LIMIT 없음. UPDATE·broadcast는 실행하지 않았다. 실제 조회한 actor 2의 행 수 추정은 23건이며 수신자 전체 이력 증가 시 비용이 커진다는 판단은 코드에 근거한다.
- **증가 영향:** 누적 알림 N에 비례한 객체·HTML·unread ID 배열, notifiable 유형별 후속 N+1. unread가 많으면 읽음 UPDATE 및 badge 재집계 비용도 커진다.
- **최소 개선:** 우선 notifiable 유형별로 필요한 parent/source/Group을 한 번씩 preload하고 같은 알림에 대한 현재 접근 판정을 요청 안에서 재사용한다. 이후 `(recipient_id, created_at, id)` 인덱스와 cursor/limit을 검토한다. 페이지를 추가하면서 “조회한 페이지의 unread만 읽음”으로 자동 변경하지 않는다. 현재 **로드한 전체 이력을 읽음 처리**하는 동작과 전체/표시분 중 무엇을 읽음으로 볼지 명시해야 한다. 읽음 UPDATE를 단순 수신자 전체 조건으로 바꾸면 조회 후 도착한 새 알림까지 읽음 처리할 수 있으므로 snapshot 경계도 필요하다.
- **보존 조건:** 수신자 본인 scope, 읽음 상태와 도메인 사건의 분리, 원문/댓글의 현재 권한과 안전한 fallback, 운영 조치 actor·내부 메모 비노출. 권한 캐시를 요청 간 공유하지 않는다.
- **수정 범위·필요 테스트:** 우선 controller/helper의 연관 준비·중복 판정; 페이지/읽음 동작은 알림 spec 정리 후 별도 변경. `notifications_spec`, `group_lifecycle_notifications_spec`, `group_membership_notifications_spec` 등에서 기존 문구·대상 링크·탈퇴/삭제된 대상·unread badge와 동시 신규 알림 경계를 확인한다.

### 9. P2 — 관리자/동아리 콘텐츠 thread의 반복 scope·댓글 MAX·전체 thread hydration

- **파일·메서드/화면:** [GroupContentThreadQuery#apply_search/#apply_status/#latest_comments_join/#hydrate](../../app/queries/group_content_thread_query.rb), [Admin::GroupContentThreadQuery](../../app/queries/admin/group_content_thread_query.rb), [Groups::ContentThreadQuery](../../app/queries/groups/content_thread_query.rb). `/admin/groups/:id/content`, `/groups/:id/content`.
- **구조적 문제:** 기존 미커밋 수정이 status의 반복 root subquery 하나를 제거했다. search는 여전히 기존 thread scope를 root ID subquery로 감싸고, 공통 `prepare_scopes`의 ID wrapper 및 Group 검색의 이름/본문별 subquery도 중첩된다. page는 scoped 댓글을 `GROUP BY jjaek_id, MAX(created_at)`로 집계해 outer join하고 `GREATEST(root.created_at, latest_comment_at)` 정렬을 한다. root COUNT, page ID 선정, root hydration에서 검색/권한 조건을 재평가하며 선택한 root들의 **전체 댓글**을 로드한다.
- **근거:** 코드 분석 + 전후 EXPLAIN/ID 집합 비교. admin 검색+active는 56→39노드, 158.07→111.34; 현재 group-admin 검색+active는 72노드/281.30이다. 이는 다른 검색 권한 구조의 관찰이며 두 화면의 속도 비교가 아니다. 작은 DB에서 실제 시간 병목인지는 확인하지 않았다.
- **증가 영향:** 한 Group의 root·댓글·운영 이력이 늘수록 전체 댓글 집계·계산값 Sort, COUNT/중복 필터와 깊은 OFFSET 비용이 커진다. 30/50/100 root 제한은 전체 댓글 행 수를 제한하지 않는다.
- **최소 개선:** 기존 status 수정을 유지한다. 다음에는 같은 Group·허용된 댓글 조건을 유지하며 검색식의 중복 wrapper 제거를 한 단계씩 검토한다. 최신 댓글 집계를 적격 root 집합으로 좁히거나 인덱스 기반 LATERAL 최신 1건과 비교할 수 있다. 단, 현재 페이지 30개 root를 **먼저** 뽑은 뒤 MAX를 계산하면 순서가 달라진다. `hydrate`의 재검색 제거도 중간 삭제/권한 변화 때의 재검사 경계를 정하기 전 자동 적용하지 않는다. 최근 활동 counter/materialization은 댓글 삭제까지 책임져야 하므로 첫 변경으로 권장하지 않는다.
- **보존 조건:** root와 댓글의 검색/상태는 thread 포함 조건이며 전체 댓글 문맥을 보존한다. 검색에 맞지 않는 최신 댓글도 활동 시각에 반영한다. group-admin은 표시 가능한 본문·작성자 이름만 검색하고 이메일/platform-hidden/deleted 본문은 제외한다. admin의 조사 scope, tombstone, 상태 혼합, 동률 ID, 정확한 총 thread 수를 보존한다. 상세 동등성은 다음 절에 기록한다.
- **수정 범위·필요 테스트:** 공통 query와 두 검색 subclass, 필요 시 댓글 복합 인덱스. 기존 두 query spec/공유 검색 계약, `admin/groups_spec`, `group_content_inventory_spec`에 검색×유형×상태·다른 Group 배제·숨김 authority·deleted root의 visible 댓글·전체 문맥·정렬/페이지 경계를 보강한다.

### 10. P2 — 관리자 목록의 “최근 콘텐츠”가 페이지 대상의 전체 이력을 정렬

- **파일·메서드/화면:** [Admin::LatestContentActivityQuery#latest_rows_sql/#activity_rows_sql](../../app/queries/admin/latest_content_activity_query.rb), [Admin::UsersController#index](../../app/controllers/admin/users_controller.rb), [Admin::GroupsController#index](../../app/controllers/admin/groups_controller.rb). 사용자/동아리 모니터링 목록의 마지막 활동 열.
- **구조적 문제:** 현재 페이지의 owner ID로 범위를 제한하는 점은 좋다. 그러나 해당 owner들의 Jjaek·Comment 전체를 UNION ALL하고 `DISTINCT ON(owner_id)`를 위해 owner/time/type/id 순으로 정렬한다. Group 댓글은 부모 Jjaek JOIN으로 owner를 구한다. 마지막 1개씩만 필요해도 각 owner의 누적 콘텐츠를 처리한다.
- **근거:** 코드 분석 + EXPLAIN. owner User ID 1~30은 5노드/39.76, 현재 Group 12개는 8/48.10. `Append → Sort → Unique`, Group은 댓글 JOIN을 확인했다. 별도로 본 기본 inventory SELECT는 User 6/41.92, Group 9/31.20이며 scalar COUNT가 페이지 출력 측 Result에 있다. 이를 모두 “전체 테이블에 row별 COUNT”라고 확대 해석하지 않는다.
- **증가 영향:** 관리자 페이지 크기가 같아도 활발한 사용자·대형 Group이 포함되면 입력 이력 수가 커진다. 이 비용은 단순 inventory의 검색/COUNT/OFFSET에 더해진다.
- **최소 개선:** User는 owner별 Jjaek/Comment 각각 `ORDER BY created_at DESC, id DESC LIMIT 1`을 인덱스로 찾고 두 후보를 비교하는 LATERAL 형태를 검토한다. N개 owner를 Ruby loop의 N개 SQL로 바꾸지 않는다. Group 댓글은 group_id가 Comment에 없으므로, Jjaek/Comment 인덱스만으로 owner별 조기 중단이 가능한지 별도 계획 확인이 필요하다. 자동 denormalization이나 event cache를 추가하지 않는다.
- **보존 조건:** 운영 조사에서 hidden/deleted/private까지 현재 포함되는 범위, 콘텐츠 없는 owner, `created_at DESC, record_type DESC, record_id DESC` 동률 처리와 kind 판별. 일반 피드 scope로 대체하면 조사 범위가 달라진다.
- **수정 범위·필요 테스트:** 해당 query 및 대응 인덱스 후보. `admin/users_spec`, `admin/groups_spec`에서 글·댓글 중 최신, 같은 시각의 종류/ID, 숨김·삭제·그룹 댓글·활동 없음의 결과를 검증한다. 실제 큰 owner 이력의 버퍼/시간을 비교한 뒤 적용한다.

## EXPLAIN 관찰 기록

relation의 `to_sql`로 생성한 실제 SELECT에 EXPLAIN을 붙였다. includes의 후속 preload 쿼리와 HTTP 렌더링은 아래 숫자에 포함되지 않는다. 노드 수는 JSON Plan과 하위 `Plans`의 개수를 세었으며, 다른 SQL의 노드 수/비용을 성능 순위로 사용하지 않는다.

공통 actor ID 2(일반 계정), admin ID 1, Group ID 1. 별도 cursor가 없는 첫 페이지이고 시간 정렬은 `created_at DESC, id DESC`다. 검색은 `%독서%`; 발견 발행일은 2026-11-02 KST, cutoff는 그날 00:00이다.

| 생성 경로/조건 | 노드 수 | 최상위 Total Cost | 핵심 계획 |
| --- | ---: | ---: | --- |
| Jjaek FeedScope, LIMIT 21 | 17 | 58.74 | Sort, Jjaek/Group/원문 subplan |
| actor 본인 ProfileScope, LIMIT 21 | 22 | 61.69 | Sort, visible ID subquery |
| Group 1 GroupContentScope, LIMIT 21 | 30 | 93.41 | Sort, Group/hidden 조건 |
| BookActivity FeedScope, LIMIT 21 | 10 | 10.32 | BookshelfEntry/Bookshelf JOIN, Sort |
| SearchScope, book_id NULL, ILIKE, LIMIT 30 | 16 | 50.73 | Seq Scan, 권한 subplan, Sort |
| 같은 검색의 COUNT | 15 | 50.73 | Aggregate, 권한 subplan |
| 인기 태그, LIMIT 8 | 24 | 187.51 | JOIN, Aggregate, count Sort; 태그 0건 |
| 발견 책 후보, LIMIT 1 | 20 | 57.96 | book_id Aggregate, hash JOIN, MD5 Sort |
| 발견 일반 짹 작성자 후보, LIMIT 3 | 20 | 55.41 | user_id Aggregate, MD5 Sort |
| 발견 actor 2 일반 짹 후보, LIMIT 1 | 17 | 49.98 | user filter, MD5 Sort |
| actor 본인 프로필 장서, recent, LIMIT 없음 | 5 | 3.53 | Bookshelf JOIN, updated_at Sort |
| actor 수신 알림 전체, created_at DESC | 2 | 3.77 | Seq Scan, Sort |
| admin User 1~30의 최근 콘텐츠 | 5 | 39.76 | Append, Sort, Unique |
| admin 현재 Group 12개의 최근 콘텐츠 | 8 | 48.10 | 댓글 JOIN, Append, Sort, Unique |
| 기본 admin User inventory, LIMIT 30 | 6 | 41.92 | Sort, 출력 시 administered Group COUNT |
| 기본 admin Group inventory, LIMIT 30 | 9 | 31.20 | admin JOIN, Sort, 출력 시 active membership COUNT |
| actor 2 admin User timeline, 전체 유형, LIMIT 30 | 6 | 18.56 | UNION ALL/Append, Sort |
| group-admin thread, 전체 유형, `%책%`+active, LIMIT 50 | 72 | 281.30 | 권한별 검색 subquery, 댓글 Aggregate, Sort |

대표적으로 알림의 실제 SQL은 아래와 같다. recipient의 전체 조회이며 unread 조건이나 LIMIT는 없다.

```sql
SELECT "notifications".*
FROM "notifications"
WHERE "notifications"."recipient_id" = 2
ORDER BY "notifications"."created_at" DESC;
```

발견 책 선정에는 다음 실제 정렬식이 생성되었다.

```sql
ORDER BY md5('2026-11-02:' || "books".id::text) ASC, "books"."id" ASC
LIMIT 1
```

## 기존 관리자 SQL 수정의 동등성과 유지·보완 판단

### 결론: 유지하고, 공통 query의 조합 검증을 보완한다

현재 호출부와 relation 구조에서 권한·검색·유형 조건을 바깥 두 OR 분기 모두에 유지하므로 의미적으로 동등하다. 이번 감사로 되돌릴 이유는 발견하지 못했다. 입력 scope를 감싼 `prepare_scopes`와 두 검색 subclass의 권한 차이는 남아 있다.

검색 적용 후 root 집합을 S, root 상태 조건을 R, 허용된 댓글 중 상태에 맞는 댓글의 부모 ID 집합을 C라고 하면 다음과 같다.

```text
기존: S ∩ (id IN (S ∩ R) OR id IN C)
현재: (S ∩ R) OR (S ∩ (id IN C))
동일: S ∩ (R OR id IN C)
```

root의 primary key ID를 이용한 집합 조건이므로 이 중복 S 참조를 제거할 수 있다. 현재 `merge` 대상은 `Jjaek.where(...)`의 상태 predicate뿐이며, S는 이미 authorized ID subquery/유형/검색 조건을 갖고 있다. 상태 predicate가 인가 ID 조건을 덮어쓰지 않는다. 댓글 분기도 같은 S를 유지하므로 다른 Group의 정상/숨김 댓글로 외부 root가 섞이지 않는다. 임의 JOIN/다른 FROM을 가진 새 호출부까지 일반화한 증명은 아니다.

특히 **검색에 일치한 댓글과 상태에 일치한 댓글이 같을 필요가 없다.** 숨김 댓글 본문으로 검색한 thread에 정상 root나 다른 정상 댓글이 있으면 active 결과에 포함될 수 있다. 삭제 root도 정상 댓글이 있으면 active에, 삭제 root 조건으로 deleted에도 포함된다. 검색·상태가 서로 다른 thread 구성원에서 성립하는 기존 계약이다. 현재 추가된 request example 3개는 이 조합을 보강한다. 상태 필터를 검색 댓글 relation에 합치는 후속 수정은 다른 동작이 된다.

| admin Group 1, 전체 유형/30 root | 변경 전 노드/비용 | 현재 노드/비용 |
| --- | --- | --- |
| active, 검색 없음 | 28 / 93.97 | 24 / 78.74 |
| active, `%독서%` | 56 / 158.07 | 39 / 111.34 |
| hidden, 검색 없음 | 28 / 79.65 | 23 / 67.97 |
| hidden, `%독서%` | 56 / 144.74 | 38 / 100.62 |
| deleted, 검색 없음 | 22 / 51.73 | 17 / 40.06 |
| deleted, `%독서%` | 50 / 116.83 | 32 / 72.71 |

active+검색의 생성 SQL 크기는 2,540→1,700 bytes였다. 이는 구조 감소의 보조 지표이며 성능 지표가 아니다. 변경 전은 HEAD의 공통 query를 별도 임시 class로 읽었고, 동일한 현재 admin 검색 subclass와 입력 scope를 사용했다.

- 기존 개발 데이터에서 양방향 `EXCEPT`로 위 **6개 admin 조합**의 root ID 차이가 모두 0임을 확인했다.
- 같은 공통 부모를 쓰는 Group query도 **4개 유형(all/general/book/comments) × 3개 상태 × 검색 없음/`%책%` = 24개 조합**에서 전후 ID 차이가 0이었다. Group subclass는 동일하게 유지하고 부모만 HEAD/작업본으로 바꿨다.
- 검색 결과가 비거나 데이터에 특정 상태가 없으면 비교의 강도는 낮다. 위 비교는 fixture를 만들지 않은 기존 개발 데이터 검증이며 RSpec의 권한·조합 회귀 검증을 대체하지 않는다. hydration/HTTP 응답의 동등성도 실행 검증하지 않았다.
- 보완할 검증: 두 subclass의 검색×상태 결합, root만/댓글만 일치, 서로 다른 댓글의 조건 일치, deleted root+visible 댓글, 다른 Group/인가 제외 root, `jjaek_scope.none`/`comment_scope.none`, 전체 thread와 최신 비일치 댓글의 정렬, 동률/페이지 경계. Group 검색에는 현재 hide authority 변경 후 본문 비노출도 유지한다.

## 인덱스 개선 후보

`db/schema.rb`와 개발 DB `pg_indexes`의 관련 정의를 확인했다. 아래는 **선택 후보**이며 전부 추가하는 계획이 아니다. 실제 분포·선택도·쓰기 비용·기존 인덱스 중복을 비교한 뒤 응집 단위별로 선택한다. 이번에는 extension 설치나 인덱스 생성/삭제, migration 작성을 하지 않았다.

| 후보 | 맞추려는 조회 | 기존 상태와 선택 기준 |
| --- | --- | --- |
| `jjaeks(user_id, created_at DESC, id DESC)` | 프로필·User 마지막 활동 | user_id 단독과 created_at 단독은 있음. 전체 프로필/admin 재사용을 우선 평가 |
| `jjaeks(group_id, created_at DESC, id DESC)` | 특정 Group 피드·Group root 후보 | group_id 단독 있음. 여러 Group 통합 피드는 이 인덱스 하나로 최종 정렬 제거를 보장하지 않음 |
| `jjaeks(book_id, created_at DESC, id DESC)` | 책 상세·책친구 책 활동 | book_id 단독 있음. 개인/Group 조건 선택도와 함께 평가 |
| `jjaeks(target_user_id, created_at DESC, id DESC)` 및 개인 영역 시간 인덱스 | target 포함 홈 OR 분기 | target 단독 있음. `WHERE group_id IS NULL` partial/full 중 사용처별 선택. hidden/deleted 전체 제외 partial은 placeholder/tombstone 경로를 지원하지 못함 |
| `book_activities(user_id, created_at DESC, id DESC)`; 필요 시 book_id 시간 조합 | 활동 피드/책 상세 | 현재 user/book/time 단독. Bookshelf visibility JOIN 이후 효과를 비교 |
| `comments(jjaek_id, created_at DESC, id DESC)` | 댓글 최신 1개·thread·댓글 순서 | jjaek_id 단독 있음. MAX 집계 전체 비용/계산 활동 시각 Sort까지 없애지는 않음 |
| `comments(user_id, created_at DESC, id DESC)` | User 최근 콘텐츠·timeline | user_id 단독 있음. LATERAL 전환 후보와 함께 평가 |
| `notifications(recipient_id, created_at DESC, id DESC)` | 전체 inbox의 안정적 최신순·cursor | 현재 `(recipient_id, read_at, created_at)`는 unread COUNT에 유용. 새 순서와 pagination 설계 후 선택. 기존 인덱스를 바로 제거하지 않음 |
| `group_memberships(user_id, status, group_id)` 또는 `(group_id, status, created_at, id)` | 읽기/쓰기 Group scope 또는 member preview/목록 | `(group_id,user_id)` unique는 이미 단건 membership EXISTS를 지원. user scope와 Group별 집계 중 실제 비용이 큰 쪽을 선택; moderation_status 추가는 분포 확인 후 판단 |
| `jjaek_tags(tag_id, jjaek_id)` | 정확 태그 조회·인덱스 내 부모 ID 조회 | 반대 순서 unique와 tag_id 단독 존재. 태그 데이터가 없어 추가 가치 미검증 |
| `jjaeks.content`, `users.name/handle`, `groups.name`의 trigram GIN; 필요 시 admin용 comments.content/users.email | `%term%` 문자열 검색 | 현재 없음. 본문부터 우선 검토하고 짧은 한글/흔한 값/여러 컬럼 OR를 각각 비교. 이메일은 admin 전용 검색이며 일반 검색 정책을 넓히지 않음 |
| moderation target/time/id 또는 action/authority/target 조합 | 현재 hide/restore 및 Group 검색의 최신 authority | `(target_type,target_id,created_at)`, action_type, partial unique reversal_of는 이미 있음. 중복/유사 인덱스 추가 전 target 조회와 전체 authority scan 중 병목을 구분 |
| 필요 시 `bookshelf_entries(bookshelf_id, updated_at DESC, id DESC)` | 선택 책장 recent 지연 조회 | `(bookshelf_id, position)`는 수동 정렬에 이미 맞음. 전체 장서 반환을 계속하면 최근순 인덱스만의 효과는 제한적 |

정렬 인덱스는 WHERE와 정렬이 맞고 적은 행을 요청할 때 특히 유용하다. 전체 범위를 읽는 집계에서는 planner가 순차 탐색/명시적 정렬을 선택할 수 있다. [PostgreSQL Indexes and ORDER BY](https://www.postgresql.org/docs/14/indexes-ordering.html)를 기준으로 보며, 위 모든 Sort를 인덱스로 제거할 수 있다고 가정하지 않는다.

## 우선 실행할 3개와 단계

1. **#1 피드 카드의 요약·공유 권한 일괄 조회.** 실제 함수 호출에서 반복 SQL을 확인했고 여러 핵심 화면에 공통으로 영향을 준다. 먼저 공유 대상/중복 조회를 일괄화하고, 별도 단계에서 likes/comments/current hide 로딩을 정리한다. 기존 policy/상호작용 결과를 유지하는 작은 변경으로 시작할 수 있다.
2. **#3 통합 문자열 검색의 인덱스 검증과 적용 계획.** 공개 사용자 기능이며 전체 데이터 증가와 직접 연결된다. 검색 의미·정확한 COUNT·번호 페이지는 유지하고, 대표 문자열/선택도별 계획을 먼저 비교해 인덱스 대상을 좁힌다. 이때 필요한 인덱스 migration은 감사 검토 후 같은 브랜치의 후속 작업이다.
3. **#8 알림의 유형별 연관 일괄 로딩.** 수신자 이력 증가에 대한 상한이 없고 현재 preload만으로 후속 관계 조회를 막지 못한다. 우선 현재 읽음 동작을 유지한 채 N+1을 줄이고, 전체/표시분 읽음 처리와 cursor 경계를 정한 뒤 pagination을 별도 단계로 진행한다.

다음은 #5 발견의 반복 후보 선정, #7 댓글 감사 일괄화, #9 thread 검색/최신 댓글 접근을 각각 독립 단위로 진행한다. 기존 관리자 status 수정은 유지하되 관련 조합 검증부터 보강한다. 정책 경계가 큰 #2의 범용 scope 재작성, #6의 DnD/전체 장서 pagination, #10의 마지막 활동 SQL 전환을 한 리팩터링에 합치지 않는다.

후속 완료 기준은 (a) 동일 권한/동작 결과, (b) 조회 횟수·로딩 행 수 또는 계획 입력 감소, (c) 대표 데이터에서 실제 시간/버퍼 개선 확인이다. 코드가 짧아지거나 추정 비용만 낮아지는 것을 최종 성공 기준으로 삼지 않는다. 현재 감사에는 정책을 바꿔 해결해야 하는 확정 충돌은 없으며, COUNT/읽음 처리/추천 저장소/전체 이동에 관한 **후속 설계 선택**이 남아 있다.

## 당장은 수정하지 않아도 되는 영역

- **P3 — FeedPage 자체:** 소스별 21개, 최종 20개와 signed cursor로 깊은 OFFSET을 피하고 있다. 피드 전체를 새 pagination framework나 SQL UNION 기반으로 바꿀 근거는 부족하다. #1의 연결 데이터 로딩과 #2의 필터/인덱스는 별도로 개선한다.
- **P3 — 독서 상태/다시짹 건수의 일괄 준비:** `prepare_current_reading_states_for`는 페이지 user/book 집합과 visibility로 제한해 조회한다. 두 IN 목록이 쌍이 아닌 조합을 허용하더라도 현재 페이지 크기로 제한된다. `prepare_visible_requote_counts_for`는 원문 ID별 GROUP BY와 작성자용 제한 scope를 사용한다. 정확한 가시성과 원문 작성자 예외를 단순 counter cache로 대체하지 않는다. 이 scope의 중복 비용은 #2에서 관찰한다.
- **P3 — Group 카드 미리보기:** `GroupMembership.card_previews_for`는 대상 Group별 window COUNT/순위로 3명만 반환하고 avatar를 일괄 로드한다. 회원 전체 window 처리는 필요하지만 카드별 COUNT+전체 회원 로딩으로 퇴행시키지 않는다. 큰 Group에서 관찰되면 membership 인덱스/COUNT 분리를 검토한다.
- **P3 — 정확한 태그 탐색:** tag 이름 unique와 연결 FK 인덱스가 있다. substring/tag 검색을 합치거나 검색 엔진을 추가할 필요는 없다. 인기 태그 전체 집계(#4)와 구분한다.
- **P3 — 책 identity와 import 조회:** canonical ISBN/external URL의 partial unique, BookshelfEntry의 `(user_id,book_id)` unique가 있다. 현재 식별 조회에 대한 인덱스 부재는 보이지 않는다. 외부 API 지연은 SQL 감사와 구분한다.
- **P3 — 기본 관리자 inventory와 User timeline:** scalar COUNT/EXISTS는 관련 FK 인덱스가 있고 페이지 30/50/100개로 결과가 제한된다. User timeline은 조건별 Jjaek/Comment UNION 후 정렬·페이지화한다. 누적 이력의 COUNT/Sort와 deep OFFSET은 관찰 대상이지만 전부 새 추상화로 바꾸지 않는다. 부분 문자열 인덱스는 #3, 마지막 활동의 전체 이력 입력은 #10과 함께 다룬다. 정확한 총수·페이지 번호 제거는 기존 moderation spec 변경이 필요하다.

## RSpec 간헐적 지연은 별도 조사한다

이번 단계에서 RSpec을 실행하거나 지연을 재현하지 않았다. 개발 DB의 작은 계획과 테스트 DB의 통계/연결·데이터는 다르다. 기존 status SQL의 개선만으로 지연이 해결되었다고 결론낼 수 없다.

- **부팅과 example 분리:** 다음 허용된 검증에서 같은 example을 고정해 boot/load 시간과 실행 시간을 구분한다. cold/warm Bootsnap, `CI`에 따른 eager loading, schema 유지 확인을 따로 기록한다. `rails_helper`는 `maintain_test_schema!`를 수행한다.
- **SQL 실행과 대기 분리:** 지연이 실제 발생한 순간의 `sql.active_record` duration/쿼리 수와 request/render 시간을 비교한다. 동시 테스트·console·server의 DB 연결, connection pool 대기, `pg_stat_activity.wait_event`와 blocking PID를 확인한다. 감사용 READ ONLY EXPLAIN은 lock 대기나 Ruby 시간을 설명하지 못한다.
- **fixture 준비와 실제 GET 분리:** 해당 request example은 사용자/책/동아리/댓글 생성, hide와 tombstone 등 여러 서비스 실행 후 다수의 GET/HTML 파싱을 수행한다. 예시 전체 시간이 특정 SELECT 시간과 같지 않다. ActiveRecord callback, 태그 동기화, 알림/transaction 경계, Nokogiri 파싱도 분리해 본다.
- **외부/비SQL 작업은 관찰된 경우 추적:** 테스트의 Cable adapter는 `test`, Devise stretches는 test에서 1이다. 임의로 운영 Cable polling이나 높은 bcrypt 비용을 원인으로 단정하지 않는다. Notification의 after-commit badge/메일·job·파일/avatar 작업은 실제 trace에 나타날 때 확인한다. 현재 자료만으로 외부 I/O를 지연 원인으로 지목하지 않는다.
- **측정 방식:** 동일 example/seed·환경, 프로세스 동시 실행 유무, SQL cache 여부와 지연 시각을 함께 남긴다. 안정적인 성능 단정을 위해 여러 실행을 비교하되, 고정 wall-clock threshold를 기능 RSpec에 넣지 않는다. 권한·상태·결과 회귀는 일반 spec, SQL 횟수·행 수·시간/버퍼는 좁은 성능 관찰로 구분한다.

아래는 **후속 코드 변경 후 사용자가 실행할 예시 명령**이며 이번 감사에서는 실행하지 않았다. 처음에는 변경된 기능에 해당하는 파일만 고른다.

```sh
# 기존 admin status 변경과 공통 thread 계약
bundle exec rspec spec/queries/admin/group_content_thread_query_spec.rb spec/queries/groups/content_thread_query_spec.rb spec/requests/admin/groups_spec.rb spec/requests/group_content_inventory_spec.rb

# 피드 요약/공유 권한을 변경한 단계
bundle exec rspec spec/policies/jjaek_feed_policy_spec.rb spec/policies/group_jjaek_policy_spec.rb spec/requests/homes_spec.rb spec/requests/feed_pagination_spec.rb spec/requests/group_sharing_requotes_spec.rb

# 해당 기능을 변경한 단계에만 선택
bundle exec rspec spec/requests/searches_spec.rb
bundle exec rspec spec/requests/notifications_spec.rb spec/requests/group_lifecycle_notifications_spec.rb spec/requests/group_membership_notifications_spec.rb

# 간헐적 지연 분석: 문제가 난 단일 example/line과 seed를 고정
bundle exec rspec spec/requests/admin/groups_spec.rb --example 'filters Group content and preserves filters across navigation' --profile 10 --seed 12345
```

## 재현 절차와 이번 산출물

후속 계획 비교는 개발 환경을 명시하고 연결 DB명을 먼저 확인한 뒤, 같은 사용자/Group/필터·정렬·page size로 relation을 만든다. 관리자 변경 전 비교 시 HEAD의 query를 작업본에 덮어쓰지 말고 별도 임시 class로 읽는다. ID 비교는 조회만 수행하는 양방향 `EXCEPT`를 사용한다.

```sql
BEGIN READ ONLY;
SET LOCAL statement_timeout = '3s';
SET LOCAL lock_timeout = '1s';
SELECT current_database(); -- checkjjaek4_development인지 확인
-- EXPLAIN (FORMAT JSON) <동일 조건의 relation.to_sql>;
-- (old_ids EXCEPT new_ids) UNION ALL (new_ids EXCEPT old_ids);
ROLLBACK;
```

이번에 추가한 저장소 산출물은 이 문서뿐이다. SQL/계획 수집용 스크립트와 JSON은 `/tmp`에서만 사용했으며 저장소에는 임시 파일을 추가하지 않았다. 대규모 benchmark나 migration·구현은 감사 결과 검토 후 같은 브랜치에서 단계별로 진행한다.
