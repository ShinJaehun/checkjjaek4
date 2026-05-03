# Bookshelf MVP Spec

## 목적

Bookshelf MVP는 Checkjjaek4에서 사용자의 책 목록을 “책장” 단위로 관리하기 위한 foundation 작업이다.

현재 `BookshelfEntry`는 사용자가 어떤 책을 자신의 서재에 담았는지, 그리고 그 책에 어떤 상태/스티커를 부여했는지를 표현한다.

이번 MVP에서는 여기에 `Bookshelf` 개념을 추가하여 다음을 가능하게 한다.

- 모든 사용자는 기본 책장 “내 책장”을 가진다.
- 기존 `BookshelfEntry`는 각 사용자의 기본 책장에 연결된다.
- 책장 단위 visibility 정책을 준비한다.
- 향후 여러 책장, 책장 이동, 책장별 공개 범위 기능을 확장할 수 있는 기반을 만든다.

이번 작업은 foundation 단계이며, UI 확장보다 데이터 구조와 기본 정책 정리를 우선한다.

---

## 현재 전제

- `Book`은 전역 책 정보를 나타낸다.
- `BookshelfEntry`는 사용자와 책의 관계를 나타낸다.
- `BookshelfEntry`는 상태와 스티커 정보를 가진다.
- `BookActivity`는 `BookshelfEntry`의 상태/스티커 변화에서 발생한다.
- BookActivity 1차 MVP는 이미 구현되어 있다.
- BookActivity는 현재 self / accepted book_friend에게만 노출한다.
- Bookshelf visibility와 BookActivity visibility는 이번 MVP에서 연동하지 않는다.

---

## 핵심 정책

## 1. Bookshelf 모델을 도입한다

`Bookshelf`는 사용자가 책을 꽂아두는 책장이다.

관계는 다음과 같다.

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

모든 사용자는 기본 책장을 가진다.

기본 책장 이름은 다음과 같다.

```text
내 책장
```

기본 책장의 visibility는 `public`이다.

기본 책장은 시스템 책장으로 취급한다.

- 사용자당 기본 책장은 하나만 존재한다.
- 기본 책장은 삭제할 수 없다.
- 기본 책장의 이름은 변경할 수 없다.
- 다만 User가 삭제될 때는 해당 User의 기본 책장과 BookshelfEntry도 함께 삭제된다.
- 이때 Book 자체는 전역 책 데이터이므로 삭제되지 않는다.

---

## 2. 한 사용자 기준 한 책은 하나의 책장에만 속한다

Bookshelf MVP에서는 한 사용자의 같은 책이 여러 책장에 동시에 들어가는 것을 허용하지 않는다.

즉, 한 사용자 기준으로 `Book` 하나는 하나의 `BookshelfEntry`만 가진다.
그리고 하나의 `BookshelfEntry`는 하나의 `Bookshelf`에만 속한다.

```text
User A + Book X = 하나의 BookshelfEntry
BookshelfEntry = 하나의 Bookshelf에만 속함
```

### 정책 이유

책장은 단순한 태그 묶음이 아니라, 사용자가 그 책을 어떤 맥락으로 보관하는지를 나타내는 단위다.

예를 들어 같은 책이 동시에 다음 책장에 들어갈 수 있다면:

- 내 책장
- 수업 추천 도서
- 아이들과 함께 읽은 책

그 책의 상태, 스티커, 공개 범위, BookActivity 맥락이 흐려질 수 있다.

따라서 Checkjjaek4에서는 현재 MVP 기준으로 다음 정책을 따른다.

- 같은 사용자는 같은 책을 중복해서 담을 수 없다.
- 같은 책을 다른 책장에 넣고 싶다면 “중복 추가”가 아니라 “책장 이동”으로 처리한다.
- 책장 이동 UI는 이번 MVP에서 구현하지 않는다.
- 여러 책장에 같은 책을 동시에 꽂는 기능은 이번 MVP 범위가 아니며, 현재 정책상 지원하지 않는다.

### 제약 방향

기존 `bookshelf_entries`에 `user_id + book_id` 유니크 제약이 있다면 유지한다.

없다면 이번 작업에서 현재 제약 상태를 확인하고, 한 사용자 기준 같은 책이 중복 생성되지 않도록 제약 추가 여부를 검토한다.

또한 `BookshelfEntry.user_id`와 `BookshelfEntry.bookshelf.user_id`는 항상 일치해야 한다.

```text
bookshelf_entry.user_id == bookshelf_entry.bookshelf.user_id
```

이 인바리언트는 모델 validation 또는 테스트로 보강한다.

### 이번 MVP에서 도입하지 않는 구조

이번 MVP에서는 다음과 같은 조인 모델을 도입하지 않는다.

- `BookshelfItem`
- `BookshelfPlacement`

즉, 다음 구조는 채택하지 않는다.

```text
BookshelfEntry
  user_id
  book_id
  status
  stickers

BookshelfItem
  bookshelf_id
  bookshelf_entry_id
```

현재 MVP에서는 `bookshelf_id`를 `BookshelfEntry`에 직접 추가하는 단순 구조를 사용한다.

---

## 3. Bookshelf visibility

Bookshelf는 공개 범위를 가진다.

지원할 visibility는 다음 세 가지다.

```text
public
book_friends
private
```

의미는 다음과 같다.

| visibility | 의미 |
| --- | --- |
| `public` | 관계 없는 사용자와 follow-only 사용자도 책 목록을 볼 수 있다. |
| `book_friends` | accepted book_friend 이상만 책 목록을 볼 수 있다. |
| `private` | 본인만 볼 수 있다. |

기본 책장 “내 책장”의 visibility는 `public`이다.

이유는 다음과 같다.

- 초기 MVP에서는 대부분의 사용자가 기본 책장만 가진다.
- 기본 책장이 `book_friends`이면 stranger/follow-only 사용자가 프로필에서 책 목록을 거의 볼 수 없다.
- Checkjjaek4는 책 기반 SNS 성격을 가지므로 기본적인 발견성이 필요하다.
- 따라서 기본 책장은 `public`으로 시작한다.

---

## 4. 관계별 프로필 책 목록 노출

프로필에서 책 목록을 볼 수 있는 범위는 Bookshelf visibility를 기준으로 한다.

| viewer 관계 | 볼 수 있는 책장 |
| --- | --- |
| self | `public` + `book_friends` + `private` |
| accepted book_friend | `public` + `book_friends` |
| follow-only | `public` |
| stranger | `public` |

follow-only 사용자는 Jjaek visibility 정책에서는 일부 public Jjaek을 볼 수 있지만, Bookshelf visibility에서는 stranger와 동일하게 `public` 책장만 볼 수 있다.

---

## 5. 책 목록 노출과 상태/스티커 노출은 분리한다

책 목록을 볼 수 있다는 것이 상태/스티커까지 볼 수 있다는 뜻은 아니다.

정책은 다음과 같다.

| viewer 관계 | 책 제목/표지/저자 | 상태/스티커 |
| --- | --- | --- |
| self | 볼 수 있음 | 볼 수 있음 |
| accepted book_friend | 볼 수 있음 | 볼 수 있음 |
| follow-only | public 책장에 한해 볼 수 있음 | 볼 수 없음 |
| stranger | public 책장에 한해 볼 수 있음 | 볼 수 없음 |

즉, stranger/follow-only는 public 책장의 책 제목, 표지, 저자 정도만 볼 수 있다.
하지만 상태 배지와 스티커는 볼 수 없다.

이번 foundation 브랜치에서 상태/스티커 숨김 UI가 큰 변경을 요구한다면 구현하지 않는다.
이 정책은 문서와 scope 설계에 반영하고, 실제 UI 세부 반영은 후속 작업으로 넘길 수 있다.

---

## 6. BookActivity visibility는 현재 정책을 유지한다

BookActivity visibility는 Bookshelf visibility와 이번 MVP에서 연동하지 않는다.

현재 정책은 다음과 같다.

- self는 자신의 BookActivity를 볼 수 있다.
- accepted book_friend는 상대의 BookActivity를 볼 수 있다.
- follow-only는 상대의 BookActivity를 볼 수 없다.
- stranger는 상대의 BookActivity를 볼 수 없다.

즉, 책장이 `public`이어도 BookActivity는 public으로 열지 않는다.

이번 MVP에서 하지 않는 것:

- Bookshelf visibility와 BookActivity visibility 연동
- BookActivity visibility snapshot 저장
- action별 BookActivity visibility 분리
- books/:id timeline에 BookActivity 추가

BookActivity visibility는 후속 판단으로 남긴다.

---

## 7. 사용자별 책 문맥 화면은 만들지 않는다

현재 `/books/:id`는 전역 책 상세 화면이다.

이번 MVP에서는 다음과 같은 사용자별 책 문맥 화면을 만들지 않는다.

```text
/users/:user_id/books/:book_id
```

사용자별 책 문맥 화면은 책장/visibility 정책이 안정된 뒤 후속으로 판단한다.

---

## 8. BookshelfEntry 삭제/이동과 BookActivity

이번 MVP에서는 책장 이동 UI를 만들지 않는다.

향후 책장 이동을 구현할 경우 정책은 다음 방향을 기본 후보로 둔다.

- 같은 책을 다른 책장에 넣는 것은 중복 생성이 아니라 기존 `BookshelfEntry`의 `bookshelf_id` 변경으로 처리한다.
- 책장 이동 시 BookActivity를 남길지 여부는 후속 판단한다.
- BookshelfEntry가 삭제되더라도 과거 BookActivity는 일단 유지하는 방향을 기본 후보로 둔다.
- 책장 visibility 변경 시 과거 BookActivity를 어떻게 처리할지는 후속 판단한다.

---

## MVP 1단계 구현 범위

이번 foundation 단계에서 할 일은 다음과 같다.

### 1. Bookshelf 모델 도입

- `Bookshelf` 모델 추가
- `bookshelves` 테이블 추가
- `user_id` 추가
- `name` 추가
- `visibility` 추가
- 기본 visibility는 `public`
- 기본 책장 이름은 “내 책장”

### 2. 관계 추가

- `User has_many :bookshelves`
- `User has_many :bookshelf_entries`
- `Bookshelf belongs_to :user`
- `Bookshelf has_many :bookshelf_entries`
- `BookshelfEntry belongs_to :bookshelf`

### 3. BookshelfEntry에 bookshelf_id 추가

- `bookshelf_entries` 테이블에 `bookshelf_id`를 추가한다.
- 기존 `BookshelfEntry`는 각 entry.user의 기본 Bookshelf에 연결한다.
- 기존 `user_id`는 당장 제거하지 않는다.
- `BookshelfEntry.user_id`와 `BookshelfEntry.bookshelf.user_id`가 일치해야 한다는 인바리언트를 유지한다.

### 4. 기본 책장 자동 생성

- 새 User 생성 시 기본 Bookshelf가 자동 생성되도록 한다.
- 기존 사용자에게도 기본 Bookshelf가 생기도록 데이터 보정한다.
- 기존 BookshelfEntry가 있으면 해당 사용자의 기본 Bookshelf에 연결한다.

마이그레이션에서는 현재 앱 모델의 콜백이나 validation에 과하게 의존하지 않는다.
기존 데이터가 없어도 깨지지 않아야 한다.

### 5. visibility scope 준비

프로필 책 목록에서 사용할 수 있는 Bookshelf visibility 기준 scope 또는 policy를 준비한다.

정책:

- self: `public` + `book_friends` + `private`
- accepted book_friend: `public` + `book_friends`
- stranger/follow-only: `public`

단, 이번 작업에서 프로필 UI를 크게 바꾸지 않는다.

---

## MVP 1단계에서 하지 않을 것

이번 foundation 단계에서는 다음을 하지 않는다.

- 여러 책장 생성 UI
- 책장 수정 UI
- 책장 삭제 UI
- 책 이동 UI
- BookshelfItem / BookshelfPlacement 조인 모델 도입
- BookActivity visibility 연동
- BookActivity visibility snapshot
- action별 BookActivity visibility 분리
- 사용자별 책 문맥 화면
- feed pagination
- Notification 연동
- books/:id timeline에 BookActivity 추가
- 상태/스티커 숨김 UI 대규모 변경

---

## Rails enum 주의사항

Bookshelf visibility 값은 다음 세 가지를 사용한다.

```text
public
book_friends
private
```

다만 `public`과 `private`은 Ruby/Rails 메서드명과 충돌할 수 있다.

따라서 Rails enum을 정의할 때는 안전한 방식을 사용한다.

예를 들어 DB 값은 `public`, `book_friends`, `private`를 유지하되, Rails 메서드는 prefix 또는 suffix를 붙여 충돌을 피한다.

예상 방향:

```ruby
enum :visibility,
  {
    public: "public",
    book_friends: "book_friends",
    private: "private"
  },
  prefix: true
```

정확한 구현 방식은 현재 Rails 버전과 기존 enum 스타일을 확인한 뒤 결정한다.

---

## 테스트 기준

기존 전체 RSpec은 계속 통과해야 한다.

기존 최종 상태는 다음과 같다.

```text
228 examples, 0 failures
```

실패하는 테스트를 skip/delete 하지 않는다.

최소한 다음 테스트를 추가/보강한다.

1. User 생성 시 기본 Bookshelf가 생성된다.
2. 기본 Bookshelf 이름은 “내 책장”이다.
3. 기본 Bookshelf visibility는 `public`이다.
4. 기본 Bookshelf는 `is_default: true`이다.
5. 사용자당 기본 Bookshelf는 하나만 존재할 수 있다.
6. 기본 Bookshelf는 직접 삭제할 수 없다.
7. 기본 Bookshelf 이름은 변경할 수 없다.
8. User 삭제 시 해당 User의 Bookshelf와 BookshelfEntry는 삭제된다.
9. User 삭제 시 Book은 삭제되지 않는다.
10. 기존 BookshelfEntry가 기본 Bookshelf에 연결된다.
11. BookshelfEntry의 user와 bookshelf.user가 일치해야 한다.
12. 한 사용자 기준 같은 `book_id`의 BookshelfEntry가 중복 생성되지 않는다.
13. visibility scope가 self / accepted book_friend / stranger 기준으로 동작한다.
14. BookActivity visibility 기존 정책이 깨지지 않는다.

---

## 구현 시 주의사항

- Rails way를 우선한다.
- 과한 추상화를 피한다.
- 작은 diff를 우선한다.
- 기존 UI는 가능한 한 유지한다.
- 기존 `BookshelfEntry.user_id`는 이번 단계에서 제거하지 않는다.
- `BookshelfEntry`에 `bookshelf_id`를 직접 추가한다.
- 조인 모델은 도입하지 않는다.
- BookActivity visibility는 건드리지 않는다.
- Notification과 연결하지 않는다.
- 빌드 산출물을 커밋하지 않는다.

커밋하지 말아야 할 예:

```text
app/assets/builds/tailwind.css
```

---

## 후속 작업 후보

Bookshelf MVP foundation 이후 다음 작업을 검토할 수 있다.

- 책장 생성 UI
- 책장 이름 수정
- 책장 visibility 변경
- 책장 삭제
- 책장 이동 UI
- 프로필에서 책장별 목록 표시
- stranger/follow-only에게 상태/스티커 숨김 UI 적용
- 사용자별 책 문맥 화면
- 책장 이동 시 BookActivity 기록 여부 결정
- Bookshelf visibility와 BookActivity visibility 연동 여부 결정
- BookActivity visibility snapshot 필요 여부 결정
