# Bookshelf UI Spec

## 목적

Bookshelf UI는 사용자가 프로필 화면에서 책장을 확인하고 관리하는 화면 정책을 정의한다.

이 문서는 다음 내용을 다룬다.

- 프로필 책장 탭 UI
- URL 기반 탭 선택
- 관계별 책장 탭 노출
- 상태/스티커 노출 정책
- 새 책 서재 담기 시 대상 책장 선택 UI
- select 기반 책 이동
- 책장 인덱스 기반 Drag and Drop 이동
- 일반 책장 생성 UI
- 일반 책장 수정/삭제 UI
- 책장 `color_key` 표시와 선택
- 일반 책장 위/아래 순서 변경 UI
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
6. 새 책을 서재에 담을 때 책장이 2개 이상이면 대상 책장을 선택할 수 있다.
7. 본인은 select를 사용해 책을 다른 내 책장으로 이동할 수 있다.
8. 본인은 일반 책장을 새로 만들 수 있다.
9. 본인은 일반 책장의 이름/visibility를 수정하고 빈 일반 책장을 삭제할 수 있다.
10. 본인은 일반 책장 생성/수정 시 제한된 `color_key`를 선택할 수 있다.
11. 본인은 프로필 화면 안에서 일반 책장 순서를 위/아래 버튼으로 변경할 수 있다.
12. 본인은 책장 인덱스 기반 Drag and Drop으로 책을 다른 내 책장으로 이동할 수 있다.

아래 기능은 이 문서에 계속 누적하지 않고, 필요하면 별도 spec 문서 또는 해당 브랜치에서 구체화한다.

- 책장 삭제 시 안의 책 처리 정책
- 별도 책장 관리 화면

---

## 새 책 서재 담기 시 대상 책장 선택

책 검색 결과와 책 상세 read-only 화면에서 새 책을 서재에 담을 수 있다.

- 사용자의 책장이 2개 이상이면 대상 책장 select를 표시한다.
- 책장이 1개뿐이면 select 없이 기존처럼 바로 담는다.
- 대상 책장을 선택하지 않으면 기본 책장 “내 책장”에 담긴다.
- `bookshelf_id`가 전달되면 반드시 `current_user` 소유 책장이어야 한다.
- 이미 담긴 책은 중복 생성하지 않고, 이 흐름에서 책장 이동으로 처리하지 않는다.

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
- 나머지 책장은 `position` 순서를 따른다.
- 선택된 책장의 BookshelfEntry만 목록에 표시한다.
- `manual` 정렬은 BookshelfEntry의 `position` 오름차순을 사용한다.
- 본인 Library의 기본 정렬은 `manual`이다.
- visitor / book_friend 등 타인이 보는 Library의 기본 정렬은 `recent`이다.
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

## 책장 Drag and Drop 목표와 단계

책장 UI의 최종 목표는 책장을 단순한 필터 탭이 아니라, 책을 정리하는 실제 공간처럼 느끼게 하는 것이다.

상단 책장 인덱스는 다음 두 역할을 가진다.

- 클릭하면 해당 책장을 연다.
- 책 카드를 드래그할 때 이동 대상이 된다.

책은 한 번에 하나의 책장에만 속한다.
기본 책장인 “내 책장”도 이동 대상이 될 수 있다.
책 이동이 성공하면 원래 책장에서는 해당 책이 사라지고, 이동한 책장이 열린다.

### 현재 구현: 책장 간 이동 DnD 1차

현재 구현은 안전한 책장 간 이동을 우선한다.

구현된 동작:

- self의 Library 화면에서만 책 카드를 드래그할 수 있다.
- 책 카드를 책장 인덱스에 직접 드롭하면 해당 책장으로 이동한다.
- 이동은 기존 `BookshelfEntriesController#move`와 `PATCH /bookshelf_entries/:id/move`를 사용한다.
- 새 이동 endpoint는 추가하지 않는다.
- 기존 select 기반 책 이동 fallback은 유지한다.
- 책장 인덱스 클릭은 기존 URL 기반 탭 선택 흐름을 유지한다.
- 다른 책장 인덱스 위에 일정 시간 hover하면 target 책장이 armed 상태가 된다.
- armed target이 있는 상태에서 현재 보이는 책장 영역에 드롭하면 armed target 책장으로 이동한다.
- armed target 책장의 실제 책 목록 일부를 별도 preview panel에 표시한다.
- preview panel은 현재 책 목록 grid를 제거하거나 숨기지 않고 별도 영역으로 표시한다.
- preview panel에 드롭하면 기존 책장 이동 요청으로 armed target 책장에 이동한다.
- 현재 열린 책장에 다시 드롭하면 move 요청을 보내지 않는다.
- 이동 성공 후 기존 redirect 흐름으로 target 책장을 열어 보여준다.
- drag 중에는 bookshelf section 전체나 현재 책 목록 DOM을 교체하지 않는다.
- 책장 간 이동 DnD에는 SortableJS를 사용하지 않는다.

현재 구현은 “hover 중 실제 책장 목록이 열린다”가 아니라, “hover한 책장을 이동 대상으로 지정한 뒤 drop 성공 후 해당 책장을 연다”에 가깝다.

이 방식은 drag 중 원본 책 카드 DOM이 사라지는 문제를 피하기 위한 안전한 1차 구현이다.

### 최종 목표: 실제 hover open

최종 UX에서는 책 카드를 드래그한 상태에서 책장 인덱스 위에 hover하면, 화면의 책 목록 영역이 해당 책장으로 열린 것처럼 보여야 한다.

목표 동작:

1. 책 카드를 드래그한다.
2. 다른 책장 인덱스 위에 hover한다.
3. 해당 책장이 실제로 열린 것처럼 책 목록 영역이 바뀐다.
4. 열린 책장 영역에 책을 드롭한다.
5. 책이 그 책장으로 이동한다.
6. 이동 후 해당 책장이 열린 상태로 유지된다.

다만 이 기능을 구현할 때는 drag 중 원본 책 카드 DOM을 제거하면 안 된다.
원본 카드가 포함된 DOM을 교체하면 브라우저에 따라 drag/drop 이벤트가 끊길 수 있다.

따라서 실제 hover open 구현 시 다음 원칙을 지킨다.

- drag 중 전체 bookshelf section을 교체하지 않는다.
- drag 중 controller root, 책장 인덱스, hidden move form을 교체하지 않는다.
- 원본 책 카드 DOM을 제거하지 않는 구조를 우선 검토한다.
- 필요하면 현재 grid를 제거하지 않고 숨기거나, target grid를 같은 위치에 overlay/swap 표시하는 방식을 검토한다.
- Turbo Frame으로 전체 section을 교체하는 방식은 피한다.
- 실제 목록 교체가 불안정하면 현재 armed target 방식을 fallback으로 유지한다.

### 책장 안 책 순서 변경

책장 간 이동과 별개로, 같은 책장 안에서 책의 순서를 조정하는 기능도 필요하다.

목표 동작:

- self는 자신의 책장 안에서 책 카드 순서를 Drag and Drop으로 바꿀 수 있다.
- 순서 변경은 같은 책장 안에서 먼저 지원한다.
- 책장 간 이동과 책장 안 정렬은 기능적으로 구분한다.

책 순서 변경을 위해서는 `BookshelfEntry`에 사용자 지정 순서를 저장할 source of truth가 필요하다.

현재 foundation:

- `bookshelf_entries.position`을 도입한다.
- 같은 bookshelf scope 안에서 position을 관리한다.
- 새 책은 해당 책장의 마지막 position으로 들어간다.
- 책장 간 이동 시 target 책장의 마지막 position으로 들어간다.
- `sort=manual`일 때 `position ASC, id ASC`로 정렬한다.
- `PATCH /bookshelf_entries/reorder`는 같은 책장 안 전체 BookshelfEntry id를 전달받아 position을 재배정한다.
- reorder 요청은 owner만 가능하며, 다른 책장/다른 사용자 entry id가 섞이거나 id가 누락되면 실패한다.
- sort가 `manual`이고 owner 화면일 때만 책 카드에 정렬 handle을 표시한다.
- 정렬 handle을 드래그하면 같은 책장 안 카드 순서를 바꾸고 기존 reorder endpoint로 저장한다.
- 책 카드 본문 drag는 책장 간 이동 DnD 역할을 유지한다.
- 본인 Library의 기본 정렬은 `manual`이다.
- visitor / book_friend 등 타인이 보는 Library의 기본 정렬은 `recent`이다.
- 제목순, 저자순, 최근 추가순 같은 정렬은 별도 보기 옵션으로 유지할 수 있다.
- 책 순서 DnD 1차는 SortableJS를 사용한다.

controller 역할은 분리한다.

- `bookshelf_dnd_controller`: 책장 간 이동
- `bookshelf_entries_sort_controller`: 같은 책장 안 책 순서 변경

### 단계별 구현 순서

1. 책장 간 이동 DnD 1차를 안정화한다.
   - 책장 인덱스 직접 drop
   - armed hover target
   - 기존 select fallback 유지
2. 실제 hover open 구조를 실험한다.
   - drag 중 원본 책 카드 DOM을 제거하지 않는 방식만 검토한다.
   - 전체 bookshelf section 교체는 금지한다.
   - 현재 armed hover 방식은 fallback으로 유지한다.
3. hover open이 안정적이면 책장 간 이동 UX를 보강한다.
   - 책장 인덱스 hover 시 target 책장이 열린 것처럼 표시
   - 열린 책장 영역에 drop
   - 이동 후 target 책장 유지
4. 책장 안 책 순서 변경 1차를 유지한다.
   - `BookshelfEntry` position 기반 저장
   - reorder endpoint
   - SortableJS 기반 정렬 handle UI
   - 모바일/접근성 fallback 검토
 
아직 하지 않는 것:
 
- 책장 인덱스 자체 순서 변경
- hover 중 전체 bookshelf section 교체
- Turbo Frame으로 책장 영역 전체 교체
- 책장별 상시 미리보기 UI 또는 책장별 미리보기 확장 화면
- 모바일 전용 고급 DnD 구현
- 기존 select 이동 UI 제거
- 한 책을 여러 책장에 중복 저장

### 브라우저 스모크 체크리스트

- `sort=manual`에서 owner에게만 순서 변경 handle이 보인다.
- 순서 변경 후 새로고침해도 같은 순서가 유지된다.
- `recent`, `title`, `author`, `status` 정렬에서는 순서 변경 handle이 숨겨진다.
- 책장 인덱스 직접 drop으로 책장 간 이동이 동작한다.
- 책장 인덱스 hover 시 preview panel이 표시되고, panel drop으로 이동할 수 있다.
- 기존 select 기반 책 이동 fallback이 계속 동작한다.
 
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

## 일반 책장 순서 변경 UI

책장 순서 변경 UI는 본인 프로필에서 선택된 일반 책장에만 노출한다.

- 기본 책장 “내 책장”은 항상 첫 번째이며 이동할 수 없다.
- 일반 책장은 `position ASC, id ASC`로 정렬한다.
- 새 일반 책장은 마지막 `position`으로 생성한다.
- 위로 이동하면 이전 일반 책장과 `position`을 교환한다.
- 아래로 이동하면 다음 일반 책장과 `position`을 교환한다.
- 첫 번째 일반 책장은 위로 이동할 수 없다.
- 마지막 일반 책장은 아래로 이동할 수 없다.
- 이동 성공 후 현재 책장 탭을 유지한다.
- 다른 사용자의 책장은 이동할 수 없다.
- 일반 책장 자체의 순서 변경에는 drag & drop이나 Stimulus controller를 도입하지 않는다.

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
- 선택한 일반 책장 위/아래 이동 UI

### accepted book_friend

책친구는 다음을 볼 수 있다.

- public + book_friends 책장 탭
- 책 목록
- 상태/스티커
- 책 이동 select는 볼 수 없음
- 일반 책장 생성 form은 볼 수 없음
- 책장 수정/삭제 UI는 볼 수 없음
- 책장 순서 변경 UI는 볼 수 없음

### stranger / follow-only

stranger/follow-only는 다음을 볼 수 있다.

- public 책장 탭
- 책 목록
- 상태/스티커는 볼 수 없음
- 책 이동 select는 볼 수 없음
- 일반 책장 생성 form은 볼 수 없음
- 책장 수정/삭제 UI는 볼 수 없음
- 책장 순서 변경 UI는 볼 수 없음

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
- 나머지 일반 책장은 `position ASC, id ASC`

---

## 책 카드 정렬

책장 안의 책 목록은 query parameter 기반 정렬을 지원한다.

```text
/users/:id?bookshelf_id=3&sort=title
```

지원 값:

- `recent`: 기존 `recent_first` 흐름
- `title`: 책 제목순
- `author`: 저자순
- `status`: 상태순

정책:

- 본인 Library의 기본 정렬은 `manual`이다.
- visitor / book_friend 등 타인이 보는 Library의 기본 정렬은 `recent`이다.
- 허용되지 않은 `sort` 값은 기본 정렬 정책으로 fallback한다.
- 책장 탭 이동 시 현재 `sort` 값을 유지한다.
- 정렬은 선택된 책장 안의 접근 가능한 책 목록에만 적용한다.
- 책 순서 변경 handle은 owner 화면에서 `sort=manual`일 때만 표시한다.
- `recent`, `title`, `author`, `status` 정렬에서는 책 순서 변경 handle을 숨긴다.
- 상태/스티커 노출 정책과 책장 visibility 정책은 바꾸지 않는다.
- JavaScript 없이 동작해야 한다.

---

## 책장 색상

현재는 `Bookshelf.color_key` 방식으로 제한된 palette key만 선택한다.

이유:

- 디자인이 깨지는 것을 막을 수 있다.
- 접근성과 가독성을 관리하기 쉽다.
- Tailwind 스타일과 연결하기 쉽다.

---

## 별도 spec으로 다룰 확장 범위

아래 기능은 이 문서에 계속 누적하지 않고, 필요하면 별도 spec 문서 또는 해당 브랜치에서 구체화한다.

- 책장 삭제 시 안의 책 처리 정책
- 실제 hover open 실험
- 책장 안 책 순서 Drag and Drop
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

### 책장 순서 변경

1. 기본 책장은 항상 첫 번째로 정렬된다.
2. 일반 책장은 `position` 순으로 정렬된다.
3. 새 일반 책장은 마지막 `position`으로 생성된다.
4. owner는 일반 책장을 위/아래로 이동할 수 있다.
5. 기본 책장과 다른 사용자의 책장은 이동할 수 없다.
6. 첫 번째 일반 책장 위 이동과 마지막 일반 책장 아래 이동은 순서를 깨뜨리지 않는다.
7. 본인 프로필의 일반 책장에는 가능한 위/아래 이동 버튼이 보인다.
8. 기본 책장과 타인 프로필에서는 위/아래 이동 버튼이 보이지 않는다.
9. 이동 후 해당 책장 탭으로 redirect된다.

### 책 목록 정렬

1. `sort` 파라미터가 없으면 기존 `recent_first` 정렬을 유지한다.
2. `sort=title`이면 책 제목순으로 표시된다.
3. `sort=author`이면 저자순으로 표시된다.
4. `sort=status`이면 상태순으로 표시된다.
5. 허용되지 않은 `sort` 값이면 `recent`로 fallback한다.
6. 정렬해도 선택된 책장 안의 책만 표시된다.
7. 정렬해도 stranger/follow-only에게 상태/스티커는 보이지 않는다.
8. 책장 탭 링크가 현재 `sort` 값을 유지한다.
9. 정렬 UI가 프로필 책장 섹션에 보인다.

---

## 관련 문서

- `docs/specs/bookshelf_foundation.md`
- `docs/architecture/current_system.md`
- `docs/architecture/authorization.md`
