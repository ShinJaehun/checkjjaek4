# Book Search MVP

## 상태

이 문서는 현재 리부트 범위와 연결된 **활성 하위 spec**이다.
다만 독립 기준 문서가 아니라, 아래 두 문서를 전제로 해석한다.

- `docs/specs/bookjjaek_reboot_spec.md`
- `docs/reboot/reboot_plan.md`

---

## 목적

`checkjjaek4`의 다음 구현 단위는 외부 책 검색 API를 이용해
사용자가 책을 찾고 결과를 확인할 수 있는 최소 검색 흐름을 만드는 것이다.

이 단계의 목표는 다음과 같다.

- 책짹의 핵심 정체성인 “책 검색” 기능을 먼저 복원한다.
- 레거시 `checkjjaek3`의 책 검색 흐름을 참고하되, 구현은 현재 공식 API 문서를 기준으로 다시 정리한다.
- 검색 기능을 먼저 작게 고정하되, 현재 리부트 흐름에서는 `Book` / `BookshelfEntry` / `Jjaek`와 연결되는 방향을 따른다.

---

## 포함 범위

- Kakao Developers Daum Search Book API 기반 책 검색
- 검색 입력 폼
- 검색 결과 목록 표시
- 검색 결과 pagination
- 최소한의 검색 결과 정규화/표준화
- 빈 결과 처리
- 외부 API 실패 시 안전한 사용자 메시지 처리
- 로그인 사용자 기준 검색 접근
- 얇은 adapter/service 계층 도입
- 검색 결과에서 `책 상세 보기` 진입
- 검색 결과에서 `서재에 담기` import 동작

---

## 핵심 규칙

- 책 검색은 현재 시점의 Kakao Developers 공식 문서를 기준으로 구현한다.
- 책 검색 엔드포인트는 `GET https://dapi.kakao.com/v3/search/book`를 기준으로 한다.
- 인증은 Kakao REST API 키를 이용한 요청 헤더 방식으로 처리한다.
- Kakao 책 검색 API의 `page`, `size`, `meta.is_end`, `meta.pageable_count`를 사용한다.
- 다음 페이지 존재 여부는 우선 `meta.is_end`를 기준으로 판단한다.
- `meta.pageable_count`는 결과 수 표시와 보조 판단에 사용한다.
- `page`는 query string으로 유지한다.
- 검색 폼 제출 시에는 `page` 값을 넘기지 않고, controller에서 기본값 1로 처리한다.
- pagination 링크를 클릭할 때만 `page` 값을 query string으로 유지한다.
- `page` 값이 비정상이면 1로 보정한다.
- `size`는 앱 내부 상수로 고정하며, MVP 기본값은 10으로 둔다.
- 외부 API 호출 코드는 controller에 직접 흩뿌리지 않고, 얇은 adapter/service 계층에서 감싼다.
- 검색 결과는 화면 표시용 데이터로 먼저 사용한다.
- 검색 결과는 최소한 아래 정보를 우선 노출한다.
  - 제목
  - 저자
  - 출판사
  - 썸네일
  - ISBN
  - 소개글 일부
- 검색 결과의 책 썸네일은 공통 책 썸네일 partial을 사용한다.
- 책 검색 결과에서는 표지 전체가 자연스럽게 보이는 것을 우선한다.
- 검색 결과 썸네일은 Kakao API 응답의 thumbnail URL을 우선 사용한다.
- 검색 결과의 기본 진입은 `책 상세 보기`다.
- 검색 결과의 `서재에 담기`는 **외부 책 정보를 우리 서비스 DB/서재로 가져오는 import 동작**이다.
- `서재에 담기`는 아래를 포함할 수 있다.
  - `Book` 생성 또는 재사용
  - 현재 사용자의 `BookshelfEntry` 생성 또는 재사용
  - 기본 대표 상태는 `읽고 싶어요(wish)`로 시작
- 이미 담긴 책이면 중복 생성하지 않고, 기존 `Book` / `BookshelfEntry`를 재사용한다.
- 검색 결과의 `책 상세 보기`는 내부 `books/:id` 진입을 의미한다.
- `책 상세 보기`만으로는 `BookshelfEntry`를 생성하지 않는다.
- 따라서 검색 결과에서 책 상세로 먼저 들어간 사용자는
  책 정보와 visible Jjaek은 읽을 수 있지만,
  상태/스티커 변경과 Jjaek 작성은 먼저 `서재에 담기` 후 가능하다.
- 검색 결과에서 직접 `Jjaek`를 작성하지 않는다.

---

## 제외 범위

- `BookActivity` 생성
- 검색 결과에서의 direct Jjaek 작성
- 그룹과의 결합
- 태그/추천/고급 검색
- 메시지/사진 전용 모델
- 검색 결과 캐싱/최적화
- 쿼터 초과 대응의 고급 운영 기능
- 무한 스크롤
- Turbo Stream 기반 결과 append
- 숫자 페이지 전체 목록 UI

---

## 라우트 / 화면 방향

- 책 검색은 별도 화면 또는 명확한 검색 진입점에서 시작한다.
- 첫 단계에서는 별도 책 검색 화면을 기준으로 한다.
- 검색은 `GET` 요청과 query string 기반 흐름을 사용한다.
- 첫 단계에서는 아래 흐름만 만족하면 충분하다.
  1. 로그인 사용자가 검색어를 입력한다.
  2. 외부 API로 책 검색을 요청한다.
  3. 결과 목록을 렌더링한다.
  4. 사용자는 결과에서 `책 상세 보기` 또는 `서재에 담기`를 선택할 수 있다.
  5. 결과가 없으면 빈 상태 메시지를 보여준다.
  6. API 실패 시 안전한 오류 메시지를 보여준다.
  7. 결과가 더 있으면 다음 페이지로 이동할 수 있다.
  8. 2페이지 이후에는 이전 페이지로 이동할 수 있다.
- pagination은 GET query string 기반으로 구현한다.
- MVP에서는 `이전` / `다음` 링크만 제공한다.
- legacy `checkjjaek3`처럼 숫자 페이지 범위를 직접 계산하는 UI는 후속으로 미룬다.

---

## 구현 원칙

- 현재 공식 Kakao Developers 문서를 기준으로 요청 파라미터와 인증 방식을 다시 확인한다.
- 앱 내부에서는 외부 API 의존을 직접 controller에 넣지 않는다.
- service 또는 adapter는 작고 명확하게 유지한다.
- 기본 검색 대상은 제목(`target=title`)으로 시작한다.
- controller는 `query`와 `page`를 정규화해 service에 넘긴다.
- service는 `page`, `size`를 adapter에 넘기고, 결과와 meta를 함께 반환한다.
- adapter는 Kakao API의 `page`, `size`, `is_end`, `pageable_count` 구조를 그대로 활용한다.
- 문자열은 처음부터 locales를 고려한다.
- Turbo 응답 최적화는 이번 spec의 필수 범위가 아니다.
- 지금 단계에서는 “검색이 된다”를 먼저 고정하되,
  리부트 기준에서는 검색 결과를 `Book` / `BookshelfEntry` 흐름과 연결할 수 있어야 한다.
- Kakao REST API 키는 서버 측 설정값으로 관리한다.
- 키 조회와 외부 요청 처리는 controller가 아니라 adapter/service 계층에서 담당한다.

---

## 테스트 기준

- 비로그인 사용자는 책 검색 기능에 접근할 수 없다.
- 로그인 사용자는 검색어로 책을 검색할 수 있다.
- 검색 결과가 있으면 결과 목록이 정상 표시된다.
- 검색 결과가 더 있으면 `다음` 링크가 표시된다.
- 마지막 페이지이면 `다음` 링크가 표시되지 않는다.
- 2페이지 이후에는 `이전` 링크가 표시된다.
- pagination 링크는 검색어와 page 값을 유지한다.
- 검색 결과가 없으면 빈 상태 메시지가 표시된다.
- 외부 API 오류가 발생하면 앱이 깨지지 않고 안전한 오류 메시지를 보여준다.
- adapter/service는 응답 데이터를 화면에서 쓰기 쉬운 형태로 정규화한다.
- adapter/service는 Kakao 응답의 `meta.is_end`와 `meta.pageable_count`를 보존한다.
- `서재에 담기`는 `Book`과 `BookshelfEntry`를 생성 또는 재사용한다.
- 이미 담긴 책은 중복 `BookshelfEntry`를 만들지 않는다.

---

## 현재 단계에서 결정하지 않는 것

이번 단계에서는 아래를 일부러 고정하지 않는다.

- 작가 정규화
- `BookActivity` 생성 타이밍
- 검색 결과에서 바로 `Jjaek` 작성까지 허용할지
- ISBN 중복 처리 정책
- 썸네일/소개글을 어느 수준까지 영속 저장할지

이 결정들은 후속 spec에서 다룬다.

---

## 후속 spec 후보

다음 단계 후보는 아래 둘 중 하나다.

- `books/:id` 상호작용 화면 정교화
- `BookActivity` 도입
- 작가 정규화

즉, 이번 spec은
“책을 찾는다”와 “내 서재로 가져온다”를 먼저 고정하고,
그 다음 단계에서
“책 상세에서 어떻게 상호작용하는가”를 정교화한다.
