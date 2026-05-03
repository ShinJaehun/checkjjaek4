# Bookshelf Management MVP Spec

## 목적

Bookshelf Management MVP는 사용자가 자신의 책장을 화면에서 구분하고, 책을 다른 책장으로 이동할 수 있게 하는 최소 관리 기능이다.

이번 단계에서는 다음 두 가지를 우선 구현한다.

1. 프로필 책 목록을 책장 탭으로 구분해서 보여준다.
2. 본인은 select를 사용해 책을 다른 내 책장으로 이동할 수 있다.

책장 생성/수정/삭제, 책장 색상 선택, drag & drop 이동은 후속 작업으로 남긴다.

---

## 현재 전제

Bookshelf foundation 작업은 이미 완료되어 있다고 가정한다.

현재 정책은 다음과 같다.

- 모든 사용자는 기본 책장 “내 책장”을 가진다.
- 기본 책장은 `is_default: true`이다.
- 기본 책장은 삭제할 수 없다.
- 기본 책장의 이름은 변경할 수 없다.
- 기본 책장의 `is_default` 값을 `false`로 변경할 수 없다.
- User 삭제 시에는 해당 User의 Bookshelf와 BookshelfEntry도 함께 삭제된다.
- User 삭제 시에도 Book 자체는 삭제되지 않는다.
- 한 사용자의 같은 책은 하나의 `BookshelfEntry`만 가진다.
- 하나의 `BookshelfEntry`는 하나의 `Bookshelf`에만 속한다.
- 책을 다른 책장으로 옮기는 것은 기존 `BookshelfEntry.bookshelf_id`를 변경하는 것이다.
- 책 이동은 중복 추가가 아니다.

---

## 책장 개수 제한

MVP에서는 사용자당 Bookshelf 수를 최대 20개로 제한한다.

이 제한에는 기본 책장 “내 책장”도 포함된다.  
따라서 사용자가 추가로 생성할 수 있는 일반 책장은 최대 19개다.

제한 이유는 다음과 같다.

- 탭 UI가 과도하게 길어지는 것을 막는다.
- 모바일에서 책장 탐색이 복잡해지는 것을 막는다.
- 책 이동 select가 너무 길어지는 것을 막는다.
- 책장 관리 UI의 복잡도를 낮춘다.
- 의미 없는 대량 책장 생성을 방지한다.

향후 실제 사용 패턴을 본 뒤 제한 값은 조정할 수 있다.

이번 단계에서는 책장 생성 UI를 만들지 않으므로, 이 제한은 문서 정책으로 먼저 둔다.  
실제 validation은 책장 생성 UI를 구현하는 단계에서 추가한다.

---

## 이번 MVP에서 할 것

### 1. 책장 탭 UI

프로필 책 목록을 Bookshelf 단위로 구분해서 보여준다.

- 접근 가능한 Bookshelf만 탭으로 표시한다.
- 기본 책장 “내 책장”도 하나의 탭으로 표시한다.
- 기본 책장은 항상 첫 번째 탭으로 표시한다.
- 나머지 책장은 생성순 또는 기존 scope 순서를 따른다.
- 선택된 책장의 BookshelfEntry만 목록에 표시한다.
- 탭에는 책장 이름과 책 개수를 표시한다.
- 책장이 많아질 수 있으므로 탭은 가로 스크롤 가능한 구조를 우선한다.
- 선택된 탭은 색상뿐 아니라 border, font-weight 등으로 명확히 표시한다.

예상 UI:

```text
[내 책장 12] [수업 추천 5] [아이들과 읽은 책 8]
```

---

### 2. URL 기반 탭 선택

탭 선택 상태는 JavaScript 내부 상태로만 관리하지 않는다.

MVP에서는 query parameter를 사용한다.

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

### 3. 관계별 책장 탭 노출

Bookshelf visibility 정책은 기존 정책을 따른다.

| viewer 관계 | 표시 가능한 책장 탭 |
| --- | --- |
| self | `public` + `book_friends` + `private` |
| accepted book_friend | `public` + `book_friends` |
| follow-only | `public` |
| stranger | `public` |

follow-only는 Bookshelf visibility 기준으로는 stranger와 동일하게 public 책장만 볼 수 있다.

---

### 4. 상태/스티커 노출 정책 유지

책장 탭을 도입하더라도 상태/스티커 노출 정책은 기존 정책을 유지한다.

| viewer 관계 | 책 제목/표지/저자 | 상태/스티커 |
| --- | --- | --- |
| self | 볼 수 있음 | 볼 수 있음 |
| accepted book_friend | 볼 수 있음 | 볼 수 있음 |
| follow-only | public 책장에 한해 볼 수 있음 | 볼 수 없음 |
| stranger | public 책장에 한해 볼 수 있음 | 볼 수 없음 |

즉, stranger/follow-only는 public 책장 탭과 책 목록은 볼 수 있지만, 상태와 스티커는 볼 수 없다.

---

### 5. select 기반 책 이동

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

---

## 책 이동 권한

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

view에서 `policy(...)` 직접 호출을 늘리지 않는다.  
controller/policy/helper에서 계산한 값을 view에 넘기는 방향을 우선한다.

---

## Owner / Visitor UI 차이

### self

본인 프로필에서는 다음을 볼 수 있다.

- 접근 가능한 모든 책장 탭
- 책 목록
- 상태/스티커
- 책 이동 select

### accepted book_friend

책친구는 다음을 볼 수 있다.

- public + book_friends 책장 탭
- 책 목록
- 상태/스티커
- 책 이동 select는 볼 수 없음

### stranger / follow-only

stranger/follow-only는 다음을 볼 수 있다.

- public 책장 탭
- 책 목록
- 상태/스티커는 볼 수 없음
- 책 이동 select는 볼 수 없음

---

## 빈 책장 처리

선택된 책장에 표시할 책이 없으면 빈 상태 문구를 보여준다.

MVP에서는 단순한 문구를 사용한다.

```text
아직 책이 없습니다.
```

후속 작업에서 owner/visitor별 문구를 나눌 수 있다.

예:

- owner: “이 책장에는 아직 책이 없습니다. 책을 추가하거나 다른 책장에서 이동해보세요.”
- visitor: “이 책장에는 아직 공개된 책이 없습니다.”

---

## 책장 정렬

MVP에서는 단순 정렬을 사용한다.

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

이번 MVP에서는 책장 색상 선택을 구현하지 않는다.

다만 후속 UI 작업에서는 `Bookshelf.color_key` 방식으로 색상을 관리하는 방향을 우선 검토한다.

예상 후보:

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

자유 hex 입력보다는 제한된 palette key 방식을 우선한다.

이유:

- 디자인이 깨지는 것을 막을 수 있다.
- 접근성과 가독성을 관리하기 쉽다.
- Tailwind 스타일과 연결하기 쉽다.
- dark mode 대응이 쉽다.

---

## Drag & Drop

이번 MVP에서는 drag & drop을 구현하지 않는다.

책 이동은 select 기반으로 먼저 구현한다.

후속 작업에서 drag & drop을 도입할 수 있다.

drag & drop도 서버 정책은 동일하다.

- 기존 `BookshelfEntry.bookshelf_id`만 변경한다.
- 다른 사용자의 책장으로 이동할 수 없다.
- 다른 사용자의 BookshelfEntry를 이동할 수 없다.

---

## 이번 MVP에서 하지 않을 것

이번 단계에서는 다음을 하지 않는다.

- 책장 생성 UI
- 책장 이름 수정 UI
- 책장 삭제 UI
- 기본 책장 이름 변경
- 기본 책장 삭제
- 책장 visibility 변경 UI
- 책장 색상 선택
- `color_key` 컬럼 추가
- drag & drop 이동
- 캐러셀/슬라이드 UI
- 사용자별 책 문맥 화면
- BookActivity visibility 변경
- Notification 연동
- 책장 순서 변경
- 책 목록 정렬 UI

---

## 후속 작업 후보

Bookshelf Management MVP 이후 다음 작업을 검토할 수 있다.

1. 일반 책장 생성 UI
2. 사용자당 책장 최대 20개 validation
3. 일반 책장 이름 수정
4. 일반 책장 visibility 변경
5. 일반 책장 삭제
6. 책장 삭제 시 안의 책을 기본 책장으로 이동
7. 책장 `color_key` 추가
8. 책장 색상 선택 UI
9. drag & drop 기반 책 이동
10. 책장 순서 변경
11. 책장별 책 정렬 옵션
12. 별도 책장 관리 화면 분리

---

## 테스트 기준

최소한 다음 테스트를 추가/보강한다.

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