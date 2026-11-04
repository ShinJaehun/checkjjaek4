# 콘텐츠 정합성 감사 — 2026-11-04

대상 브랜치: `feature/content-integrity-hardening`. 시작 시 작업 트리는 깨끗했다.
사용자 승인에 따라 정적 분석과 확정적 수정을 수행했다. RSpec, 브라우저, migration,
운영 DB 조회 및 성능 측정은 실행하지 않았다. 아래 재현 경로는 코드 분석 결과이며 실행 검증 결과가 아니다.

## 기준과 확인 범위

`AGENTS.md`, `spec-driven-rails-development/SKILL.md`, 추천짹 canonical spec
`docs/specs/book_recommendation_jjaeks.md`, `current_system.md`의 추천·콘텐츠·피드 설명,
visibility/authorization architecture, `group_sharing_requotes.md`, `requotes_mvp.md`의
접근·삭제 경계와 RSpec 전략을 기준으로 확인했다. 이번 사용자의 명시적 감사·수정·diff 확인
승인을 적용했고, 추가 승인이나 commit은 수행하지 않았다.

| 영역 | 확인한 경로 및 판단 |
| --- | --- |
| 생성·정합성 | `Jjaek`, `JjaekRecommendation`, `Book`, `RecommendationSelection`, 추천 선택/게시 controller, schema. 선택 순서·중복 제거·1~5권·혼합 문맥 거부·외부 캐시의 사용자 바인딩과 만료·신규 Book 저장 경계를 확인했다. |
| 수정·삭제 | 게시 후 책/유형 변경은 strong parameters로 차단한다. hard delete는 연결을 제거하고 Book을 보존한다. 댓글이 있는 tombstone은 추천 연결을 보존하지만 `_jjaek_body`가 책 목록과 본문을 표시하지 않는다. 개인 A의 private 전환과 B/C의 원문 식별 정보 제거는 공통 삭제 처리를 따른다. |
| 홈·프로필 | `HomeFeedContext`, `ProfileContext`, `JjaekPolicy::FeedScope`(356행), `ProfileScope`(332행). 홈은 개인 게시물만, 프로필은 기존 사용자/운영자 경계를 사용한다. 추천 flag로 visibility를 우회하는 별도 분기는 찾지 못했다. |
| 책 상세 | `ApplicationController#prepare_book_show_read_context`(78행): 단일 book 조건과 추천 연결 ID subquery를 OR로 결합한 후 BookScope 또는 GroupContentScope를 적용한다. 추천 책 수만큼 행을 복제하는 JOIN이 아니다. BookScope(281행)의 개인 추천짹은 public만 포함하는 기존 명세를 유지했다. |
| 동아리 | `GroupShowContext`, `GroupsController`의 GroupActivityScope, 선택/작성 authorize 및 게시 시 group lock 안의 재인가. 비회원·회원 자격 상실 경계를 기존 정책으로 유지한다. |
| 검색·운영 조회 | `SearchesController#results_for`의 SearchScope와 태그 ID subquery, 별도 추천 유형을 확인했다. 관리자 콘텐츠는 `Admin::UsersController#content`의 authorize와 AdminInventoryScope를 거친다. 관리자용 전체 visibility는 명시적 운영 권한이며 일반 피드로 확장하지 않는다. |
| 원문 | `JjaekPolicy::Scope`의 원문 ID subquery와 `view_quoted_source?`, `_quoted_jjaek` 호출 경계를 확인했다. 원문 권한 상실과 실제 삭제를 구분한다. |
| SQL·메모리 | `FeedPage`는 각 입력 relation을 21개로 제한하고 created_at/id cursor를 사용한다. `ApplicationController#prepare_recommendation_books_for`(163행)는 페이지 레코드와 인용 원문의 추천 책을 일괄 preload한다. 검색도 제한된 결과에 같은 preload를 호출한다. 추천 FK/고유 인덱스와 책 상세 subquery 조건이 대응한다. 운영 목록은 책 목록을 렌더하는 공통 카드와 다른 요약 UI다. |
| Turbo·Stimulus | permanent 창, 선택 fields, 검색/추가/삭제 Stream, 게시 실패/성공, close, 단계 전환, 모바일 max-height markup을 추적했다. 실제 focus·스크롤·복원 동작은 브라우저 확인이 필요하다. |

위 조회 경로에서 추천짹 도입으로 새로 발생한 비공개 콘텐츠 노출 결함(P0)은 확인하지 못했다.
이는 전체 권한 시스템의 무결성을 실행 검증했다는 뜻은 아니다.

## 발견 및 반영

### P1 — 유효하지 않은 선택으로 게시하면 작성 내용 소실

- 근거: `app/controllers/jjaeks_controller.rb:235`의 `build_recommendation_jjaek`와
  `app/controllers/concerns/recommendation_selection.rb:21`. 기존 코드는 책 삭제·외부 참조 만료·위변조 시
  본문을 할당하기 전에 검색으로 redirect했다. HTML에서는 이유·visibility를 잃고 Turbo에서도
  작성창에 실패를 표시하는 명세와 달랐다.
- 수정: 게시에서는 redirect하지 않고 선택을 안전하게 비운 뒤, 작성 권한을 확인하고 본문·visibility를
  유지한 writing 단계에 422를 반환한다. GET 선택 오류의 기존 redirect는 유지한다.
- `spec/requests/recommendation_jjaeks_spec.rb:31`에 HTML/Turbo 입력 보존 및 세 테이블 무변경 검증을
  추가했다. 기존 위변조/없는 책 테스트의 저장 거부 검증을 보존하고 응답 기대를 422로 변경했다.
- 기존 canonical의 실패 입력 보존 정책에 맞춘 수정이다. 오류 선택을 부분 게시하지 않는다.

### P1 — 이전 작성의 늦은 응답이 새 창을 덮어씀

- 근거: `app/javascript/controllers/recommendation_composer_controller.js`의 기존 `guardStream`은
  요청 시점이 아니라 응답 Stream 도착 시점의 panel/revision을 잡았다. A 선택 요청 → 닫기 → B 작성
  → A 응답 순서이면 A 응답을 B의 현재 상태로 받아들일 수 있었다. 게시 성공의 완료 Stream도 같은 대상이다.
- 수정: connect/close에서 DOM에 작성 수명 식별자를 유지·교체하고, `prepareRequest`(140행)에서 요청
  header로 보낸다. `RecommendationSelection#echo_recommendation_revision`(10행)이 제한된 형식만
  응답에 돌려준다. `guardResponse`(148행)는 capture 단계에서 다른 수명의 응답을 차단해 Turbo
  Stream 처리가 시작되기 전에 제외한다. 기존 렌더 예약 시점의 guard도 유지한다.
- 새 저장소나 DB 초안을 추가하지 않았다. 이 header는 화면 응답 식별용이며 권한 판단에 사용하지 않는다.
- request spec 48행은 선택 및 게시 실패 응답의 식별자 반환을 검증한다. 실제 응답 순서 차단은 아래
  브라우저 절차로 검증해야 한다.

### P1 — 여러 선택 폼의 동시 제출로 선택 유실

- 근거: 기존 `prepare`는 각 폼이 동일한 현재 selected_books를 보내도록 했다. 서로 다른 추가 폼의
  요청 A/B가 같은 목록을 바탕으로 응답하면 마지막 응답이 앞선 추가를 지울 수 있었다. 선택 요청 중
  게시해도 아직 반영되지 않은 목록을 게시할 수 있었다.
- 수정: Stimulus `prepare`(102행)에서 선택 mutation/게시가 진행 중이면 다음 관련 제출을 막고,
  `submitted`(136행)에서 해당 폼의 submit-end에 해제한다. close는 이전 작업의 잠금을 해제한다.
  첫 요청 종료 후 다시 선택·게시할 수 있다. 요청 큐나 서버 초안을 도입하지 않았다.
- 네트워크 지연 및 오류 뒤 잠금 해제는 브라우저 검증 항목이다.

### P2 — 모호한 책 ID를 단일 선택으로 수용

- 근거: `app/controllers/recommendation_books_controller.rb:58`의 `book_for_selection`은
  `Book.find_by(id: params[:book_id])`에 배열/문자열을 그대로 전달했다. 배열은 IN 조건,
  숫자 뒤 문자열은 정수 coercion으로 의도하지 않은 책 선택이 가능했다.
- 수정: 기존 selected_books ID와 같은 양의 정수 문자열만 허용한다. 실패 시 기존 선택을 유지하고
  기존 재선택 안내를 표시한다. request spec 18행에서 배열과 숫자+문자 입력 및 데이터 무변경을 검증한다.

### P2 — 선택 정규화 중복

`RecommendationSelection`의 연속된 map/reject/uniq 중 두 번째 동일 처리를 제거했다.
동작 변경이나 성능 개선 수치 주장은 없다.

## 데이터 저장과 남은 위험

- 정상 게시의 `Jjaek#save`와 autosave 연결은 하나의 ActiveRecord 저장 트랜잭션에 참여한다.
  child의 신규 Book 저장도 그 안에서 처리된다. group 경로는 기존 with_lock을 사용한다.
  0권/6권·본문 오류는 부모 validation에서 거부한다. DB는 FK, NOT NULL, book/position 고유성과
  position >= 0을 강제한다(`db/schema.rb:254`). 별도 transaction/service를 추가할 근거는 찾지 못했다.
- P2 후속: `JjaekRecommendation` 직접 create/destroy는 부모의 1~5권 validation을 실행하지 않는다.
  예를 들어 부모를 거치지 않고 position 5로 여섯 번째 연결을 만들거나 마지막 연결만 삭제할 수 있다.
  현재 웹 요청은 이 쓰기 경로를 제공하지 않는다. 임의 모델 쓰기/DB 쓰기까지 invariant를 보장하려면
  부모 잠금·삭제 lifecycle·DB 제약 적용 범위를 함께 정해야 하므로 이번에 callback/trigger를 추가하지 않았다.
- P2 후속: 새 부모에 동일 position의 sibling 둘을 build하면 child uniqueness 검증만으로 sibling을
  비교하지 못하고 DB 고유 제약에서 실패할 수 있다. 현재 게시 controller는 each_with_index로 위치를
  생성하므로 요청 경로에서 발생하지 않는다. 추후 연결 편집 경로 도입 전 부모 수준 검증을 검토한다.
- tombstone에 남는 추천 연결은 표시되지 않지만 Book 삭제 제한에도 남는다. 보관 기간/물리 삭제는
  명세에서 정하지 않았으므로 임의 삭제하지 않았다.
- 브라우저 제출 잠금은 서버 idempotency가 아니다. 네트워크 재전송·여러 탭·직접 POST 중복 생성은
  기존과 같이 가능하다. 게시 멱등 키가 필요하면 별도 저장 정책과 만료 범위를 정해야 한다.
- 이미 서버가 접수한 게시는 창을 닫아도 취소되지 않는다. 이전 완료 응답의 새 창 개입을 차단하는 수정이며
  서버 저장 취소를 제공하지 않는다.
- 같은 작성 내 검색 pagination과 선택 변경이 겹치는 복원, 뒤로/앞으로, 느린 모바일 환경은 실행 확인이 남는다.
- 선택 입력 전체를 읽은 뒤 중복 제거·최대 수를 확인하는 기존 흐름은 유지했다. 매우 큰 forged 배열은
  정상 5권 UI보다 많은 조회/메모리를 쓸 수 있다. 정상 중복 제거 정책과 요청 상한 정책을 구분해 후속 검토한다.
- SQL 횟수·실행 계획·RSS는 측정하지 않았다. FeedScope의 기존 관계 ID 배열이나 운영 목록 count를
  추측으로 다시 작성하지 않았고 새 인덱스도 추가하지 않았다.

## 검증 인계

실행한 확인: `git diff --check`. RSpec/브라우저는 실행하지 않았으므로 통과 여부는 미확인이다.

우선 실행:

```sh
bundle exec rspec spec/requests/recommendation_jjaeks_spec.rb spec/models/jjaek_recommendation_spec.rb
```

조회·삭제 호환성 확인:

```sh
bundle exec rspec spec/policies/jjaek_policy_spec.rb spec/policies/jjaek_feed_policy_spec.rb spec/policies/group_jjaek_policy_spec.rb spec/models/jjaek_spec.rb spec/requests/admin/jjaeks_spec.rb
```

브라우저 절차:

1. 개인/동아리 창에서 1~5권 선택, 제거 후 재추가, 이유·private 설정, 단계 왕복, 재검색·다음 페이지를 확인한다.
2. 외부 선택 후 캐시 만료 또는 선택 Book 삭제 상태에서 게시한다. 이유·visibility가 writing 단계에 남고
   재선택 안내와 빈 선택 목록이 표시되는지 확인한다. 유효한 책을 재선택해 게시한다.
3. 네트워크를 느리게 설정하고 추가 요청 직후 닫은 다음 다른 동아리/개인 창을 연다. 이전 응답이
   책·동아리 문맥·본문·화면 이동을 바꾸지 않는지 확인한다. 초기 Frame 로드와 게시 완료도 같은 순서로 확인한다.
4. 추가/삭제 중 다른 추가·삭제·게시를 빠르게 누른다. 첫 응답까지 두 번째 제출이 억제되고 이후 다시
   동작하는지 확인한다. 네트워크 실패 뒤에도 재시도가 가능한지 확인한다.
5. 일반 Turbo 이동과 뒤로/앞으로에서 선택·입력 유지, 메뉴/로고/일반 책 검색 종료 후 빈 창,
   모바일 하단 창의 스크롤과 배경 검색 결과 조작을 확인한다.
6. outsider 계정으로 private 추천의 상세·프로필·책 타임라인·태그/텍스트 검색·다시짹을 확인한다.
   동아리 탈퇴 후 원문/인용 조회와 게시 제한, 원문 삭제 후 A/B/C 표시, tombstone의 책 목록 비노출을 확인한다.
7. 필요 시 동일 데이터·페이지 크기로 SQL 로그/실행 계획과 RSS를 수집한다. 특히 추천 1권/5권,
   추천 원문을 인용한 페이지에서 카드 수에 비례하는 추천 책 조회가 없는지 비교한다.

수정 파일: controller 2개, 공통 selection concern, Stimulus controller, 창의 event binding partial,
추천짹 request spec, 이 보고서. 공개 범위 정책·schema·locale·저장 모델은 변경하지 않았다.
