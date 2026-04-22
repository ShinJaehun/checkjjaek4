# RSpec Strategy for checkjjaek4

## 상태

현재 테스트 우선순위는
`docs/specs/bookjjaek_reboot_spec.md`와 `docs/reboot/reboot_plan.md`
를 기준으로 해석한다.

---

## 목적
이 문서는 `checkjjaek4`에서 테스트를 어떤 철학과 우선순위로 추가할지 정리한다.

---

## 기본 철학

이 프로젝트의 테스트 목적은 다음과 같다.

- 핵심 기능 변경 시 자신감을 주는 안전망 제공
- 리팩토링 비용 절감
- 권한/정책/상태 전이 규칙 고정
- 수동 클릭 테스트 의존도 감소

Coverage 수치 자체를 목표로 삼지 않는다.

---

## 스타일 원칙

- 읽기 쉬운 테스트를 우선한다.
- 테스트 이름은 동작을 설명하는 문장으로 작성한다.
- guest / authenticated / member / non-member / owner 같은 context를 분명히 나눈다.
- 테스트 데이터는 가능한 사용 위치 가까이에 둔다.
- DRY보다 DAMP(설명적이고 의미가 드러나는 테스트)를 우선한다.
- `before`, `let`, `shared_context`, `support`는 필요할 때만 사용한다.

---

## 우선순위

### 1순위
- 인증 이후 기본 진입 흐름
- Pundit policy / policy_scope 핵심 분기
- Book 생성/재사용과 BookshelfEntry 생성/재사용 흐름
- BookshelfEntry 상태/스티커 저장 규칙
- Jjaek 생성 / 수정 / 삭제 / 조회 request 흐름
- ReJjaek 공개 범위 규칙
- ReJjaek 조회 시 원문 접근 권한 재검사 규칙
- Comment / Like 핵심 request 흐름
- `볼 수 있는 사람만 댓글/좋아요 가능` 규칙
- Book 검색과 `서재에 담기` import 흐름
- Turbo / HTML 응답의 핵심 성공/실패 흐름

### 2순위
- 홈의 Jjaek-only 피드 노출 규칙
- books/:id 한 화면 두 form 흐름
- locale이 개입되는 핵심 사용자 메시지
- 외부 API 연동 실패 시의 안전한 처리

### 후순위
- 세세한 뷰 구조
- 자주 바뀌는 마크업
- 스타일/문구 중심 테스트
- BookActivity
- Group / GroupMembership
- 여러 책장
- 학생 계정 전환

---

## 권장 테스트 레벨

### model / service spec
다음에 우선 사용한다.

- 상태 전이
- 불변식
- 경계값
- 도메인 규칙
- 외부 API 응답 정규화
- 입력값 검증

예시:
- BookshelfEntry 상태 규칙
- BookshelfEntrySticker 중복 방지
- Jjaek visibility / ReJjaek 규칙
- Book 검색 결과 매핑 규칙

### policy spec
다음에 우선 사용한다.

- 역할별 허용/금지
- visible / non-visible 분기
- policy_scope 범위

예시:
- JjaekPolicy
- ReJjaek 관련 policy / scope 규칙
- CommentPolicy
- LikePolicy
- BookFriendshipPolicy
- Book 관련 조회/연결 policy
- UserPolicy

### request spec
다음에 우선 사용한다.

- 인증/인가
- 성공/실패 응답
- redirect / forbidden / not found 흐름
- create/update/destroy 핵심 엔드포인트
- Turbo / HTML 응답 분기

예시:
- 서재에 담기 / 서재 수정
- Jjaek 작성/수정/삭제
- ReJjaek 작성/조회
- 댓글 작성
- 좋아요 생성/취소
- 책 검색 요청
- 인증 후 landing path

### system spec
정말 필요한 핵심 happy path에만 제한적으로 사용한다.

예시:
- 로그인 후 기본 진입
- 책 검색 후 서재에 담기
- 책 상세에서 상태 저장 + Jjaek 작성

---

## 현재 단계에서 먼저 고정할 것

초기 재구축 단계에서는 아래를 먼저 테스트로 고정한다.

1. 인증 이후 기본 landing path
2. Pundit 도입 후 authorize / policy_scope의 핵심 분기
3. BookshelfEntry / BookshelfEntrySticker의 생성과 수정
4. Jjaek 중심 구조에서의 생성/조회 권한
5. ReJjaek 공개 범위와 원문 접근 권한 재검사 규칙
6. 댓글/좋아요의 visibility 기반 허용 규칙
7. Book 검색 결과를 서재와 연결하는 최소 흐름

---

## 현재 단계에서 테스트로 바로 고정하지 않아도 되는 것

- 세세한 partial 구조
- Tailwind class
- 문구의 정확한 HTML 배치
- 레거시와 1:1 동일한 DOM 구조
- 아직 도입하지 않은 `BookActivity`, 그룹, 여러 책장 관련 기능

---

## 피해야 할 것

- 구현 세부사항에 과하게 결합된 테스트
- 저가치 HTML 구조 고정 테스트
- request/system 테스트의 과도한 중복
- helper/shared_context 남용으로 읽기 어려워진 테스트
- 레거시 구조를 그대로 따라가는 테스트
- 아직 확정되지 않은 spec을 성급히 테스트로 박아두는 것

---

## 문서와 테스트의 관계

- 테스트는 `docs/specs/*.md`에 합의된 요구사항을 기준으로 작성한다.
- spec이 아직 없는 기능은 먼저 spec 초안을 만들고 그 뒤 테스트를 설계한다.
- migration/legacy 문서는 “왜 이렇게 바뀌었는가”의 근거로 참고하되,
  실제 테스트 기준은 현재 `checkjjaek4`의 spec과 architecture 문서에 둔다.

---

## 초기 테스트 작성 순서 제안

### Step 1
- 인증 이후 landing path request/spec
- 기본 policy spec

### Step 2
- BookshelfEntry / BookshelfEntrySticker model + request spec
- Book 검색 / `서재에 담기` import request spec

### Step 3
- Jjaek request + policy spec
- Comment / Like request + policy spec

### Step 4
- ReJjaek request + policy spec
- ReJjaek 조회 시 원문 접근 권한 재검사 spec

### Step 5
- books/:id 한 화면 두 form 흐름 spec
- 꼭 필요한 최소 system spec

---

## 한 줄 기준

테스트는 레거시를 복제하기 위한 장치가 아니라,
`checkjjaek4`의 현재 도메인 규칙과 사용자 흐름을 안전하게 고정하는 장치다.
