# BookActivity MVP

## 목적

이 문서는 checkjjaek4에서 `BookActivity`를 어떤 기준으로 기록하고
어디까지 노출할지 정리한다.

`BookActivity`는 현재 일부 구현된 모델이다.
이 문서는 현재 구현 기준과 남은 후속 판단을 함께 정리하는 canonical spec이다.

현재 checkjjaek4의 피드는 `Jjaek` 중심으로 동작한다.
`BookActivity`는 `BookshelfEntry`와 `BookshelfEntrySticker`의 변화를
피드와 프로필에서 소비하기 좋은 이벤트로 표현하기 위한 모델이다.

---

## BookActivity의 역할

`BookActivity`는 책 관련 사용자 행동을 피드와 프로필에서 보여주기 위한
활동 이벤트 모델이다.

예:

- 사용자가 책을 서재에 담았다.
- 사용자가 책의 대표 상태를 변경했다.
- 사용자가 책의 대표 상태를 비웠다.
- 사용자가 책에 스티커를 붙였다.
- 사용자가 책에서 스티커를 제거했다.

중요한 점:

- `BookActivity`는 책에 대한 본문 글이 아니다.
- `BookActivity`는 `Jjaek`을 대체하지 않는다.
- `BookActivity`는 `BookshelfEntry`의 현재 상태를 대체하지 않는다.
- `BookActivity`는 `BookshelfEntrySticker`의 현재 부착 상태를 대체하지 않는다.
- `BookActivity`는 피드 노출을 위한 이벤트 표현이다.

즉, `BookActivity`는 “현재 상태의 원본”이 아니라
“상태 변화가 있었다는 기록”이다.

---

## 책임 경계

### BookshelfEntry

`BookshelfEntry`는 사용자의 현재 서재 상태의 source of truth다.

담당:

- 사용자가 어떤 책을 자기 서재에 담았는지
- 그 책의 현재 대표 상태가 무엇인지
- 대표 상태가 없는지

예:

- 읽고 싶어요
- 읽는 중
- 읽었어요
- 상태 없음

`BookshelfEntry`는 현재 상태를 저장한다.
과거에 어떤 변화가 있었는지를 피드 이벤트로 표현하는 책임은 갖지 않는다.

### BookshelfEntrySticker

`BookshelfEntrySticker`는 사용자가 특정 서재 항목에 붙인
현재 스티커 상태의 source of truth다.

담당:

- 현재 어떤 스티커가 붙어 있는지
- 현재 어떤 스티커가 제거되어 있는지

`BookshelfEntrySticker`는 현재 부착 상태를 저장한다.
스티커 추가/제거 사건을 피드 이벤트로 표현하는 책임은 갖지 않는다.

### Jjaek

`Jjaek`은 사용자가 직접 쓴 본문 글의 source of truth다.

담당:

- 일반 짹
- 책짹
- profile-context 짹
- ReJjaek

`Jjaek`은 본문이 있는 사용자 콘텐츠다.
책 상태 변경이나 스티커 변경을 억지로 `Jjaek`으로 저장하지 않는다.

### BookActivity

`BookActivity`는 책 관련 변화에서 파생되는 피드용 이벤트다.

담당:

- 책을 서재에 담은 사건
- 대표 상태 변경 사건
- 대표 상태 비움 사건
- 스티커 추가 사건
- 스티커 제거 사건

`BookActivity`는 현재 상태를 판정하는 기준이 아니다.
현재 상태 판정은 항상 `BookshelfEntry`와 `BookshelfEntrySticker`를 기준으로 한다.

---

## MVP에서 다룰 이벤트

초기 `BookActivity` MVP에서는 아래 이벤트만 다룬다.

### 1. 책을 서재에 담음

사용자가 검색 결과나 책 상세 화면에서 책을 자기 서재에 처음 담았을 때 생성한다.

예시 문구:

- 재훈님이 『어린 왕자』를 서재에 담았습니다.

주의:

- 이미 서재에 있는 책을 다시 저장하는 경우 중복 활동을 만들지 않는다.
- 책 자체가 DB에 생성되는 것과 사용자의 서재에 담기는 것은 구분한다.
- 피드 이벤트의 기준은 “공용 Book 생성”이 아니라 “사용자의 BookshelfEntry 생성”이다.

### 2. 대표 상태를 변경함

사용자가 서재 항목의 대표 상태를 다른 값으로 변경했을 때 생성한다.

예시 문구:

- 재훈님이 『어린 왕자』를 읽는 중으로 바꿨습니다.
- 재훈님이 『어린 왕자』를 읽었어요로 바꿨습니다.

주의:

- 같은 상태로 다시 저장하는 경우 중복 활동을 만들지 않는다.
- 상태 변경 전후 값은 metadata에 기록한다.

### 3. 대표 상태를 비움

사용자가 기존 대표 상태를 비워 상태 없음으로 만들었을 때 생성한다.

예시 문구:

- 재훈님이 『어린 왕자』의 독서 상태를 비웠습니다.

주의:

- 이미 상태가 없는 항목을 다시 상태 없음으로 저장하는 경우 중복 활동을 만들지 않는다.
- 상태 비움은 상태 변경의 하위 케이스로 구현할 수도 있지만, 피드 문구는 별도로 둘 수 있다.

### 4. 스티커를 추가함

사용자가 책에 새 스티커를 붙였을 때 생성한다.

예시 문구:

- 재훈님이 『어린 왕자』에 “좋았어요” 스티커를 붙였습니다.

주의:

- 이미 붙어 있는 스티커를 다시 저장하는 경우 중복 활동을 만들지 않는다.
- 여러 스티커를 한 번에 추가한 경우, MVP에서는 스티커별 이벤트로 기록한다.

### 5. 스티커를 제거함

사용자가 책에서 기존 스티커를 제거했을 때 생성한다.

예시 문구:

- 재훈님이 『어린 왕자』에서 “좋았어요” 스티커를 제거했습니다.

주의:

- 붙어 있지 않은 스티커 제거 시도는 활동을 만들지 않는다.
- 여러 스티커를 한 번에 제거한 경우, MVP에서는 스티커별 이벤트로 기록한다.

---

## MVP에서 제외할 것

이번 `BookActivity` MVP에서 하지 않는다.

- 여러 책장 구조
- 책장별 공개 범위
- 그룹 활동
- 교실 활동
- 추천/랭킹
- 실시간 알림
- Notification 연동
- 이메일 알림
- 푸시 알림
- 복잡한 피드 정렬
- 상세한 감사 로그
- 관리자용 활동 로그
- 외부 SNS 공유
- BookActivity에 대한 댓글/좋아요/ReJjaek
- BookActivity를 직접 수정하는 UI
- BookActivity를 사용자가 직접 작성하는 기능

특히 `Notification`과는 분리한다.

`BookActivity`는 피드에 보일 수 있는 활동 이벤트이고,
`Notification`은 특정 사용자가 확인해야 할 직접 상호작용의 inbox다.

따라서 책을 서재에 담거나 상태/스티커를 바꾸는 행동은
초기 MVP에서 Notification을 만들지 않는다.

---

## 피드 노출 원칙

현재 구현에서는 `BookActivity`를 프로필의 별도 책활동 섹션에 노출한다.
home feed에는 아직 합성하지 않는다.

다만 초기 MVP에서는 Jjaek visibility보다 단순한 정책으로 시작한다.

### 기본 원칙

- `BookActivity`는 작성자인 사용자의 책 관련 활동이다.
- `BookActivity`의 actor는 활동을 일으킨 사용자다.
- `BookActivity`의 대상 책은 `Book`이다.
- 필요하면 관련 `BookshelfEntry`를 함께 참조할 수 있다.
- 피드 노출 여부는 actor와 viewer의 관계를 기준으로 판단한다.

### home feed 후보 규칙

home feed 합성은 아직 구현하지 않는다.
후속 후보:

- 내 BookActivity
- 내가 소식받는 사용자의 공개 BookActivity
- 내 책친구의 책친구 공개 BookActivity

다만 home feed 합성 전 아래를 먼저 결정해야 한다.

- BookActivity에 별도 visibility를 둘 것인지
- BookshelfEntry의 공개 범위를 따를 것인지
- 사용자 프로필/서재 공개 정책을 따를 것인지

현재는 여러 책장과 책장 공개 범위가 아직 없으므로,
MVP에서는 과한 visibility 모델을 먼저 만들지 않는다.

### profile feed 규칙

현재 구현:

- 내 프로필에서는 내 BookActivity를 볼 수 있다.
- accepted book_friend는 해당 사용자의 BookActivity를 볼 수 있다.
- 관계 없는 사용자는 해당 사용자의 BookActivity를 볼 수 없다.
- 소식받기만 한 사용자는 해당 사용자의 BookActivity를 볼 수 없다.

다만 이 규칙은 여러 책장/책장 공개 범위 도입 전까지 임시 정책이다.

### 책 상세 후보 규칙

`books/:id`에서 BookActivity를 노출할지는 후속 단계에서 별도로 결정한다.

가능한 후보:

- 전역 책 상세에서는 여러 사용자의 공개 BookActivity를 보여준다.
- 특정 사용자 프로필에서 책으로 들어온 경우에는 그 사용자의 해당 책 BookActivity만 보여준다.

다만 현재 `books/:id`는 전역 책 상세와 사용자 책 문맥이 아직 분리되어 있지 않다.
따라서 BookActivity를 책 상세에 바로 노출하면 문맥 혼동이 생길 수 있다.

초기 구현에서는 home/profile 쪽 노출을 먼저 검토하고,
책 상세 노출은 후순위로 둔다.

---

## visibility 정책 초안

`BookActivity` visibility는 아직 확정하지 않는다.

후보는 세 가지다.

### 후보 A. actor의 기본 공개 정책을 따른다

사용자별 기본 서재 공개 정책이 생기면 그 정책을 따른다.

장점:

- 단순하다.
- BookActivity마다 공개 범위를 따로 저장하지 않아도 된다.

단점:

- 과거 활동의 공개 범위가 나중에 바뀔 수 있다.
- 특정 활동만 비공개로 두기 어렵다.

### 후보 B. BookshelfEntry 공개 범위를 따른다

`BookshelfEntry` 또는 향후 `Bookshelf`의 공개 범위를 따른다.

장점:

- 서재/책장 공개 범위와 자연스럽게 연결된다.
- 여러 책장 도입 이후 확장성이 있다.

단점:

- 현재는 여러 책장/책장 공개 범위가 없어서 바로 적용하기 어렵다.

### 후보 C. BookActivity 자체 visibility를 가진다

`BookActivity`에 `public_activity`, `book_friends`, `private_activity` 같은
별도 visibility를 둔다.

장점:

- Jjaek visibility와 유사하게 명시적이다.
- 과거 이벤트의 공개 범위를 고정할 수 있다.

단점:

- 현재 단계에서는 모델과 UI가 과해질 수 있다.
- Jjaek visibility와 비슷하지만 완전히 같은 의미는 아니어서 혼동될 수 있다.

### MVP 판단

초기 MVP에서는 후보 B를 장기 방향으로 염두에 두되,
여러 책장 구조가 없으므로 단순한 관계 기반 scope로 시작한다.

즉, 처음부터 복잡한 BookActivity visibility UI를 만들지 않는다.

---

## 생성 시점

BookActivity는 사용자의 명시적 서재 변경 액션에서 생성한다.

후보 생성 위치:

- `BookshelfEntriesController#create`
- `BookshelfEntriesController#update`
- 향후 서비스 객체

초기 구현에서는 controller에 생성 로직을 직접 늘어놓기보다,
작은 도메인 메서드나 service 객체로 분리할지 검토한다.

다만 과한 추상화는 피한다.

원칙:

- BookshelfEntry 생성 성공 후 활동 생성
- BookshelfEntry 상태 변경 성공 후 활동 생성
- BookshelfEntrySticker 추가/제거 성공 후 활동 생성
- 저장 실패 시 활동 생성 안 함
- 실제 변화가 없으면 활동 생성 안 함

---

## 중복 방지

같은 저장 요청에서 실제 변화가 없으면 BookActivity를 만들지 않는다.

예:

- 이미 `reading` 상태인데 다시 `reading` 저장
- 이미 상태가 없는데 다시 상태 없음 저장
- 이미 붙어 있는 스티커를 다시 전달
- 붙어 있지 않은 스티커 제거
- 같은 책을 이미 서재에 담은 상태에서 다시 담기 요청

중복 방지의 기준은 “요청이 들어왔는가”가 아니라
“도메인 상태가 실제로 바뀌었는가”다.

---

## 삭제 / 수정 정책 초안

`BookActivity`는 현재 상태를 대체하지 않는다.

따라서 과거 활동을 반드시 현재 상태와 동기화할 필요는 없다.

예:

- 사용자가 책을 읽는 중으로 바꿨다가 나중에 읽었어요로 바꿀 수 있다.
- 이 경우 과거 “읽는 중으로 바꿈” 활동이 틀린 데이터가 되는 것은 아니다.
- 그것은 과거 시점의 활동 기록이다.

다만 아래 정책은 후속 단계에서 결정해야 한다.

### BookshelfEntry가 삭제되는 경우

후보:

1. 과거 BookActivity를 유지한다.
2. 관련 BookActivity를 숨긴다.
3. 관련 BookActivity를 삭제한다.

초기 MVP에서는 삭제 기능과 함께 판단한다.
삭제 기능이 명확하지 않다면 BookActivity 삭제 정책을 먼저 구현하지 않는다.

### Book이 삭제되는 경우

공용 `Book` 삭제는 일반 사용자 흐름에서 빈번한 기능이 아니다.
BookActivity가 `Book`을 참조한다면 삭제 제약 또는 fallback 표시가 필요할 수 있다.

초기 MVP에서는 Book 삭제에 따른 BookActivity 정책을 후순위로 둔다.

### StickerDefinition이 비활성화되는 경우

스티커 정의가 비활성화되어도 과거 활동 문구를 유지할 수 있다.
필요하면 activity 생성 시점의 sticker name snapshot을 저장할 수 있다.

초기 MVP에서는 snapshot 저장 여부를 구현 단계에서 결정한다.

---

## 데이터 설계

현재 구현 필드:

- `user_id`
  - 활동을 일으킨 사용자
- `book_id`
  - 대상 책
- `bookshelf_entry_id`
  - 관련 서재 항목
- `action`
  - 활동 종류
- `metadata`
  - 상태 변경 전후 값, 스티커 정보 등 보조 정보
- `created_at`

action 후보:

- `added_to_shelf`
- `status_changed`
- `status_cleared`
- `sticker_added`
- `sticker_removed`

metadata 후보:

- `from_status`
- `to_status`
- `sticker_definition_id`
- `sticker_name`

초기 구현에서는 필요한 최소 필드만 둔다.
나중에 리포트나 상세 감사 로그까지 고려해 과한 metadata를 먼저 넣지 않는다.

---

## UI 문구 후보

초기 문구 후보:

- `{user}님이 『{book}』를 서재에 담았습니다.`
- `{user}님이 『{book}』를 {status}로 바꿨습니다.`
- `{user}님이 『{book}』의 독서 상태를 비웠습니다.`
- `{user}님이 『{book}』에 “{sticker}” 스티커를 붙였습니다.`
- `{user}님이 『{book}』에서 “{sticker}” 스티커를 제거했습니다.`

문구는 구현 시 locale 파일로 이동한다.

---

## 테스트 기준

### Model spec

- `BookActivity`는 user, book, action이 필요하다.
- action은 허용된 값만 가진다.
- recent scope는 최신 활동부터 반환한다.
- metadata가 없어도 기본 활동은 생성될 수 있다.
- 필요한 경우 metadata에 상태/스티커 정보를 저장할 수 있다.

### Service / domain spec

- 책을 처음 서재에 담으면 `added_to_shelf` 활동이 생성된다.
- 이미 서재에 있는 책을 다시 담으려는 경우 중복 활동을 만들지 않는다.
- 상태가 변경되면 `status_changed` 활동이 생성된다.
- 상태가 비워지면 `status_cleared` 활동이 생성된다.
- 같은 상태로 다시 저장하면 활동을 만들지 않는다.
- 스티커가 추가되면 `sticker_added` 활동이 생성된다.
- 스티커가 제거되면 `sticker_removed` 활동이 생성된다.
- 스티커 목록이 바뀌지 않으면 활동을 만들지 않는다.
- 저장 실패 시 활동을 만들지 않는다.

### Policy / scope spec

- 사용자는 자기 BookActivity를 볼 수 있다.
- accepted book_friend의 BookActivity를 볼 수 있다.
- 관계 없는 사용자와 follow-only 사용자는 BookActivity를 볼 수 없다.
- 관계 없는 사용자의 비공개/책친구 범위 BookActivity는 볼 수 없다.
- home feed용 scope와 profile용 scope를 혼동하지 않는다.

### Request spec

- 서재에 담기 요청 성공 시 BookActivity가 생성된다.
- 상태 저장 요청 성공 시 실제 변경이 있을 때만 BookActivity가 생성된다.
- 스티커 저장 요청 성공 시 추가/제거된 스티커에 대해서만 BookActivity가 생성된다.
- BookActivity가 없어도 기존 BookshelfEntry 생성/수정 흐름은 계속 동작한다.

### View / feed spec

- profile feed에 접근 가능한 BookActivity가 표시된다.
- 접근 권한이 없는 BookActivity는 표시되지 않는다.
- home feed에는 아직 BookActivity가 표시되지 않는다.
- BookActivity와 Jjaek이 같은 피드에 함께 표시될 경우 시간순 정렬 기준을 따른다.

---

## 구현 상태와 남은 순서

### Step 1. 모델과 생성 규칙 `완료`

- `BookActivity` 모델 도입
- 최소 action enum 도입
- BookshelfEntry 생성/수정 성공 시 활동 생성
- 실제 변경이 없는 경우 중복 생성 방지

### Step 2. 프로필 조회 scope `완료`

- self / accepted book_friend 기준 profile scope
- 관계 기반 접근 범위 테스트

### Step 3. 프로필 표시 `완료`

- 프로필의 별도 BookActivity 섹션
- home feed에는 아직 합성하지 않음

### Step 4. 후속 피드 판단

- Jjaek 중심 피드에 BookActivity를 섞을지 별도 섹션으로 둘지 결정
- books/:id에 BookActivity를 노출할지 결정
- 여러 책장/책장 공개 범위와 visibility를 연결할지 결정

### Step 5. 문서 갱신

구현 상태가 바뀌면 아래 문서를 함께 갱신한다.

- `docs/architecture/current_system.md`
- `docs/reboot/reboot_plan.md`
- 필요한 경우 `docs/architecture/authorization.md`
- 필요한 경우 `docs/architecture/visibility.md`

---

## 결정 보류 항목

아래는 후속 단계에서 별도 판단이 필요하다.

- BookActivity에 자체 visibility 컬럼을 둘지
- 여러 책장 도입 전 임시 공개 정책을 어디까지 둘지
- home feed에 바로 섞을지, 별도 활동 섹션으로 둘지
- 책 상세에 BookActivity를 노출할지
- status/sticker 변경을 한 요청 안에서 하나의 활동으로 묶을지, 개별 활동으로 나눌지
- metadata snapshot을 어디까지 저장할지
- BookshelfEntry 삭제 시 과거 활동을 유지할지 숨길지 삭제할지

---

## 다른 문서와의 관계

이 문서는 `BookActivity`의 현재 구현 기준과 후속 판단을 다루는 기준 문서다.

함께 읽을 문서:

- `docs/specs/bookjjaek_reboot_spec.md`
  - BookActivity의 제품 방향과 책임 경계
- `docs/reboot/reboot_plan.md`
  - BookActivity가 부분 완료 상태임을 추적
- `docs/architecture/current_system.md`
  - 현재 구현된 BookActivity 흐름 확인
- `docs/architecture/authorization.md`
  - 권한 구조와 policy/scope 원칙
- `docs/architecture/visibility.md`
  - Jjaek visibility와 BookActivity 공개 정책을 혼동하지 않기 위한 참고
- `docs/specs/notifications_mvp.md`
  - BookActivity를 Notification MVP와 분리
- `docs/testing/rspec_strategy.md`
  - 테스트 기준

원칙:

- 현재 상태의 source of truth는 `BookshelfEntry`와 `BookshelfEntrySticker`다.
- 본문 글의 source of truth는 `Jjaek`이다.
- `BookActivity`는 피드용 이벤트 표현이다.
- `Notification`은 직접 상호작용 알림 inbox다.
- 이 네 책임을 서로 대체하지 않는다.
