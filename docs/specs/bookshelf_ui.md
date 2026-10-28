# Bookshelf UI Spec

## 목적

Bookshelf UI는 사용자가 Library 화면에서 책장을 확인하고 관리하는 화면 정책을 정의한다.

이 문서는 다음 내용을 다룬다.

- Library 책장 탭 UI
- URL 기반 탭 선택
- 관계별 책장 탭 노출
- 상태/스티커 노출 정책
- 새 책 서재 담기 시 대상 책장 선택 UI
- Book 상세 라디오 배지 모달 기반 책 이동
- 책장 이동 모드
- 일반 책장 생성 UI
- 일반 책장 수정/삭제 UI
- 책장 `color_key` 표시와 선택
- 일반 책장 위/아래 순서 변경 UI
- 아직 구현하지 않은 책장 관리 UI 후보

Bookshelf의 데이터 모델, 기본 책장, visibility, BookshelfEntry 인바리언트는 `docs/specs/bookshelf_foundation.md`에서 다룬다.

---

## 기본 UI 범위

이 문서는 Library Bookshelf UI의 기본 범위를 다룬다.

1. Library 책 목록을 책장 탭으로 구분해서 보여준다.
2. URL query parameter로 선택된 책장을 유지한다.
3. viewer 관계에 따라 접근 가능한 책장 탭만 보여준다.
4. self / accepted book_friend에게는 상태/스티커를 보여준다.
5. stranger / follow-only에게는 상태/스티커를 숨긴다.
6. 새 책을 서재에 담을 때 책장이 2개 이상이면 대상 책장을 선택할 수 있다.
7. 본인은 Book 상세 화면에서 라디오 배지 모달을 사용해 책을 다른 내 책장으로 이동할 수 있다.
8. 본인은 일반 책장을 새로 만들 수 있다.
9. 본인은 일반 책장의 이름/visibility를 수정하고 빈 일반 책장을 삭제할 수 있다.
10. 본인은 일반 책장 생성/수정 시 제한된 `color_key`를 선택할 수 있다.
11. 본인은 Library 화면 안에서 일반 책장 순서를 위/아래 버튼으로 변경할 수 있다.
12. 본인은 책장 이동 모드에서 SortableJS group 기반 Drag and Drop으로 책을 다른 내 책장으로 이동할 수 있다.

아래 기능은 이 문서에 계속 누적하지 않고, 필요하면 별도 spec 문서 또는 해당 브랜치에서 구체화한다.

- 별도 책장 관리 화면

---

## 새 책 서재 담기 시 대상 책장 선택

책 검색 결과와 책 상세 read-only 화면에서 새 책을 서재에 담을 수 있다.

- 책 검색 결과의 등록 폼은 사용자의 책장이 2개 이상이면 대상 책장 select를 표시하고, 하나뿐이면 select 없이 바로 담는다.
- 책 상세 read-only 화면은 서재에 담기 모달의 단일 라디오 배지로 선택하며 기본 책장을 우선 선택한다.
- 대상 책장을 선택하지 않으면 기본 책장 “내 책장”에 담긴다.
- `bookshelf_id`가 전달되면 반드시 `current_user` 소유 책장이어야 한다.
- 이미 담긴 책은 중복 생성하지 않고, 이 흐름에서 책장 이동으로 처리하지 않는다.

---

## 공통 UI 원칙

- 책 상세의 모달 실행 버튼은 상태 표시 배지와 구별되는 각진 모서리·배경·테두리와 최소 44px 터치 영역을 사용한다.
  주요 동작은 진한 배경, 보조 동작은 밝은 배경과 테두리로 구분하며 hover·focus-visible·눌림·disabled 상태를 제공한다.
- 독서 상태·스티커 및 책 상세의 책장 선택은 라디오·체크박스를 표시하고 선택 테두리를 강조한다. 읽기 전용 배지는 기존 크기와 색상을 유지한다.
- 기본 책장 “내 책장”은 항상 첫 번째 탭으로 표시한다.
- 접근 가능한 Bookshelf만 탭으로 표시한다.
- 선택된 책장의 BookshelfEntry만 목록에 표시한다.
- 책장 탭에는 책장 이름과 책 개수를 표시한다.
- 기본 Library의 작은 화면에서는 책장 탭 대신 책장 전환 select/dropdown으로 현재 보는 책장을 바꾼다.
- 이 select/dropdown은 책장 간 이동이 아니라 현재 Library에서 볼 책장을 바꾸는 탐색 UI다.
- 책장 탭에는 접근 가능한 책장의 `color_key`를 시각적으로 반영한다.
- 책장이 많아지면 한 줄 tab/index를 유지하고 horizontal scroll과 좌우 이동 버튼으로 탐색한다.
- 작은 화면의 기본 Library에서는 tab/index 대신 책장 전환 select/dropdown을 사용한다.
- 긴 책장명은 비선택 tab에서는 ellipsis로 줄이고, 선택된 tab에서는 전체 이름을 노출한다.
- 선택된 tab은 화면 안으로 자동 가시화한다.
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

Library 책 목록을 Bookshelf 단위로 구분해서 보여준다.

- 접근 가능한 Bookshelf만 탭으로 표시한다.
- 기본 책장 “내 책장”도 하나의 탭으로 표시한다.
- 기본 책장은 항상 첫 번째 탭으로 표시한다.
- 나머지 책장은 `position` 순서를 따른다.
- 선택된 책장의 BookshelfEntry만 목록에 표시한다.
- `manual` 정렬은 BookshelfEntry의 `position` 오름차순을 사용한다.
- 본인 Library의 기본 정렬은 `manual`이다.
- visitor / book_friend 등 타인이 보는 Library의 기본 정렬은 `recent`이다.
- 탭에는 책장 이름과 책 개수를 표시한다.
- 책장이 많아지면 한 줄 tab/index를 유지하고 horizontal scroll과 좌우 이동 버튼으로 탐색한다.
- 긴 책장명은 비선택 tab에서는 ellipsis로 줄이고, 선택된 tab에서는 전체 이름을 노출한다.
- 선택된 tab은 화면 안으로 자동 가시화한다.
- 선택된 탭은 색상뿐 아니라 border, font-weight 등으로 명확히 표시한다.
- 책장 탭은 단순 filter pill이 아니라 사전 index 또는 바인더 tab처럼 보이게 한다.
- 책장 tab/index 영역은 책장 선택 역할에 집중한다.
- 선택된 책장 tab/index와 아래 책 목록 영역은 같은 accent로 시각적으로 연결한다.
- 정렬, 새 책장, 책장 관리 UI는 tab/index와 책 목록 사이의 drag 동선을 방해하지 않는 위치로 분리한다.

예상 UI:

```text
[내 책장 12] [수업 추천 5] [아이들과 읽은 책 8]
```

---

## URL 기반 탭 선택

탭 선택 상태는 JavaScript 내부 상태로만 관리하지 않는다.

query parameter를 사용한다.

```text
/users/:user_id/library?bookshelf_id=3
```

이 방식의 장점은 다음과 같다.

- 새로고침해도 선택된 책장이 유지된다.
- 브라우저 뒤로가기가 자연스럽다.
- 테스트가 쉽다.
- JavaScript 없이도 동작한다.
- 나중에 Turbo Frame으로 확장하기 쉽다.

Library 접근은 self / accepted book_friend에게만 허용한다. stranger/follow-only는 query parameter와 관계없이 프로필로 redirect되며 책장 탭을 볼 수 없다. 접근 정책은 `docs/specs/library_screen.md`를 따른다.

선택된 `bookshelf_id`가 없으면 기본 책장을 선택한다.

선택된 `bookshelf_id`가 viewer에게 허용되지 않은 책장이면, 접근 가능한 첫 번째 책장 또는 기본 책장으로 fallback한다.

---

## 관계별 책장 탭 노출

Bookshelf visibility 정책은 foundation 정책을 따른다.

| viewer 관계 | 표시 가능한 책장 탭 |
| --- | --- |
| self | `public` + `book_friends` + `private` |
| accepted book_friend | `public` + `book_friends` |
| follow-only | Library 접근 불가, 탭 비노출 |
| stranger | Library 접근 불가, 탭 비노출 |

follow-only와 stranger는 프로필의 public 책 목록 요약만 볼 수 있다. 이는 Library 내부 책장 탭 접근과 별개다.

---

## 상태/스티커 노출 정책

책장 탭을 도입하더라도 상태/스티커 노출 정책은 foundation 정책을 유지한다.

| viewer 관계 | 책 제목/표지/저자 | 상태/스티커 |
| --- | --- | --- |
| self | 볼 수 있음 | 볼 수 있음 |
| accepted book_friend | 볼 수 있음 | 볼 수 있음 |
| follow-only | 프로필의 public 책 목록 요약에서만 볼 수 있음 | 볼 수 없음 |
| stranger | 프로필의 public 책 목록 요약에서만 볼 수 있음 | 볼 수 없음 |

위 표의 stranger/follow-only 책 정보는 프로필의 public 책 목록 요약에만 적용된다. Library 책장 탭은 볼 수 없고, 프로필에서도 상태와 스티커는 볼 수 없다.

---

## Book 상세 라디오 배지 모달 기반 책 이동

본인은 자신의 BookshelfEntry를 다른 내 책장으로 이동할 수 있다.

- Library 책 카드에는 책장 이동 select/form을 표시하지 않는다.
- 책장 간 이동은 기본 Library가 아니라 `/users/:user_id/library/transfer` 책장 이동 모드에서 Drag and Drop으로 처리한다.
- Book 상세 화면에서 현재 사용자의 해당 책 BookshelfEntry가 있으면 현재 책장 이름을 보여주고, 책장이 2개 이상일 때 책장 이동 버튼으로 라디오 배지 모달을 열어 옮길 수 있다.
- 이동 모달의 라디오 배지에는 자신의 Bookshelf만 표시한다.
- 현재 책장이 기본 선택값이다.
- 다른 책장을 선택하고 이동 버튼을 누르면 기존 `BookshelfEntry.bookshelf_id`를 변경한다.
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

상단 책장 인덱스는 다음 역할을 가진다.

- 클릭하면 해당 책장을 연다.

책은 한 번에 하나의 책장에만 속한다.
기본 책장인 “내 책장”도 이동 대상이 될 수 있다.
책 이동이 성공하면 원래 책장에서는 해당 책이 사라진다.
책장 이동 모드에서 이동한 경우에는 transfer 화면의 UI source / target 조합을 유지한다.

### 현재 구현: 책장 이동 모드

현재 구현은 `/users/:user_id/library/transfer`에서 source 책장 list와 target 책장 list 두 개에만 SortableJS group을 적용하는 책장 이동 모드를 제공한다.

구현된 동작:

- self의 책장 이동 모드에서만 책 카드를 책장 간 드래그할 수 있다.
- 책 카드를 이동 대상 책장 list에 드롭하면 해당 책장으로 이동한다.
- 이동 대상 책장은 한 번에 하나만 실제 list DOM으로 렌더링한다.
- 모든 책장 list를 한 번에 DOM에 렌더링하지 않는다.
- 사용자는 source / target 책장 선택 링크로 위/아래 책장을 각각 바꿀 수 있다.
- source와 target이 같아지면 `changed=source|target` 기준으로 사용자가 바꾼 쪽은 유지하고 반대쪽을 다음 책장으로 순환 보정한다.
- 다음 책장은 책장 정렬 순서 기준으로 순환하며, 마지막 책장 다음은 첫 책장이다.
- 데스크톱/넓은 화면의 단일 책 이동은 기존 `BookshelfEntriesController#move`와 `PATCH /bookshelf_entries/:id/move`를 사용한다.
- Library 카드 안 select 기반 책 이동 fallback은 제공하지 않는다.
- 책장 인덱스 클릭은 기존 URL 기반 탭 선택 흐름을 유지한다.
- 이동 대상 책장 list 안 원하는 위치에 드롭하면 해당 위치에 삽입한다.
- 드롭된 카드의 다음 형제 entry를 `before_entry_id`로 계산한다.
- target header에 드롭하거나 마지막 위치에 드롭하면 `before_entry_id` 없이 target 책장 끝에 삽입한다.
- 위치 삽입 drop 후에는 사용자가 수동 위치를 지정한 것으로 보고 `sort=manual`로 전환한다.
- 현재 열린 책장에 다시 드롭하면 move 요청을 보내지 않는다.
- 이동 성공 후 transfer 화면의 UI source / target 조합을 유지한다.
- drag 중에는 bookshelf section 전체나 현재 책 목록 DOM을 Turbo로 교체하지 않는다.

화면 폭별 책장 이동 UX는 다음 기준을 따른다.

- 선택 기반 이동 UI는 기본 Library가 아니라 `/users/:user_id/library/transfer` 책장 이동 모드에만 노출한다.
- 작은 화면은 md 미만, 중간 화면은 md 이상 lg 미만, 큰 화면은 lg 이상으로 본다.
- 작은 화면에서는 Drag and Drop 대신 선택 기반 책장 이동 UX를 제공한다.
- 작은 화면에서는 source 책장 하나만 표시한다.
- 작은 화면에서는 책장 탭 대신 현재 source 책장 이름이 보이는 compact dropdown으로 현재 선택/정리할 책장을 바꾼다.
- 작은 화면의 target 책장 선택은 하단 action bar의 이동 버튼으로 여는 Bottom Sheet에서 제공하며 현재 source 책장은 대상에서 제외한다.
- 작은 화면에서는 책장 안 순서 변경 Drag and Drop을 제공하지 않는다.
- 작은 화면의 책장 간 이동은 selection mode 기반 bulk move로만 제공한다.
- target panel 동시 표시는 중간/큰 화면 전용이다.
- 중간/큰 화면에서는 기존 source/target 2-panel Drag and Drop UX를 유지한다.
- 모바일 진입 즉시 checkbox와 하단 action bar를 표시하고, 일반 Library와 같은 가로형 책 카드에서 선택을 시작한다.
- checkbox는 카드 오른쪽 상단에 겹쳐 표시하며 표지와 책 정보 영역을 좁히지 않는다.
- 처음 선택 권수는 0권이며, 책 카드를 여러 권 선택할 수 있다. `선택 해제`는 체크된 책만 비운다.
- selection mode에서 선택된 카드는 border/ring/background로 구분한다.
- selection mode에서 카드 영역을 탭하면 선택/해제할 수 있고, 제목 링크는 계속 책 상세로 이동한다.
- selection mode의 하단 fixed action bar에 선택 권수, 이동 버튼, 선택 해제 버튼을 표시한다. 선택 항목이 없으면 이동 버튼은 비활성화한다.
- Bottom Sheet 안에서 대상 책장 목록을 스크롤할 수 있고, 닫기·취소·바깥 영역 탭·Escape로 닫아도 선택 상태는 유지한다.
- 제출은 `PATCH /bookshelf_entries/bulk_move`를 사용한다.
- `bookshelf_entry_ids[]`는 요청 순서를 보존해 처리한다.
- `target_bookshelf_id`는 반드시 현재 사용자 소유 책장이어야 한다.
- 다른 사용자의 entry가 섞이면 거부한다.
- 같은 책장으로 이동하는 entry는 no-op으로 건너뛰고, 이동 가능한 entry만 대상 책장 끝에 순서대로 append한다.
- 선택 기반 이동은 위치 지정 삽입을 지원하지 않는다.
- 작은 화면에서 bulk move 성공 후에는 이동한 target 책장을 source로 열어 보여준다.

- 선택 기반 이동에서 특정 위치 삽입을 지원할지 별도 검토한다.

### 책장 안 책 순서 변경

책장 간 이동과 별개로, 같은 책장 안에서 책의 순서를 조정하는 기능도 필요하다.

목표 동작:

- self는 자신의 책장 안에서 PC에서는 Drag and Drop, 모바일에서는 위·아래 버튼으로 책 카드 순서를 바꿀 수 있다.
- 순서 변경은 같은 책장 안에서 먼저 지원한다.
- 책장 간 이동과 책장 안 정렬은 기능적으로 구분한다.

책 순서 변경을 위해서는 `BookshelfEntry`에 사용자 지정 순서를 저장할 source of truth가 필요하다.

현재 foundation:

- `bookshelf_entries.position`을 도입한다.
- 같은 bookshelf scope 안에서 position을 관리한다.
- 새 책은 해당 책장의 마지막 position으로 들어간다.
- 책장 간 이동 시 기본적으로 target 책장의 마지막 position으로 들어간다.
- `before_entry_id`가 함께 전달되면 target 책장 안의 해당 entry 앞에 들어간다.
- `sort=manual`일 때 `position ASC, id ASC`로 정렬한다.
- `PATCH /bookshelf_entries/reorder`는 같은 책장 안 전체 BookshelfEntry id를 전달받아 position을 재배정한다.
- reorder 요청은 owner만 가능하며, 다른 책장/다른 사용자 entry id가 섞이거나 id가 누락되면 실패한다.
- sort가 `manual`이고 owner 화면일 때 PC의 같은 목록 안 drop은 reorder로 처리한다.
- 모바일은 책이 2권 이상일 때 책장 헤더의 `순서 변경` 버튼으로 편집 모드를 연다. 편집 중 헤더에는 `순서 변경 중`을 표시하고, 하단 고정 action bar의 `취소` 또는 `적용`으로 닫는다. 마지막 카드 아래 여백에는 모바일 safe area를 반영한다.
- 위·아래 버튼은 카드 오른쪽에 겹쳐 표시하여 기존 카드 크기와 책 정보 배치를 유지한다. 첫 책의 위 버튼과 마지막 책의 아래 버튼은 비활성화한다.
- 모바일 위·아래 버튼은 화면에서 한 칸씩 이동하며 저장 요청은 보내지 않는다. `취소`는 편집 전 순서를 복원하고, 변경 사항이 없으면 `적용`은 비활성화한다.
- `적용`은 전체 책 순서를 기존 reorder endpoint로 한 번 저장한다. 저장 중 추가 조작을 막고 실패하면 새로고침해 서버 순서로 복구한다.
- PC에서 책 카드를 같은 책장 안에서 드래그하면 카드 순서를 바꾸고 기존 reorder endpoint로 저장한다.
- 기본 Library에는 책장 간 이동 UI를 두지 않는다.
- 책장 이동 모드에서는 source 책장과 target 책장 두 list 사이에 SortableJS group을 적용한다.
- 책장 이동 모드에서 책 카드를 target 책장 list에 놓으면 기존 책장 간 이동 흐름을 사용한다.
- target 책장 list 안 원하는 위치에 놓으면 `before_entry_id` 기반으로 해당 위치에 삽입한다.
- target 책장 header에 놓으면 `before_entry_id` 없이 target 책장 끝에 append한다.
- 책장 간 이동은 move endpoint, 같은 책장 안 reorder는 reorder endpoint를 사용한다.
- PC 기본 Library의 detail 카드와 책장 이동 모드의 compact 카드는 SortableJS drag source로 동작한다.
- 썸네일과 카드 여백은 drag handle로 동작한다.
- 책 제목 링크는 클릭 시 책 상세 링크로 동작한다.
- 버튼, input, select, textarea, form 같은 control 요소는 reorder drag 시작 대상에서 제외한다.
- reorder handle 밖의 책 카드 drag도 책장 간 이동 DnD 역할을 유지한다.
- 본인 Library의 기본 정렬은 `manual`이다.
- visitor / book_friend 등 타인이 보는 Library의 기본 정렬은 `recent`이다.
- 제목순, 저자순, 최근 추가순 같은 정렬은 별도 보기 옵션으로 유지할 수 있다.
- PC 책 순서 DnD는 SortableJS를 사용하고 모바일 기본 Library에서는 비활성화한다.
- 카드 안의 버튼, input, select, textarea, form 같은 control 요소에서는 drag가 시작되지 않도록 guard한다.
- 같은 목록 안 drop은 reorder, 다른 책장 list drop은 move가 되도록 이벤트 경계를 분명히 나눈다.

controller 역할은 분리한다.

- `bookshelf_transfer_controller`: 책장 이동 모드에서 source / target 책장 사이의 이동과 list 내부 manual reorder
- `bookshelf_entries_sort_controller`: 기본 Library의 단일 list manual reorder

아직 하지 않는 것:
 
- 책장 인덱스 자체 순서 변경
- hover 중 전체 bookshelf section 교체
- Turbo Frame으로 책장 영역 전체 교체
- 책장별 상시 미리보기 UI 또는 책장별 미리보기 확장 화면
- 모바일 전용 고급 DnD 구현
- 한 책을 여러 책장에 중복 저장

### 브라우저 스모크 체크리스트

- `sort=manual`에서 owner에게만 PC 순서 변경 handle과 모바일 순서 변경 버튼이 보인다.
- 순서 변경 후 새로고침해도 같은 순서가 유지된다.
- `recent`, `title`, `author`, `status` 정렬에서는 순서 변경 handle과 버튼이 숨겨진다.
- 기본 Library는 detail 카드로 고정되고 detail/compact 전환 UI가 없다.
- owner는 책장 이동 모드에 진입할 수 있다.
- 책장 이동 모드에서 source / target 책장을 각각 바꿀 수 있다.
- source와 target이 같아지면 사용자가 바꾼 쪽은 유지되고 반대쪽이 다음 책장으로 순환 보정된다.
- 썸네일과 카드 여백에서는 drag가 시작되고, 제목 링크 클릭은 책 상세로 이동한다.
- source 책장 책을 target list로 드래그해 원하는 위치에 삽입할 수 있다.
- target header에 드롭하면 target 책장 끝에 append된다.
- drag 중 카드 폭이 책장 전체로 깨지지 않는다.
- Library 카드 안에는 책장 이동 select/form이 노출되지 않고, Book 상세에서는 단일 선택 배지를 사용하는 책장 이동 모달을 제공한다.
 
---

## 일반 책장 생성 UI

사용자는 본인 Library에서 일반 책장을 새로 만들 수 있다.

### 목표

- 사용자는 본인 Library에서 새 책장을 만들 수 있다.
- 새 책장은 생성 즉시 책장 탭에 표시된다.
- 생성 성공 후 새로 만든 책장 탭으로 이동한다.

### 생성 UI 노출

책장 생성 UI는 본인 Library에서만 노출한다.

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
/users/:user_id/library?bookshelf_id=<new_bookshelf_id>
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

책장 수정/삭제 UI는 본인 Library에서 선택된 일반 책장에만 노출한다.

- 기본 책장 “내 책장”은 수정/삭제할 수 없다.
- 수정 가능한 값은 책장 이름, visibility, `color_key`로 제한한다.
- 수정 성공 후 해당 책장 탭으로 이동한다.
- 수정 실패 시 기존 책장 탭과 현재 선택된 책 목록은 계속 표시되어야 한다.
- 삭제는 빈 일반 책장만 허용한다.
- 책이 들어 있는 일반 책장은 삭제할 수 없다.
- 책이 들어 있는 일반 책장을 삭제할 때 책을 기본 책장으로 자동 이동하지 않는다.
- 책장과 함께 BookshelfEntry를 같이 삭제하지 않는다.
- 책이 들어 있는 일반 책장에는 삭제 버튼 대신 삭제 불가 안내를 표시한다.
- 삭제 가능한 일반 책장에도 삭제 전 confirm alert을 표시한다.
- 삭제 성공 후 기본 책장 또는 접근 가능한 첫 책장 탭으로 이동한다.
- 다른 사용자의 프로필에서는 수정/삭제 UI를 보여주지 않는다.

---

## 일반 책장 순서 변경 UI

책장 순서 변경 UI는 본인 Library에서 선택된 일반 책장에만 노출한다.

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
- accepted book_friend가 보는 타인 Library에서도 접근 가능한 책장 탭의 `color_key` 표시는 허용한다. 프로필에는 책장 탭을 표시하지 않는다.

### Library UX 색상 원칙

- 책 목록 전체 배경을 강하게 칠하지 않는다.
- 선택된 책장 tab/index에만 배경색 또는 accent 색을 적용한다.
- 책 목록 container에는 같은 색의 border, top border, ring, 또는 아주 옅은 tint만 적용한다.
- Drag and Drop 대상 list 상태일 때만 임시로 조금 더 강한 배경색을 사용할 수 있다.
- 책 표지와 충돌할 수 있는 진한 전체 배경색은 피한다.
- 기존 `Bookshelf.color_key`와 helper palette를 우선 활용한다.
- 필요하면 selected bookshelf panel용 accent class helper를 추가한다.

---

## Owner / Visitor UI 차이

### self

기본 UI 기준으로 본인 Library에서는 최소한 다음을 볼 수 있다.

- 접근 가능한 모든 책장 탭
- 책 목록
- 상태/스티커
- 책장 이동 모드 진입/사용
- 일반 책장 생성 form
- 선택한 일반 책장 수정/삭제 UI
- 선택한 일반 책장 위/아래 이동 UI

Library 카드 안에는 책장 이동 select/form을 두지 않는다. 책장을 하나 선택하여 확정하는 이동 모달은 Book 상세 화면에서 제공한다.

### accepted book_friend

책친구는 다음을 볼 수 있다.

- public + book_friends 책장 탭
- 책 목록
- 상태/스티커
- 책장 이동 모드에 접근할 수 없음
- 일반 책장 생성 form은 볼 수 없음
- 책장 수정/삭제 UI는 볼 수 없음
- 책장 순서 변경 UI는 볼 수 없음

### stranger / follow-only

stranger/follow-only는 Library에 접근할 수 없으며 프로필로 redirect된다. 프로필에서 다음을 볼 수 있다.

- public 책 목록 요약 (책장 탭 없음)
- 상태/스티커는 볼 수 없음
- 책장 이동 모드에 접근할 수 없음
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
/users/:user_id/library?bookshelf_id=3&sort=title
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
- 책 순서 변경 handle은 owner 화면에서 `sort=manual`일 때 PC에 표시한다. 모바일에서는 같은 조건에 책이 2권 이상이면 순서 변경 버튼을 표시한다.
- `recent`, `title`, `author`, `status` 정렬에서는 책 순서 변경 handle과 버튼을 숨긴다.
- 상태/스티커 노출 정책과 책장 visibility 정책은 바꾸지 않는다.
- 정렬 방식 선택 form은 JavaScript 없이 동작해야 한다.

정렬 UI는 tab/index와 책 목록 사이에 독립 form으로 끼우지 않고, 선택된 책장 header 오른쪽의 작은 컨트롤로 옮기는 방향을 우선한다.

---

## Library book card modes

기본 Library와 책장 이동 모드는 보기 방식을 분리한다.

- 기본 Library는 detail 카드로 고정한다.
- 책장 이동 모드는 모바일에서 가로형 detail 배치, md 이상에서 세로형 compact 배치로 고정한다.
- 보기 모드는 DB, session, 사용자 preference에 저장하지 않는다.
- 기본 Library에는 detail/compact 전환 UI를 두지 않는다.
- compact 카드는 책을 빠르게 훑고 책장 간 이동하는 데 집중한다.
- compact 카드에서도 표지는 충분히 크게 보여주고, 카드 크기와 썸네일 영역은 안정적으로 유지한다.
- 표지, 제목, 저자, 상태/별점 정도를 중심으로 compact하게 표시한다.
- detail 카드 제목은 한 줄 truncate로 표시한다.
- 저자와 출판사는 한 줄 metadata로 표시한다.
- 프로필·Library·transfer 카드의 스티커는 실제 표시 영역 너비에 맞춰 최대 6개의 아이콘을 표시하고, 공간이 부족할 때 숨겨진 개수와 이름을 제공하는 `+N`으로 요약한다.
- detail/compact 카드의 스티커는 아이콘 전용 배지로 표시하고 각각 `title`/`aria-label`로 이름을 제공한다.
- detail/compact 카드 모두 상태와 스티커는 각각 한 줄의 공간을 유지한다. 제목·메타정보·두 줄의 독서 정보는 공통 partial을 사용한다.
- detail/compact 모두 Library 카드 안에는 책장 이동 select/form을 두지 않는다.
- 책 카드 안의 버튼, input, select, textarea, form 같은 control 요소는 full-card drag 대상에서 제외한다.
- 책 제목 링크는 클릭 시 책 상세로 이동한다.

후속 검토 후보:

- detail 카드 중간 영역에 책짹 또는 BookActivity 요약을 표시할 필요가 있는지 검토한다.

---

## Library 관리 UI 분리

정렬 form, 새 책장 form, 책장 관리 form은 책장 tab/index와 책 목록 사이의 drag 동선을 방해하지 않아야 한다.

- 선택된 책장 header에는 책장 이름, 책 수, visibility, 정렬 컨트롤, 설정 버튼을 배치하는 방향을 우선한다.
- 정렬은 선택된 책장 header 오른쪽의 작은 컨트롤로 옮긴다.
- 새 책장 생성은 책장 tab/index 영역의 작은 `+` 버튼에서 modal로 진입한다.
- 선택된 일반 책장 관리는 selected bookshelf header의 “책장 관리” 버튼에서 같은 modal의 edit mode로 진입한다.
- modal markup은 페이지 안에 미리 렌더링하고, Turbo Frame fetch 없이 Stimulus로 create/edit panel 전환과 열기/닫기만 처리한다.
- create/edit modal shell은 공유하되, form action은 기존 `POST /bookshelves`, `PATCH /bookshelves/:id` 흐름을 재사용한다.
- edit mode에는 책장 이름, 공개 범위, 색상 수정과 move_up / move_down, 빈 책장 삭제 controls를 함께 둔다.
- validation 실패 시 실패한 create/edit modal을 다시 열린 상태로 렌더링하고 form errors를 표시한다.
- 기존 details 접이식 관리 영역은 제거한다.
- 책장 tab/index 영역에는 책장 선택 역할만 남긴다.
- Library 화면 상단은 프로필 card를 재사용하지 않고, 작은 avatar와 “사용자 이름의 서재” header만 둔다.

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

- modal close 후 focus return
- modal focus trap
- body scroll lock
- modal animation
- drawer 전환 또는 별도 책장 관리 화면 필요 여부
- system spec 기반 JS interaction 테스트
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
5. stranger/follow-only는 Library URL 접근 시 프로필로 redirect되며 책장 탭을 볼 수 없다.
6. 선택한 책장 탭의 책만 표시된다.
7. 허용되지 않은 `bookshelf_id`가 전달되면 접근 가능한 책장으로 fallback된다.

### 상태/스티커

1. self는 선택한 책장 안에서 상태/스티커를 볼 수 있다.
2. accepted book_friend는 선택한 책장 안에서 상태/스티커를 볼 수 있다.
3. stranger/follow-only는 프로필의 public 책 목록 요약에서 책 제목을 볼 수 있지만 상태/스티커는 볼 수 없다.

### 책 이동

1. self는 자신의 BookshelfEntry를 다른 자기 Bookshelf로 이동할 수 있다.
2. 이동 후 BookshelfEntry는 중복 생성되지 않는다.
3. 이동 후 BookshelfEntry의 `bookshelf_id`만 변경된다.
4. 다른 사용자의 BookshelfEntry는 이동할 수 없다.
5. 다른 사용자의 Bookshelf로 이동할 수 없다.
6. Library 카드 안에는 책장 이동 select/form이 보이지 않는다.
7. Book 상세의 책장 이동 모달은 self에게만 보인다.
8. 책장 이동 모드에서 이동한 경우에는 transfer 화면의 UI source / target 조합을 유지한다.

### 책장 생성

1. self는 본인 Library에서 책장 생성 form을 볼 수 있다.
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

1. self는 본인 Library에서 일반 책장 수정/삭제 UI를 볼 수 있다.
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
4. accepted book_friend가 보는 타인 Library에서는 생성/수정 UI 없이 허용된 책장 탭 색상 표시만 유지된다. 프로필에는 책장 탭이 없다.

### 책장 순서 변경

1. 기본 책장은 항상 첫 번째로 정렬된다.
2. 일반 책장은 `position` 순으로 정렬된다.
3. 새 일반 책장은 마지막 `position`으로 생성된다.
4. owner는 일반 책장을 위/아래로 이동할 수 있다.
5. 기본 책장과 다른 사용자의 책장은 이동할 수 없다.
6. 첫 번째 일반 책장 위 이동과 마지막 일반 책장 아래 이동은 순서를 깨뜨리지 않는다.
7. 본인 Library의 일반 책장에는 가능한 위/아래 이동 버튼이 보인다.
8. 기본 책장과 타인 프로필에서는 위/아래 이동 버튼이 보이지 않는다.
9. 이동 후 해당 책장 탭으로 redirect된다.

### 책 목록 정렬

1. self Library에서 `sort` 파라미터가 없으면 `manual` 정렬을 사용한다.
2. 타인이 보는 Library에서 `sort` 파라미터가 없으면 `recent` 정렬을 사용한다.
3. `sort=title`이면 책 제목순으로 표시된다.
4. `sort=author`이면 저자순으로 표시된다.
5. `sort=status`이면 상태순으로 표시된다.
6. 허용되지 않은 `sort` 값이면 self/other 기본 정렬 정책으로 fallback한다.
7. 정렬해도 선택된 책장 안의 책만 표시된다.
8. stranger/follow-only는 정렬 query parameter를 전달해도 Library에 접근할 수 없으며, 프로필 책 요약에서 상태/스티커는 보이지 않는다.
9. 책장 탭 링크가 현재 `sort` 값을 유지한다.
10. 정렬 UI는 선택된 책장 header의 컨트롤로 제공한다.

---

## 관련 문서

- `docs/specs/bookshelf_foundation.md`
- `docs/architecture/current_system.md`
- `docs/architecture/authorization.md`


## 책 상세와 개인 독서 관리

- 책 타이틀 카드는 홈 작성 폼과 같은 최대 896px(max-w-4xl) 너비 및 가운데 정렬을 사용한다. 아래 책 친구 활동·책짹 목록은 기존 최대 768px(max-w-3xl)을 유지한다.
  타이틀 카드 안에서는 모바일에서도 표지 왼쪽·서지 정보 오른쪽으로 배치하고 긴 제목·저자·출판사·ISBN은 줄바꿈한다.
  모바일 소개와 외부 상세 보기 링크는 그 아래 전체 너비로 표시하고, PC에서는 기존처럼 표지 오른쪽에 서지 정보와 소개·외부 링크를 표시한다.
  같은 책 정보와 소개를 반응형마다 중복 렌더링하지 않는다.
  책 정보·소개·외부 상세 보기 다음에 구분선 하나를 두고, 책장 정보 → 현재 독서 상태·스티커 → 오른쪽 아래 작은 `책짹` 버튼 순서로 통합한다.
  별도 내 서재·독서 활동 카드와 제목·설명은 표시하지 않는다. 기존 bookshelf_panel·reading_record_panel partial과 모달을 재사용한다.
  제목·저자·출판 정보·ISBN·API description·외부 링크를 유지한다.
  모바일의 긴 설명만 일부를 표시하고 기존 펼침·접기를 제공한다.
- 책 타이틀 카드의 표지 전용 배경·테두리·padding을 제거하고, 표지는 비율과 은은한 그림자를 유지하며 모바일에서 최대 너비 96px, md 이상에서는 기존 최대 160×224px로 표시한다.
- 홈·프로필의 일반 피드와 책 상세의 활동·책짹 목록은 최대 768px의 반응형 1열로 표시하며 본문 전체를 유지한다.
  책 상세 책짹 목록에서는 해당 책의 표지·제목·저자를 생략하고, 일반 피드의 책 정보는 유지한다.
- 서재에 없는 책은 소개, 통합 타이틀 카드의 서재에 담기 버튼, 공개 개인 원본 책짹 목록만 표시한다.
  상태·스티커와 책짹 입력 폼은 숨기며 기존 서재 등록·작성 권한을 유지한다.
- 모바일은 통합 타이틀 카드 → 책 친구 활동 → 기존 책짹 목록 순서로 세로 배치한다.
- 미등록 책은 타이틀 카드의 서재에 담기 버튼에서 기존 등록 모달을 연다. 기본 책장을 우선 선택하고 책장 배지를 하나만 선택하여 기존 등록 경로로 제출한다.
  검색 미리보기의 search_result_token과 group_id·return_to 검증을 유지한다. 등록된 책은 `담긴 책장` 옆에 현재 책장 이름을 rounded-full 색상 배지로 표시하고 오른쪽에 책장 이동 버튼을 제공한다.
  이름 배지는 기존 책장 색상 helper를 재사용하며 선택 ring 없이 해당 사용자의 서재에 bookshelf_id를 전달하는 링크다. hover·focus-visible과 긴 이름 줄바꿈을 유지한다.
  PC에서는 책장 정보와 버튼을 한 줄로 배치하며, 모바일에서도 긴 책장 이름은 줄바꿈하고 버튼은 줄어들거나 가로 스크롤을 만들지 않는다.
  책장 이동 모달은 단일 라디오 배지를 사용하며 현재 책장을 기본 선택한다. 이동 배지는 책장 색상을 유지하고 선택은 별도의 진한 ring으로 구분한다. 이동 버튼으로 기존 PATCH 경로에 bookshelf_id·return_to·group_id를 전달하고 기존 정책·오류 처리를 유지한다.
- 책짹 작성 버튼은 등록·작성 권한이 있는 사용자에게만 타이틀 카드 안에 표시하며, PC에서는 오른쪽 아래에 배치한다.
  작성 버튼과 모달 제목은 `책짹`이며 상단 오른쪽에는 닫기 버튼만 둔다. 모달 안에서는 폼의 중복 제목과 카드 테두리·둥근 모서리·그림자를 제거한다.
  작성 모달은 기존 개인·동아리 선택, 공개 범위, 200자 제한과 저장 흐름을 유지한다. 다른 화면의 작성·수정 폼은 바꾸지 않는다.
  모든 모달은 고유한 ID와 제목을 사용하고 기존 book-modal Stimulus로 닫기·Escape·포커스 복귀와 모바일 내부 스크롤을 제공한다.
  각 모달의 controller 범위를 분리하고 자동 열기·Turbo cache 처리를 유지한다.
- 통합 타이틀 카드의 책장 정보 아래에는 현재 선택된 독서 상태·스티커 배지를 모두 표시하고 자연스럽게 줄바꿈하며 오른쪽에 `독서 활동` 버튼을 둔다.
  상태·스티커가 없어도 등록된 책의 편집 버튼을 유지한다. 버튼으로 기존 독서 활동 모달을 열며 reading_state 폼에서
  상태 3종·상태 없음·스티커 선택과 전체 해제를 저장 버튼 한 번으로 반영한다.
- 서버는 항목 잠금·transaction 안에서 상태·스티커·BookActivity를 함께 저장한다.
  저장 실패 시 모두 롤백하고 HTML 응답은 제출한 선택값과 오류를 보존하여 독서 활동 모달을 다시 연다.
  인용 문맥이 있어도 이 실패 화면에서는 독서 활동 모달만 자동으로 연다. JSON 오류 응답은 현재 저장된 선택값을 유지한다.
- quote_id 인용 문맥 또는 작성 오류 화면에서는 작성 모달을 자동으로 열고 제출한 입력과 오류를 보존한다.
- 책 친구 활동은 해당 책의 공개 가능한 개인 활동·책짹 최근 3건을 별도 영역에 표시한다.
  BookActivity는 아바타·활동 문장·날짜만 표시하고, 책짹은 아바타·작성 정보·본문·원문 링크를 표시한다.
  상태·스티커 배지는 활동 당시 metadata에 기록된 변경분을 문장 안에 표시하고 현재 독서 기록으로 대체하지 않는다.
  기존 책짹 최신순 목록과 20건 무한 스크롤은 그대로 유지한다.
- 일반 작성 폼의 제목·버튼은 `책짹`, 동아리 작성 폼은 `동아리 책짹`으로 통일한다.
  동아리 폼에는 이름과 게시 대상 안내를 표시한다. 일반 폼은 공개 범위 선택을 유지하고 동아리 폼에는 표시하지 않는다.
- 새 책짹 폼은 구분되는 SVG 아이콘·라벨이 있는 두 개의 라디오 선택 카드로 `책짹` 또는 `동아리 책짹`을 선택한다. 일반 진입은 책짹,
  group_id 진입은 해당 동아리 책짹을 기본값으로 사용한다.
- 책짹 선택 시 전체 공개·책친구 공개·나만 보기의 SVG 라디오 카드를 표시한다. 기존 기본값·저장 정책은 유지한다. 동아리 책짹 선택 시 현재 게시 가능한 동아리 목록을 표시하고
  개인 공개 범위를 숨기며 전송에서 제외한다. 전환은 같은 폼 안에서 수행해 본문·선택한 공개 범위·동아리를 유지한다.
  모달 제목은 `책짹`으로 고정하고 실행 버튼은 현재 게시 위치와 일치한다. 다른 화면에서 사용하는 폼 제목과 카드는 유지한다. 게시 가능한 동아리가 없으면 게시 위치·동아리 선택을 표시하지 않고
  동아리에 게시할 수 없다는 안내와 제목 책짹, 공개 범위, 본문, 실행 버튼 책짹의 개인 폼을 제공한다. 목록은 GroupPolicy#create_jjaek?를 재사용해 제한한다.
- 새 원본 책짹은 `POST /jjaeks`에 book_post_destination(personal/group)과 기존 jjaek[group_id]를 전달한다.
  서버는 목적지와 Book, group_id의 일관성을 검증하고 현재 Group/Jjaek 작성 권한 및 개인 서재 등록을 확인한다.
  검증 실패 화면은 본문과 게시 위치·동아리·개인 공개 범위를 복원한다.
- 게시 위치 선택은 기존 동아리 공유·다시짹과 별개다. 인용 작성에는 이 선택을 제공하지 않고 기존 경로·정책을 유지한다.
  동아리 피드의 작성 선택은 `짹 / 동아리 책짹`이며 책 상세 입력 카드에는 중복 작성 선택 버튼을 두지 않는다.
- 일반 책 상세 목록은 개인 책짹 BookScope에서 기존 visibility와 서재 등록 여부를 함께 확인한다. 서재 등록 후 동아리 맥락에서는 해당 동아리의
  원본 책짹만 기존 GroupContentScope로 표시한다. 다른 동아리와 개인 목록을 혼합하지 않는다.
- 동아리 검색 → 개인 서재 담기 → 책짹 작성, 책장 이동 및 작성 실패에서도 기존 group_id 게시 맥락을 유지한다.
  소속·운영 상태·작성·조회 권한은 기존 Group/Jjaek 정책으로 강제한다.
- 활동 생성·피드 노출·항목 제거 기준은 `docs/specs/book_activity_mvp.md`를 따른다.

책 검색 단일 독립 페이지는 `docs/specs/book_search_mvp.md`를 따른다. 책 검색 대상과 책짹 게시 대상은
개념적으로 구분하며, 동아리 책장과 선행 모델은 만들지 않는다.
개인 BookshelfEntry와 BookActivity에는 동아리 소속을 추가하지 않는다.


## 독서 경험 UI

- Library 타이틀은 흰색 배경·둥근 테두리·border·shadow·padding이 있는 카드로 표시하며 아바타·사용자 이름의 서재·“책장 N개 · 총 M권”·기존 이동 버튼과 반응형 배치를 유지한다.
  개별 책장 요약은 제거한다. 책장 배열과 기존 집계 결과로 현재 접근 가능한 책장·책 수만 합산한다.
- 선택된 책장 header의 `bookshelf_visibility_badge(bookshelf)`와 기존 탭·관리·이동 정책은 유지한다.
- 독서 상태 3개는 최대 하나를 선택하는 각진 배지, 스티커 6개는 다중 선택형 둥근 배지로 구분한다.
  선택 UI와 책짹은 일관된 SVG 아이콘과 텍스트를 함께 표시하며 독서 활동 폼의 “상태 없음”으로 nil을 선택한다.
  프로필·Library 책 목록의 스티커는 기존 SVG·색상·순서를 유지한 아이콘 전용 배지로 표시한다.
  title과 접근 가능한 이름을 제공하고, 독서 상태는 아이콘·텍스트를 함께 유지한다.
- 상태와 스티커는 독서 활동 모달의 한 폼에서 선택한다.
  한 번의 저장으로 변경을 반영하고 상태 해제·스티커 전체 해제를 지원한다.
- 책 상세의 선택 UI, 프로필·Library·책짹·동아리 책짹·다시짹의 읽기 전용 UI는
  `BookshelfEntriesHelper`의 아이콘·상태 라벨·스티커 번역·배지 CSS 정의를 공유한다.
  선택 UI는 input과 저장 버튼을 사용하고 읽기 전용 UI는 공통 badge helper를 사용한다.
- 프로필·Library·transfer의 책 정보는 공통 `bookshelf_entries/card_information` partial로 표시한다.
  제목과 저자·출판사는 각각 한 줄 truncate로 표시하며 원문은 title로 제공한다.
- 상태는 첫 번째 줄에 아이콘·텍스트로, 스티커는 두 번째 줄의 실제 너비에 맞춰 작은 SVG 아이콘을 최대 6개 표시한다.
  남은 스티커는 정확한 숨김 개수와 순서를 유지한 이름 목록을 title·aria-label로 제공하는 포커스 가능한 `+N`으로 요약한다.
  공통 card_information의 sticker-overflow Stimulus가 ResizeObserver로 너비 변경과 숨겨진 carousel 페이지의 표시를 감지해 아이콘·요약 너비를 측정한다. JS 적용 전에는 기존 3개 아이콘과 요약을 제공하며, 같은 아이콘을 중복 렌더링하지 않는다.
- 책 정보 영역은 7rem, 상태·스티커 줄은 각각 1.75rem를 예약한다. 데이터가 없거나 열람 권한이 없어도 줄의 공간은 유지하되 배지·이름은 출력하지 않는다.
- 가로형 프로필·Library·모바일 transfer 카드는 9rem, md 이상에서 표지가 위에 있는 compact transfer 카드는 16rem로 통일한다.
  내용 개수에 따라 높이가 바뀌지 않으며 스티커는 줄바꿈하거나 잘라서 높이를 맞추지 않는다.
  프로필 carousel과 Library 정렬·DnD·이동 선택의 기존 속성과 동작은 유지한다.
- 위 목록 외의 책짹은 상태·스티커가 모두 없으면 표시 영역을 만들지 않는다.
- Helper는 전달된 상태·스티커의 표현만 담당하며 DB 조회나 권한 판단을 하지 않는다.
  목록의 기존 eager loading과 policy/scope 경계를 유지한다.
- 추천받은 스티커는 들어오는 화살표가 있는 말풍선, 추천하고 싶은 스티커는 밖으로 보내는 화살표로 구분한다.
- 개인·동아리 책짹은 작성자와 책에 해당하는 현재 BookshelfEntry/BookshelfEntrySticker를
  상태·스티커 배지로 간결하게 표시하며 책짹·동아리 책짹·다시짹 카드에 “현재 독서 정보” 제목은 출력하지 않는다.
  작성 당시 snapshot이나 BookActivity metadata를 사용하지 않는다.
- 현재 책장 접근 권한에 더해 본인/accepted book_friend의 상태·스티커 열람 경계를 적용한다.
  public 책장도 stranger/follow-only에게 상태·스티커를 공개하지 않는다.
- private 책장 정보는 타인에게 표시하지 않는다. 항목 제거 또는 상태·스티커가 모두 없으면 표시하지 않는다.
- 목록에서는 허용된 서재 항목과 스티커를 일괄 조회하여 카드별 추가 쿼리를 만들지 않는다.
- 상태·스티커 변경 시 실제 변경분을 BookActivity 한 건으로 기록한다. 홈·프로필 피드에는 여전히 추가 활동만 표시한다.
  책 검색 단일 독립 페이지와 책짹 작성 선택 카드는 위 책 상세 정책 및 `docs/specs/book_search_mvp.md`를 따른다.
