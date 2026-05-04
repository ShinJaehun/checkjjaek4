# Bookshelf UI Spec

## 목적

Bookshelf UI는 사용자가 프로필 화면에서 책장을 확인하고 관리하는 화면 정책을 정의한다.

이 문서는 다음 내용을 다룬다.

- 프로필 책장 탭 UI
- URL 기반 탭 선택
- 관계별 책장 탭 노출
- 상태/스티커 노출 정책
- select 기반 책 이동
- 일반 책장 생성 UI
- 일반 책장 수정/삭제 UI
- 책장 `color_key` 표시와 선택
- 아직 구현하지 않은 책장 관리 UI 후보

Bookshelf의 데이터 모델, 기본 책장, visibility, BookshelfEntry 인바리언트는 `docs/specs/bookshelf_foundation.md`에서 다룬다.

---

## 기본 UI 범위

이 문서는 프로필 Bookshelf UI의 기본 범위를 다룬다.

1. 프로필 책 목록을 책장 탭으로 구분해서 보여준다.
2. URL query parameter로 선택된 책장을 유지한다.
3. viewer 관계에 따라 접근 가능한 책장 탭만 보여준다.
4. self / accepted book_friend에게는 상태/스티커를 보여준다.
5. stranger / follow-only에게는 상태/스티커를 숨긴다.
6. 본인은 select를 사용해 책을 다른 내 책장으로 이동할 수 있다.
7. 본인은 일반 책장을 새로 만들 수 있다.
8. 본인은 일반 책장의 이름/visibility를 수정하고 빈 일반 책장을 삭제할 수 있다.
9. 본인은 일반 책장 생성/수정 시 제한된 `color_key`를 선택할 수 있다.

아래 기능은 이 문서에 계속 누적하지 않고, 필요하면 별도 spec 문서 또는 해당 브랜치에서 구체화한다.

- 책장 삭제 시 안의 책 처리 정책
- drag & drop 이동
- 책장 순서 변경
- 책 목록 정렬 UI
- 별도 책장 관리 화면

---

## 공통 UI 원칙

- 기본 책장 “내 책장”은 항상 첫 번째 탭으로 표시한다.
- 접근 가능한 Bookshelf만 탭으로 표시한다.
- 선택된 책장의 BookshelfEntry만 목록에 표시한다.
- 책장 탭에는 책장 이름과 책 개수를 표시한다.
- 책장 탭에는 접근 가능한 책장의 `color_key`를 시각적으로 반영한다.
- 책장이 많아지면 가로 스크롤 대신 다음 줄로 줄바꿈되게 한다.
- 선택된 탭은 색상뿐 아니라 border, font-weight 등으로 명확히 표시한다.
- view에서 `policy(...)` 직접 호출을 늘리지 않는다.
- controller/policy/helper에서 계산한 값을 view에 넘기는 방향을 우선한다.
- JavaScript 없이도 기본 기능이 동작해야 한다.

---

## 책장 개수 제한

사용자당 Bookshelf 수는 최대 20개로 제한한다.

이 제한에는 기본 책장 “내 책장”도 포함된다.  
따라서 사용자가 추가로 생성할 수 있는 일반 책장은 최대 19개다.

제한 이유는 다음과 같다.

- 탭 UI가 과도하게 길어지는 것을 막는다.
- 모바일에서 책장 탐색이 복잡해지는 것을 막는다.
- 책 이동 select가 너무 길어지는 것을 막는다.
- 책장 관리 UI의 복잡도를 낮춘다.
- 의미 없는 대량 책장 생성을 방지한다.

향후 실제 사용 패턴을 본 뒤 제한 값은 조정할 수 있다.

---

## 책장 탭 UI

프로필 책 목록을 Bookshelf 단위로 구분해서 보여준다.

- 접근 가능한 Bookshelf만 탭으로 표시한다.
- 기본 책장 “내 책장”도 하나의 탭으로 표시한다.
- 기본 책장은 항상 첫 번째 탭으로 표시한다.
- 나머지 책장은 생성순 또는 기존 scope 순서를 따른다.
- 선택된 책장의 BookshelfEntry만 목록에 표시한다.
- 탭에는 책장 이름과 책 개수를 표시한다.
- 책장이 많아지면 가로 스크롤 대신 다음 줄로 줄바꿈되게 한다.
- 선택된 탭은 색상뿐 아니라 border, font-weight 등으로 명확히 표시한다.

예상 UI:

```text
[내 책장 12] [수업 추천 5] [아이들과 읽은 책 8]
```

---

## URL 기반 탭 선택

탭 선택 상태는 JavaScript 내부 상태로만 관리하지 않는다.

query parameter를 사용한다.

```text
/users/:id?bookshelf_id=3
```

이 방식의 장점은 다음과 같다.

- 새로고침해도 선택된 책장이 유지된다.
- 브라우저 뒤로가기가 자연스럽다.
- 테스트가 쉽다.
- JavaScript 없이도 동작한다.
- 나중에 Turbo Frame으로 확장하기 쉽다.

선택된 `bookshelf_id`가 없으면 기본 책장을 선택한다.

선택된 `bookshelf_id`가 viewer에게 허용되지 않은 책장이면, 접근 가능한 첫 번째 책장 또는 기본 책장으로 fallback한다.

---

## 관계별 책장 탭 노출

Bookshelf visibility 정책은 foundation 정책을 따른다.

| viewer 관계 | 표시 가능한 책장 탭 |
| --- | --- |
| self | `public` + `book_friends` + `private` |
| accepted book_friend | `public` + `book_friends` |
| follow-only | `public` |
| stranger | `public` |

follow-only는 Bookshelf visibility 기준으로는 stranger와 동일하게 public 책장만 볼 수 있다.

---

## 상태/스티커 노출 정책

책장 탭을 도입하더라도 상태/스티커 노출 정책은 foundation 정책을 유지한다.

| viewer 관계 | 책 제목/표지/저자 | 상태/스티커 |
| --- | --- | --- |
| self | 볼 수 있음 | 볼 수 있음 |
| accepted book_friend | 볼 수 있음 | 볼 수 있음 |
| follow-only | public 책장에 한해 볼 수 있음 | 볼 수 없음 |
| stranger | public 책장에 한해 볼 수 있음 | 볼 수 없음 |

즉, stranger/follow-only는 public 책장 탭과 책 목록은 볼 수 있지만, 상태와 스티커는 볼 수 없다.

---

## select 기반 책 이동

본인은 자신의 BookshelfEntry를 다른 내 책장으로 이동할 수 있다.

- 책 카드에 책장 이동 select를 표시한다.
- select에는 자신의 Bookshelf만 표시한다.
- 현재 책장이 기본 선택값이다.
- 다른 책장을 선택하면 기존 `BookshelfEntry.bookshelf_id`를 변경한다.
- 이동은 중복 추가가 아니다.
- 이동 후에도 `BookshelfEntry`는 새로 생성되지 않는다.
- 이동 후 기존 탭에 남아 있으면 해당 책은 현재 탭에서 사라질 수 있다.
- 이동 성공 시 flash를 표시한다.

예상 flash:

```text
책을 “수업 추천” 책장으로 옮겼습니다.
```

### 책 이동 권한

책 이동은 owner만 할 수 있다.

허용:

- 로그인한 사용자는 자신의 BookshelfEntry만 이동할 수 있다.
- 자신의 Bookshelf로만 이동할 수 있다.

금지:

- 다른 사용자의 BookshelfEntry를 이동할 수 없다.
- 다른 사용자의 Bookshelf로 이동할 수 없다.
- 접근 불가능한 Bookshelf로 이동할 수 없다.
- 삭제된 Bookshelf로 이동할 수 없다.
- 기본 책장 삭제/이름 변경 정책을 우회할 수 없다.

권한은 Pundit policy 또는 controller guard로 명시적으로 고정한다.

---

## 일반 책장 생성 UI

사용자는 본인 프로필에서 일반 책장을 새로 만들 수 있다.

### 목표

- 사용자는 본인 프로필에서 새 책장을 만들 수 있다.
- 새 책장은 생성 즉시 책장 탭에 표시된다.
- 생성 성공 후 새로 만든 책장 탭으로 이동한다.

### 생성 UI 노출

책장 생성 UI는 본인 프로필에서만 노출한다.

허용:

- 로그인한 사용자가 자신의 프로필을 보고 있을 때

금지:

- 다른 사용자의 프로필을 보고 있을 때
- 비로그인 상태

accepted book_friend, follow-only, stranger에게는 책장 생성 UI를 보여주지 않는다.

### 입력값

책장 생성 시 입력받는 값은 다음으로 제한한다.

- 책장 이름
- visibility
- `color_key`

visibility는 기존 Bookshelf visibility 값을 그대로 사용한다.

```text
public
book_friends
private
```

정렬 순서, 설명 문구는 입력받지 않는다.

### 생성 정책

- 책장 생성은 owner만 가능하다.
- 새 책장은 항상 `current_user.bookshelves`에 생성한다.
- 다른 사용자의 책장은 생성할 수 없다.
- 기본 책장 “내 책장”은 생성 UI로 다시 만들 수 없다.
- 일반 책장의 `is_default` 값은 항상 `false`이다.
- 일반 책장의 `color_key`는 제한된 palette key만 허용한다.
- 사용자당 Bookshelf 수는 기본 책장 포함 최대 20개다.
- 같은 사용자 안에서 책장 이름은 중복될 수 없다.

### 생성 성공 후 이동

책장 생성에 성공하면 새로 생성한 책장 탭으로 이동한다.

예상 redirect:

```text
/users/:id?bookshelf_id=<new_bookshelf_id>
```

성공 시 flash를 표시한다.

예상 flash:

```text
책장 “수업 추천”을 만들었습니다.
```

### 생성 실패 처리

validation 실패 시 책장 생성 form에 오류를 표시한다.

실패 예:

- 이름이 비어 있음
- 같은 이름의 책장이 이미 있음
- 사용자당 최대 20개 제한을 초과함
- 허용되지 않은 visibility 값이 전달됨
- 허용되지 않은 `color_key` 값이 전달됨

실패하더라도 기존 책장 탭과 현재 선택된 책 목록은 계속 표시되어야 한다.

---

## 일반 책장 수정/삭제 UI

책장 수정/삭제 UI는 본인 프로필에서 선택된 일반 책장에만 노출한다.

- 기본 책장 “내 책장”은 수정/삭제할 수 없다.
- 수정 가능한 값은 책장 이름, visibility, `color_key`로 제한한다.
- 수정 성공 후 해당 책장 탭으로 이동한다.
- 수정 실패 시 기존 책장 탭과 현재 선택된 책 목록은 계속 표시되어야 한다.
- 삭제는 빈 일반 책장만 허용한다.
- 책이 들어 있는 일반 책장은 삭제할 수 없다.
- 삭제 성공 후 기본 책장 또는 접근 가능한 첫 책장 탭으로 이동한다.
- 다른 사용자의 프로필에서는 수정/삭제 UI를 보여주지 않는다.

---

## 책장 color_key

`color_key`는 책장 탭의 시각적 구분을 위한 제한된 palette key다.

지원 값:

```text
stone
red
orange
yellow
green
blue
purple
pink
```

- 기본값은 `stone`이다.
- 자유 hex 입력이나 사용자 정의 색상은 허용하지 않는다.
- 기본 책장 “내 책장”은 `stone`을 유지하고 수정 UI를 제공하지 않는다.
- 타인 프로필에서도 접근 가능한 책장 탭의 `color_key` 표시는 허용한다.

---

## Owner / Visitor UI 차이

### self

기본 UI 기준으로 본인 프로필에서는 최소한 다음을 볼 수 있다.

- 접근 가능한 모든 책장 탭
- 책 목록
- 상태/스티커
- 책 이동 select
- 일반 책장 생성 form
- 선택한 일반 책장 수정/삭제 UI

### accepted book_friend

책친구는 다음을 볼 수 있다.

- public + book_friends 책장 탭
- 책 목록
- 상태/스티커
- 책 이동 select는 볼 수 없음
- 일반 책장 생성 form은 볼 수 없음
- 책장 수정/삭제 UI는 볼 수 없음

### stranger / follow-only

stranger/follow-only는 다음을 볼 수 있다.

- public 책장 탭
- 책 목록
- 상태/스티커는 볼 수 없음
- 책 이동 select는 볼 수 없음
- 일반 책장 생성 form은 볼 수 없음
- 책장 수정/삭제 UI는 볼 수 없음

---

## 빈 책장 처리

선택된 책장에 표시할 책이 없으면 빈 상태 문구를 보여준다.

기본 문구:

```text
아직 책이 없습니다.
```

후속 작업에서 owner/visitor별 문구를 나눌 수 있다.

예:

- owner: “이 책장에는 아직 책이 없습니다. 책을 추가하거나 다른 책장에서 이동해보세요.”
- visitor: “이 책장에는 아직 공개된 책이 없습니다.”

---

## 책장 정렬

현재는 단순 정렬을 사용한다.

- 기본 책장 “내 책장”은 항상 첫 번째
- 나머지 책장은 생성순

후속 작업에서 사용자가 책장 순서를 바꾸는 기능을 검토할 수 있다.

---

## 책 카드 정렬

책장 안의 책 목록은 기존 정렬 정책을 유지한다.

현재 `BookshelfEntry.recent_first`가 있다면 그대로 사용한다.

후속 작업에서 다음 정렬을 검토할 수 있다.

- 최근 수정순
- 제목순
- 저자순
- 읽기 상태순

---

## 책장 색상

현재는 `Bookshelf.color_key` 방식으로 제한된 palette key만 선택한다.

이유:

- 디자인이 깨지는 것을 막을 수 있다.
- 접근성과 가독성을 관리하기 쉽다.
- Tailwind 스타일과 연결하기 쉽다.

---

## Drag & Drop

현재는 drag & drop을 구현하지 않는다.

책 이동은 select 기반으로 먼저 구현한다.

후속 작업에서 drag & drop을 도입할 수 있다.

drag & drop도 서버 정책은 동일하다.

- 기존 `BookshelfEntry.bookshelf_id`만 변경한다.
- 다른 사용자의 책장으로 이동할 수 없다.
- 다른 사용자의 BookshelfEntry를 이동할 수 없다.

---

## 별도 spec으로 다룰 확장 범위

아래 기능은 이 문서에 계속 누적하지 않고, 필요하면 별도 spec 문서 또는 해당 브랜치에서 구체화한다.

- 책장 삭제 시 안의 책 처리 정책
- drag & drop 기반 책 이동
- 책장 순서 변경
- 책장별 책 정렬 옵션
- 별도 책장 관리 화면 분리
- 사용자별 책 문맥 화면
- BookActivity visibility 변경
- Notification 연동

---

## 테스트 기준

최소한 다음 테스트를 유지한다.

### 책장 탭

1. self는 자신의 기본 책장 탭을 볼 수 있다.
2. self는 private 책장 탭도 볼 수 있다.
3. accepted book_friend는 public + book_friends 책장 탭을 볼 수 있다.
4. accepted book_friend는 private 책장 탭을 볼 수 없다.
5. stranger/follow-only는 public 책장 탭만 볼 수 있다.
6. 선택한 책장 탭의 책만 표시된다.
7. 허용되지 않은 `bookshelf_id`가 전달되면 접근 가능한 책장으로 fallback된다.

### 상태/스티커

1. self는 선택한 책장 안에서 상태/스티커를 볼 수 있다.
2. accepted book_friend는 선택한 책장 안에서 상태/스티커를 볼 수 있다.
3. stranger/follow-only는 public 책장 안의 책 제목은 볼 수 있지만 상태/스티커는 볼 수 없다.

### 책 이동

1. self는 자신의 BookshelfEntry를 다른 자기 Bookshelf로 이동할 수 있다.
2. 이동 후 BookshelfEntry는 중복 생성되지 않는다.
3. 이동 후 BookshelfEntry의 `bookshelf_id`만 변경된다.
4. 다른 사용자의 BookshelfEntry는 이동할 수 없다.
5. 다른 사용자의 Bookshelf로 이동할 수 없다.
6. 책 이동 select는 self에게만 보인다.
7. accepted book_friend / stranger / follow-only에게는 책 이동 select가 보이지 않는다.

### 책장 생성

1. self는 본인 프로필에서 책장 생성 form을 볼 수 있다.
2. accepted book_friend / stranger / follow-only는 책장 생성 form을 볼 수 없다.
3. self는 이름과 visibility를 입력해 일반 책장을 만들 수 있다.
4. 새 책장의 `is_default` 값은 `false`이다.
5. 책장 생성 후 새 책장 탭으로 이동한다.
6. 같은 사용자 안에서 같은 이름의 책장은 생성할 수 없다.
7. 사용자당 Bookshelf 수가 20개이면 새 책장을 생성할 수 없다.
8. 허용되지 않은 visibility 값으로 책장을 생성할 수 없다.
9. 생성 시 `color_key`를 저장할 수 있고, 없으면 `stone`으로 저장된다.
10. 허용되지 않은 `color_key` 값으로 책장을 생성할 수 없다.

### 책장 수정/삭제

1. self는 본인 프로필에서 일반 책장 수정/삭제 UI를 볼 수 있다.
2. 기본 책장과 타인 프로필에서는 책장 수정/삭제 UI가 보이지 않는다.
3. owner는 일반 책장 이름과 visibility를 수정할 수 있다.
4. 기본 책장과 다른 사용자의 책장은 update 요청으로도 수정할 수 없다.
5. 중복 이름이나 허용되지 않은 visibility이면 수정 실패한다.
6. owner는 빈 일반 책장을 삭제할 수 있다.
7. 기본 책장, 다른 사용자의 책장, 책이 들어 있는 일반 책장은 삭제할 수 없다.
8. 수정/삭제 실패 시 사용자에게 오류 메시지를 보여준다.
9. owner는 일반 책장의 `color_key`를 수정할 수 있다.
10. 기본 책장은 update 요청으로도 `color_key`를 바꿀 수 없다.

### 책장 color_key UI

1. 일반 책장 생성 form에 `color_key` 선택 UI가 보인다.
2. 일반 책장 관리 form에 `color_key` 선택 UI가 보인다.
3. 책장 탭에 `color_key`가 반영된다.
4. 타인 프로필에서는 생성/수정 UI 없이 책장 탭 색상 표시만 유지된다.

---

## 관련 문서

- `docs/specs/bookshelf_foundation.md`
- `docs/architecture/current_system.md`
- `docs/architecture/authorization.md`
