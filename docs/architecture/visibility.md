# Visibility Architecture

## 목적

이 문서는 checkjjaek4의 Jjaek visibility 구조를 정리하기 위한 architecture 문서다.

이 문서는 아래를 설명한다.

- `public_jjaek`
- `book_friends`
- `private_jjaek`
- 각 visibility의 의미
- 작성 위치별 선택 가능 범위
- 조회 가능 범위
- ReJjaek visibility 제약

visibility는 1차 조건이고, 최종 판단은 policy / policy_scope가 담당한다.

이 문서는 새로운 공개 범위 정책을 정의하지 않는다.
현재 구현은 `docs/architecture/current_system.md`,
목표 상태와 제품 정책은 관련 spec 문서를 기준으로 읽는다.

---

## Jjaek visibility 종류

현재 시스템에서 사용하는 visibility 값은 아래 세 가지다.

- `public_jjaek`
- `book_friends`
- `private_jjaek`

관련 위치:

- `app/models/jjaek.rb`

---

## 각 visibility의 의미

### `public_jjaek`

- 전체 공개를 의미한다

### `book_friends`

- 작성자의 책친구에게 공개되는 범위를 의미한다

### `private_jjaek`

- 작성자 본인만 볼 수 있는 범위를 의미한다

---

## 작성 위치별 선택 가능 범위

### 현재 구현에서 확인되는 범위

`docs/architecture/current_system.md` 기준으로 현재 문서에서 확인되는 범위는 아래와 같다.

- 내 프로필
  - `public_jjaek`
  - `book_friends`
  - `private_jjaek`
- 남의 프로필
  - `public_jjaek`
  - `book_friends`

현재 구현 요약 문서에는 홈과 책 상세의 선택 가능 범위가 별도 표로 정리되어 있지 않다.
그 상세는 실제 controller / policy / form 코드와 관련 spec을 함께 확인해야 한다.

### 목표 상태

visibility 선택 규칙의 목표 상태는 `docs/specs/bookjjaek_reboot_spec.md`를 우선 기준으로 본다.

---

## 조회 가능 범위

### 현재 구현

현재 구현 기준:

- Jjaek의 실제 조회 가능 여부는 visibility 값만으로 끝나지 않는다
- 관계와 화면 문맥, `policy_scope`, quoted Jjaek 가시성 재검사가 함께 작동한다
- 프로필과 책 상세는 같은 방식으로 읽기 범위를 계산하지 않는다

필요하면 권한 구조 상세는 `docs/architecture/authorization.md`를 함께 본다.

### 목표 상태

조회 가능 범위의 목표 규칙은 `docs/specs/social_relationships_mvp.md`를 기준으로 본다.

---

## ReJjaek visibility 제약

현재 구현과 목표 정책에서 공통으로 반복되는 핵심 제약은 아래와 같다.

- private 원문은 인용할 수 없다
- ReJjaek은 원문보다 넓은 공개 범위를 가질 수 없다
- quoted Jjaek 접근 권한은 조회 시 다시 검사한다
- 원문 자체가 ReJjaek이면 중첩 ReJjaek은 허용하지 않는다

관련 위치:

- `app/models/jjaek.rb`
- `app/policies/jjaek_policy.rb`

---

## 댓글 / 좋아요와 visibility의 관계

현재 구현 기준:

- 댓글과 좋아요는 부모 Jjaek을 볼 수 있는 사용자만 가능하다
- 즉, 상호작용 가능 범위는 부모 Jjaek visibility와 접근 가능 범위를 넘을 수 없다
