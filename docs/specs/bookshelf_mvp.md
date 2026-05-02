# Bookshelf MVP Policy

## 목적

이 문서는 `checkjjaek4`에서 `Bookshelf` 모델을 도입하기 전, 기본 책장 구조와 책장 공개 범위, 프로필 책 목록 노출, 상태/스티커 노출, `BookActivity` visibility, 사용자별 책 문맥 화면과의 관계를 정리한다.

현재 시스템은 `BookshelfEntry`를 중심으로 “사용자가 어떤 책을 서재에 담았는가”를 표현한다. 문서상으로는 기본 서재/기본 책장 1개처럼 해석해 왔지만, 아직 별도의 `Bookshelf` 모델은 없다.

이 문서는 이후 `Bookshelf` 모델을 실제로 도입할 때 기준이 되는 정책 문서다.

---

## 문서의 성격

이 문서는 새로운 구현 결과를 설명하는 문서가 아니다.

이 문서는 다음 구현을 준비하기 위한 제품/정책 spec이다.

- `Bookshelf` 모델 도입
- 기본 책장 생성
- 기존 `BookshelfEntry`의 기본 책장 연결
- 책장 공개 범위
- 프로필 책 목록 노출 정책
- 상태/스티커 노출 정책
- `BookActivity` visibility와의 관계
- 사용자별 책 문맥 화면 도입 시점

기존 `docs/architecture/jjaek_visibility.md`는 주로 `Jjaek` visibility 구조를 설명하는 architecture 문서다.

이 문서는 `Jjaek`이 아니라 `Bookshelf` / `BookshelfEntry` / `BookActivity`와 관련된 책장 공개 범위를 다룬다.

---

## 핵심 결정 요약

### 확정할 정책

- `Bookshelf` 모델을 도입한다.
- 모든 사용자는 기본 책장을 가진다.
- 기본 책장 이름은 `내 책장`으로 한다.
- 기본 책장의 기본 visibility는 `public`으로 한다.
- 기존 `BookshelfEntry`는 각 사용자의 기본 책장으로 이동한다.
- 초기 MVP에서는 한 사용자 기준으로 한 책은 한 책장에만 속한다.
- 여러 책장 생성 UI는 아직 만들지 않는다.
- `BookActivity` visibility는 당분간 현재처럼 `self / accepted book_friend` 기준을 유지한다.
- 사용자별 책 문맥 화면(`/users/:user_id/books/:book_id`)은 책장/visibility 정책이 안정된 뒤 후속으로 둔다.

### 후속으로 남길 정책

- 여러 책장 생성/수정/삭제 UI
- 책 이동 UI
- 책장별 상세 화면
- `BookActivity`가 책장 visibility를 따를지 여부
- `BookActivity` visibility snapshot 여부
- 사용자별 책 문맥 화면
- home/profile feed pagination 또는 limit

---

## 1. 책장 구조

### 1-1. 기본 책장을 실제 모델로 만든다

현재는 `BookshelfEntry`만 있지만, 앞으로는 `Bookshelf` 모델을 도입한다.

권장 구조:

```text
User
  has_many :bookshelves
  has_many :bookshelf_entries

Bookshelf
  belongs_to :user
  has_many :bookshelf_entries

BookshelfEntry
  belongs_to :user
  belongs_to :book
  belongs_to :bookshelf
```

`BookshelfEntry`는 계속 사용자-책 관계의 현재 상태를 저장한다.

`Bookshelf`는 그 항목들이 어떤 책장에 속하는지를 표현한다.

### 1-2. 기본 책장

모든 사용자는 기본 책장을 가진다.

기본 책장 정책:

- 이름: `내 책장`
- visibility: `public`
- 자동 생성 시점: 사용자 생성 시 또는 첫 서재 등록 시
- 삭제 가능 여부: 삭제 불가
- 이름 변경 가능 여부: 후속 판단

### 1-3. 한 책은 한 사용자 기준 한 책장에만 속한다

초기 MVP에서는 한 사용자의 한 책은 하나의 책장에만 속한다.

즉, 같은 사용자가 같은 책을 여러 책장에 동시에 넣는 기능은 만들지 않는다.

이 정책은 구현을 단순하게 유지하기 위한 것이다.

후속 단계에서 여러 책장 동시 소속이 필요해지면 별도 정책과 DB 구조를 다시 검토한다.

### 1-4. 기존 BookshelfEntry 마이그레이션

`Bookshelf` 모델을 도입하면 기존 `BookshelfEntry`는 모두 각 사용자의 기본 책장 `내 책장`에 연결한다.

마이그레이션 원칙:

- 사용자별 기본 책장을 생성한다.
- 해당 사용자의 기존 `BookshelfEntry`를 기본 책장에 연결한다.
- 기존 `BookshelfEntry`의 상태/스티커 정보는 변경하지 않는다.
- 기존 `BookActivity`는 변경하지 않는다.

---

## 2. 책장 visibility

### 2-1. visibility 종류

책장 visibility는 아래 세 가지를 후보로 둔다.

- `public`
- `book_friends`
- `private`

### 2-2. public

`public` 책장은 관계 없는 사용자와 follow-only 사용자도 책 목록을 볼 수 있다.

단, public 책장이라고 해서 상태/스티커/BookActivity까지 모두 공개하는 것은 아니다.

관계 없는 사용자와 follow-only 사용자가 볼 수 있는 정보:

- 책 제목
- 표지
- 저자
- public 책장에 들어 있는 책 목록

볼 수 없는 정보:

- 상태 배지
- 스티커
- BookActivity
- private/book_friends 책장 자체

### 2-3. book_friends

`book_friends` 책장은 accepted book_friend 이상에게만 보인다.

accepted book_friend가 볼 수 있는 정보:

- public 책장
- book_friends 책장
- 해당 책장의 책 목록
- 상태 배지
- 스티커
- BookActivity

관계 없는 사용자와 follow-only 사용자는 book_friends 책장을 볼 수 없다.

### 2-4. private

`private` 책장은 본인만 볼 수 있다.

타인은 private 책장에 있는 책의 존재도 볼 수 없다.

---

## 3. 관계별 프로필 책 목록 노출

### 3-1. stranger

아무 관계 없는 로그인 사용자는 public 책장의 책 목록만 볼 수 있다.

볼 수 있음:

- public 책장에 들어 있는 책 목록
- 책 제목
- 표지
- 저자

볼 수 없음:

- book_friends 책장
- private 책장
- 상태 배지
- 스티커
- BookActivity

### 3-2. follow-only

follow-only 사용자는 public 책장의 책 목록만 볼 수 있다.

follow는 공개 콘텐츠를 홈 피드에서 받아보는 관계이지, 책친구 공개 범위를 열어주는 관계가 아니다.

볼 수 있음:

- public 책장에 들어 있는 책 목록
- public Jjaek

볼 수 없음:

- book_friends 책장
- private 책장
- 상태 배지
- 스티커
- BookActivity

### 3-3. accepted book_friend

accepted book_friend는 public + book_friends 책장을 볼 수 있다.

볼 수 있음:

- public 책장
- book_friends 책장
- 해당 책장의 책 목록
- 상태 배지
- 스티커
- BookActivity
- public Jjaek
- book_friends Jjaek

볼 수 없음:

- private 책장

### 3-4. self

본인은 모든 책장을 볼 수 있다.

볼 수 있음:

- public 책장
- book_friends 책장
- private 책장
- 모든 책 목록
- 모든 상태/스티커
- 모든 BookActivity

---

## 4. 상태/스티커 노출 정책

책 목록 노출과 상태/스티커 노출은 분리한다.

### 원칙

- 책 목록은 책장 visibility를 따른다.
- 상태/스티커는 더 민감한 독서 기록으로 보고, `self / accepted book_friend`에게만 보여준다.

### 관계별 노출

| 관계 | 책 목록 | 상태/스티커 |
|---|---|---|
| stranger | public 책장만 | 안 보임 |
| follow-only | public 책장만 | 안 보임 |
| accepted book_friend | public + book_friends 책장 | 보임 |
| self | 전체 | 보임 |

---

## 5. BookActivity visibility

### 5-1. 현재 정책 유지

`BookActivity`는 당분간 현재 정책을 유지한다.

노출 기준:

- self
- accepted book_friend

비노출 기준:

- stranger
- follow-only

즉, public 책장에 있는 책이라도 해당 책의 BookActivity가 자동으로 public이 되지는 않는다.

### 5-2. 책장 visibility와의 연동은 후속 판단

후속 단계에서 아래 정책을 다시 검토할 수 있다.

- BookActivity가 현재 책장 visibility를 따를 것인가
- BookActivity 생성 당시 visibility를 snapshot으로 저장할 것인가
- BookActivity 자체 visibility 컬럼을 둘 것인가
- action별 visibility를 다르게 둘 것인가

### 5-3. action별 visibility 분리는 하지 않는다

초기에는 BookActivity action 종류에 따라 visibility를 나누지 않는다.

예:

- `added_to_shelf`
- `status_changed`
- `status_cleared`
- `sticker_added`
- `sticker_removed`

모두 같은 BookActivity visibility 정책을 따른다.

---

## 6. 사용자별 책 문맥 화면

### 6-1. 현재 정책

현재 `/books/:id`는 전역 책 상세 화면이다.

프로필이나 BookActivity 카드에서 책을 클릭해도 우선은 전역 `books/:id`로 이동한다.

### 6-2. 후속 후보

나중에 필요하면 아래 화면을 도입할 수 있다.

```text
/users/:user_id/books/:book_id
```

이 화면은 특정 사용자의 특정 책 기록을 보여주는 화면이다.

표시 후보:

- 그 사용자의 해당 책 Jjaek
- 그 사용자의 해당 책 BookActivity
- 현재 상태/스티커
- 책장 위치
- 공개 범위

단, 이 화면은 책장/visibility 정책이 안정된 뒤 도입한다.

---

## 7. BookActivity 삭제/수정 정책과의 관계

### 7-1. BookshelfEntry 삭제 시 BookActivity

후속 기본 후보는 유지다.

즉, `BookshelfEntry`가 삭제되더라도 과거 BookActivity는 기본적으로 유지한다.

이유:

- BookActivity는 현재 상태가 아니라 과거 활동 기록이다.
- 과거에 “읽는 중으로 바꿨다”는 사실은 이후 상태가 바뀌어도 기록으로 남을 수 있다.

단, 삭제된 책/서재항목/스티커에 대한 fallback 문구는 후속으로 정한다.

### 7-2. 상태 변경 후 과거 활동 문구

과거 활동 문구는 생성 당시 의미를 유지한다.

예:

- 과거 활동: 읽는 중으로 바꿨습니다.
- 현재 상태: 읽었어요.

이 경우 과거 활동 문구를 현재 상태에 맞춰 바꾸지 않는다.

---

## 8. Bookshelf MVP 1단계 구현 범위

### 할 것

- `Bookshelf` 모델 도입
- 사용자별 기본 책장 `내 책장` 생성
- 기본 책장의 visibility를 `public`으로 설정
- 기존 `BookshelfEntry`를 기본 책장에 연결
- 신규 `BookshelfEntry` 생성 시 기본 책장에 연결
- 프로필 책 목록 조회 scope가 책장 visibility를 고려할 수 있도록 준비
- 기존 UI는 가능한 한 그대로 유지

### 하지 않을 것

- 여러 책장 생성 UI
- `+ 책장` 버튼
- 책장 수정/삭제 UI
- 책 이동 UI
- 책장 상세 화면
- BookActivity visibility 연동
- BookActivity visibility snapshot
- 사용자별 책 문맥 화면
- Notification 연동
- feed pagination/infinite scroll

---

## 9. 다음 단계 후보

Bookshelf MVP 1단계 이후 후속 후보:

- 여러 책장 생성 UI
- 책장 공개 범위 변경 UI
- 책 이동 UI
- private/book_friends 책장 프로필 노출 정책 구체화
- BookActivity visibility와 책장 visibility 연동
- 사용자별 책 문맥 화면
- home/profile feed limit 또는 pagination

---

## 10. 관련 문서와의 관계

이 문서는 Bookshelf / 책장 visibility 정책 기준이다.

함께 읽을 문서:

- `docs/specs/bookjjaek_reboot_spec.md`
  - 제품 전체 방향
- `docs/specs/book_activity_mvp.md`
  - BookActivity 생성/노출 기준
- `docs/specs/social_relationships_mvp.md`
  - Follow / BookFriendship 관계 기준
- `docs/architecture/current_system.md`
  - 현재 구현 상태
- `docs/architecture/authorization.md`
  - 현재 권한 구조
- `docs/architecture/jjaek_visibility.md`
  - Jjaek visibility 구조

원칙:

- 이 문서는 `Jjaek` visibility를 대체하지 않는다.
- 이 문서는 Bookshelf / BookshelfEntry / BookActivity와 관련된 책장 공개 범위를 다룬다.
- `docs/architecture/jjaek_visibility.md`는 계속 Jjaek visibility 중심 architecture 문서로 유지한다.
