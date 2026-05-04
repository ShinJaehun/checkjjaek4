# Library Screen Spec

## 목적

Library Screen은 사용자의 전체 서재를 보여주고 관리하기 위한 전용 화면이다.

현재 Bookshelf UI는 프로필 화면 안에서 구현되어 있다.  
하지만 Bookshelf 기능이 다음 범위까지 확장되면서 프로필 화면이 점점 무거워지고 있다.

현재 구현된 Bookshelf UI 범위:

- 책장 탭
- 책장별 책 목록 표시
- select 기반 책 이동
- 일반 책장 생성
- 일반 책장 수정/삭제
- 책장 색상 `color_key`
- 책장 위/아래 순서 변경
- 책장 안 책 목록 정렬

따라서 후속 단계에서는 사용자의 책장/책 목록 관리 기능을 Library Screen으로 분리한다.

---

## 용어

### Library

Library는 사용자의 전체 서재 화면이다.

중요:

- `Library`는 새 DB 모델이 아니다.
- `Library`는 화면/라우팅 개념이다.
- 내부 데이터 모델은 기존 `Bookshelf`와 `BookshelfEntry`를 그대로 사용한다.

### Bookshelf

Bookshelf는 Library 안의 책장이다.

예:

- 내 책장
- 수업 추천
- 방학에 읽을 책
- 친구에게 추천할 책

### BookshelfEntry

BookshelfEntry는 사용자가 특정 책을 자신의 서재에 담은 기록이다.

현재 정책대로 하나의 `BookshelfEntry`는 하나의 `Bookshelf`에만 속한다.

---

## 기본 경로

Library Screen의 기본 경로는 다음으로 한다.

```text
/users/:user_id/library
```

Rails route:

```ruby
resources :users, only: %i[index show] do
  resource :library, only: :show
end
```

Controller:

```text
Users::LibrariesController#show
```

`Library`는 사용자별 하위 화면이라는 의미가 강하므로 `Users::LibrariesController`를 사용한다.

---

## 화면 배치 원칙

### 현재 단계

현재 Bookshelf UI는 프로필 화면 안에 있다.

### 후속 목표

Library Screen을 도입한 뒤에는 역할을 나눈다.

프로필 화면:

- 사용자 정보
- 최근 활동
- 공개 가능한 책 목록 요약
- self / accepted book_friend에게만 “서재 보기” 링크 제공

Library Screen:

- 책장 탭
- 책장별 책 목록
- 책 이동
- 일반 책장 생성
- 일반 책장 수정/삭제
- 책장 색상
- 책장 순서 변경
- 책 목록 정렬

---

## 이전 원칙

기존 프로필 Bookshelf UI를 한 번에 제거하지 않는다.

이전은 단계적으로 진행한다.

1. Library Screen을 새로 추가한다.
2. 기존 프로필 Bookshelf UI와 같은 데이터를 Library Screen에서도 보여준다.
3. Library Screen에서 기존 Bookshelf 기능이 정상 동작하는지 확인한다.
4. 프로필 화면은 요약형으로 줄인다.
5. 프로필의 상세 Bookshelf 관리 UI는 제거하거나 Library Screen으로 안내한다.

즉, 초기 구현 단계에서는 프로필 화면과 Library Screen이 일시적으로 일부 기능을 중복할 수 있다.

---

## Library Screen에서 제공할 기능

Library Screen은 기존 프로필 Bookshelf UI의 기능을 옮겨오는 것을 1차 목표로 한다.

### 책장 표시

- 접근 가능한 Bookshelf를 탭으로 표시한다.
- 기본 책장 “내 책장”은 항상 첫 번째다.
- 일반 책장은 `position ASC, id ASC` 순서로 표시한다.
- 책장 탭에는 이름, 책 개수, `color_key` 색상을 표시한다.

### 책장 선택

기존 query parameter 정책을 유지한다.

```text
/users/:user_id/library?bookshelf_id=3
```

- `bookshelf_id`가 없으면 기본 책장을 선택한다.
- 접근 불가능한 `bookshelf_id`가 주어지면 접근 가능한 기본 책장 또는 첫 책장으로 fallback한다.

### 책 목록 정렬

기존 sort query parameter 정책을 유지한다.

```text
/users/:user_id/library?bookshelf_id=3&sort=title
```

지원 값:

- `recent`
- `title`
- `author`
- `status`

정책:

- 기본값은 `recent`다.
- 허용되지 않은 sort 값은 `recent`로 fallback한다.
- 책장 탭 이동 시 현재 sort 값을 유지한다.

### 책 이동

self는 자신의 `BookshelfEntry`를 자신의 다른 Bookshelf로 이동할 수 있다.

- 이동은 중복 생성이 아니다.
- 기존 `BookshelfEntry.bookshelf_id`만 변경한다.
- 다른 사용자의 BookshelfEntry는 이동할 수 없다.
- 다른 사용자의 Bookshelf로 이동할 수 없다.

### 책장 생성

self는 일반 Bookshelf를 생성할 수 있다.

- 입력값은 `name`, `visibility`, `color_key`로 제한한다.
- `is_default`는 서버에서 `false`로 고정한다.
- 생성 성공 후 새 책장 탭으로 이동한다.
- 사용자당 Bookshelf 수는 기본 책장 포함 최대 20개다.

### 책장 수정

self는 일반 Bookshelf를 수정할 수 있다.

- 수정 가능한 값은 `name`, `visibility`, `color_key`다.
- 기본 책장 “내 책장”은 수정할 수 없다.
- 다른 사용자의 Bookshelf는 수정할 수 없다.

### 책장 삭제

self는 빈 일반 Bookshelf를 삭제할 수 있다.

- 기본 책장은 삭제할 수 없다.
- 책이 들어 있는 일반 Bookshelf는 삭제할 수 없다.
- 다른 사용자의 Bookshelf는 삭제할 수 없다.

### 책장 순서 변경

self는 일반 Bookshelf의 순서를 위/아래 버튼으로 바꿀 수 있다.

- 기본 책장은 항상 첫 번째이며 이동할 수 없다.
- 일반 책장은 `position` 기준으로 정렬한다.
- 위로 이동하면 이전 일반 책장과 `position`을 교환한다.
- 아래로 이동하면 다음 일반 책장과 `position`을 교환한다.

---

## 권한 정책

Library Screen은 프로필보다 깊은 서재 화면이다.

따라서 Library Screen 접근은 `self`와 `accepted book_friend`에게만 허용한다.

`follow`의 추가 의미는 Library 접근 권한이 아니라 홈 피드 구독이다.  
`stranger`와 `follow`는 프로필에서 public 책 목록을 볼 수 있지만, 상대의 Library Screen에는 접근할 수 없다.

### Library 접근 권한

| viewer 관계 | Library 접근 |
| --- | --- |
| self | 가능 |
| accepted book_friend | 가능 |
| follow | 불가 |
| stranger | 불가 |

follow가 상대의 public Jjaek을 홈 피드에서 받아보는 관계라면, book_friend는 상대의 서재 구조까지 볼 수 있는 관계다.

```text
follow = 소식받기
book_friend = 서재 접근
```

### Library 안에서 볼 수 있는 책장

Library 안에서 볼 수 있는 책장은 Bookshelf visibility 정책을 따른다.

| viewer 관계 | 볼 수 있는 책장 |
| --- | --- |
| self | `public` + `book_friends` + `private` |
| accepted book_friend | `public` + `book_friends` |

### 상태/스티커 노출 정책

상태/스티커 노출 정책도 기존 정책을 따른다.

| viewer 관계 | 책 제목/표지/저자 | 상태/스티커 |
| --- | --- | --- |
| self | 볼 수 있음 | 볼 수 있음 |
| accepted book_friend | 볼 수 있음 | 볼 수 있음 |

관리 기능은 self에게만 제공한다.

self만 가능한 기능:

- 책 이동
- 책장 생성
- 책장 수정
- 책장 삭제
- 책장 순서 변경

---

## 프로필 화면에 남길 것

Library Screen 도입 후 프로필 화면은 가볍게 유지한다.

프로필 화면에 남길 후보:

- 사용자 정보
- 최근 활동
- 공개 가능한 책 목록 요약
- 최근 BookActivity / Jjaek 흐름
- self / accepted book_friend에게만 “서재 보기” 링크

프로필 화면에서 제거하거나 축소할 후보:

- 전체 책장 탭
- 책장 생성 form
- 책장 수정/삭제 form
- 책장 순서 변경 버튼
- 책 목록 정렬 UI
- 책 이동 select

정확히 무엇을 남길지는 Library Screen 구현 후 브라우저 확인을 거쳐 결정한다.

---

## 이번 단계에서 하지 않을 것

Library Screen 도입 단계에서는 다음을 하지 않는다.

- `Library` 모델 생성
- DB 구조 변경
- 기존 Bookshelf / BookshelfEntry 모델 변경
- 기존 프로필 Bookshelf UI 즉시 제거
- drag & drop 도입
- 별도 책장 관리 전용 dashboard 도입
- BookActivity visibility 변경
- Bookshelf visibility와 BookActivity visibility 연동
- 사용자별 책 문맥 화면 도입

---

## 구현 단계 제안

### 1단계: Library Screen 추가

- `/users/:user_id/library` route 추가
- Library 화면 controller 추가
- 기존 프로필 Bookshelf section을 재사용하거나 partial을 분리해 Library Screen에서 렌더링
- self / accepted book_friend만 Library Screen에 접근 가능하도록 한다
- follow / stranger가 Library Screen에 접근하면 프로필 화면으로 돌려보낸다
- 프로필에는 “서재 보기” 링크를 추가한다

### 2단계: 관리 기능 이동

- Library Screen에서 책장 생성/수정/삭제/순서 변경/책 이동/정렬 기능 동작 확인
- 프로필 화면의 관리 UI를 축소하거나 제거
- 프로필 화면은 요약 중심으로 정리

### 3단계: 프로필 요약 정리

- 프로필에 공개 가능한 책 목록을 요약으로 표시한다
- self / accepted book_friend에게 “전체 서재 보기” 링크를 제공한다
- stranger / follow는 프로필에서 public 책 목록만 볼 수 있다
- visitor 권한별 요약 노출 범위를 정리한다

### 4단계: 후속 확장 검토

- drag & drop
- 별도 책장 관리 화면
- BookActivity와 Bookshelf visibility 연동
- 사용자별 책 문맥 화면

---

## 테스트 기준

Library Screen 구현 시 최소한 다음을 테스트한다.

### 접근

1. 비로그인 사용자는 Library Screen 접근 시 로그인 화면으로 이동한다.
2. self는 자신의 Library Screen을 볼 수 있다.
3. accepted book_friend는 상대의 Library Screen을 볼 수 있다.
4. stranger는 Library Screen에 접근할 수 없다.
5. follow는 Library Screen에 접근할 수 없다.
6. stranger / follow가 Library Screen에 접근하면 프로필 화면으로 redirect된다.

### 책장 탭

1. 기본 책장은 항상 첫 번째로 보인다.
2. 일반 책장은 `position` 순으로 보인다.
3. 접근 불가능한 책장은 탭에 보이지 않는다.
4. 허용되지 않은 `bookshelf_id`는 접근 가능한 책장으로 fallback된다.
5. accepted book_friend는 `public` + `book_friends` 책장만 볼 수 있다.
6. accepted book_friend는 `private` 책장을 볼 수 없다.

### 책 목록

1. 선택한 책장의 책만 표시된다.
2. sort query parameter가 동작한다.
3. 상태/스티커 노출 정책이 기존과 동일하게 유지된다.

### 관리 기능

1. self는 책장을 생성할 수 있다.
2. self는 일반 책장을 수정할 수 있다.
3. self는 빈 일반 책장을 삭제할 수 있다.
4. self는 책장 순서를 변경할 수 있다.
5. self는 책을 다른 자기 책장으로 이동할 수 있다.
6. self도 기본 책장은 수정/삭제/이동할 수 없다.
7. 타인은 관리 UI를 볼 수 없다.

### 프로필 연동

1. 프로필 화면에 Library Screen으로 이동하는 링크가 보인다.
2. Library Screen 도입 후에도 기존 프로필의 최근 활동/Jjaek 흐름이 깨지지 않는다.
3. stranger / follow는 프로필에서 public 책 목록을 볼 수 있다.
4. follow는 Library 접근 권한이 아니라 홈 피드 구독 관계로만 해석된다.

---

## 관련 문서

- `docs/specs/bookshelf_foundation.md`
- `docs/specs/bookshelf_ui.md`
- `docs/architecture/current_system.md`
- `docs/architecture/authorization.md`