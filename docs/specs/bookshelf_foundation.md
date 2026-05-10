# Bookshelf Foundation Spec

## 목적

Bookshelf Foundation은 Checkjjaek4에서 사용자의 책 목록을 “책장” 단위로 관리하기 위한 도메인 기반을 정의한다.

이 문서는 UI 세부 구현이 아니라 다음 내용을 고정한다.

- Bookshelf 모델과 관계
- 기본 책장 정책
- BookshelfEntry와 Bookshelf의 관계
- 책장 visibility 정책
- 프로필 책 목록 노출 정책
- BookActivity와 Bookshelf visibility의 분리
- 구현 시 유지해야 할 인바리언트

UI에서 책장을 어떻게 표시하고 조작할지는 `docs/specs/bookshelf_ui.md`에서 다룬다.

---

## 현재 전제

- `Book`은 전역 책 정보를 나타낸다.
- `Bookshelf`는 사용자가 책을 꽂아두는 책장이다.
- `BookshelfEntry`는 사용자와 책의 관계를 나타낸다.
- `BookshelfEntry`는 상태와 스티커 정보를 가진다.
- `BookActivity`는 `BookshelfEntry`의 상태/스티커 변화에서 발생한다.
- BookActivity는 현재 self / accepted book_friend에게만 노출한다.
- Bookshelf visibility와 BookActivity visibility는 아직 연동하지 않는다.

---

## 핵심 모델 관계

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

현재 구조에서는 `BookshelfEntry`에 `bookshelf_id`를 직접 둔다.

이번 정책에서는 다음 조인 모델을 도입하지 않는다.

- `BookshelfItem`
- `BookshelfPlacement`

즉, 하나의 `BookshelfEntry`가 하나의 `Bookshelf`에 직접 속하는 단순 구조를 유지한다.

---

## 기본 책장 정책

모든 사용자는 기본 책장 “내 책장”을 가진다.

기본 책장의 정책은 다음과 같다.

- 이름은 “내 책장”이다.
- `is_default: true`이다.
- 기본 visibility는 `public`이다.
- 사용자당 기본 책장은 하나만 존재할 수 있다.
- 기본 책장은 직접 삭제할 수 없다.
- 기본 책장의 이름은 변경할 수 없다.
- 기본 책장의 `is_default` 값을 `false`로 변경할 수 없다.
- User 삭제 시에는 해당 User의 기본 책장과 BookshelfEntry도 함께 삭제된다.
- User 삭제 시에도 Book 자체는 삭제되지 않는다.

기본 책장은 시스템 책장으로 취급한다.

---

## 한 사용자 기준 한 책은 하나의 책장에만 속한다

한 사용자의 같은 책이 여러 책장에 동시에 들어가는 것은 허용하지 않는다.

정책은 다음과 같다.

```text
User A + Book X = 하나의 BookshelfEntry
BookshelfEntry = 하나의 Bookshelf에만 속함
```

따라서 같은 책을 다른 책장에 넣고 싶다면 “중복 추가”가 아니라 기존 `BookshelfEntry.bookshelf_id`를 변경하는 “책장 이동”으로 처리한다.

새 책을 서재에 담을 때 사용자의 책장이 여러 개라면 대상 책장을 선택할 수 있다.
대상 책장을 선택하지 않으면 기본 책장 “내 책장”에 담긴다.
`bookshelf_id`가 전달되면 반드시 `current_user` 소유 책장이어야 한다.
이미 존재하는 `BookshelfEntry`를 다시 POST해도 기존 책장 소속은 덮어쓰지 않는다.

이 정책을 유지하는 이유는 다음과 같다.

- 같은 책이 여러 책장에 동시에 들어가면 상태/스티커 맥락이 흐려진다.
- BookActivity가 어느 책장 맥락에서 발생했는지 불명확해질 수 있다.
- 공개 범위가 다른 여러 책장에 같은 책이 들어갈 경우 노출 정책이 복잡해진다.
- MVP 단계에서는 단순하고 예측 가능한 구조가 더 안전하다.

---

## BookshelfEntry 인바리언트

`BookshelfEntry.user_id`와 `BookshelfEntry.bookshelf.user_id`는 항상 일치해야 한다.

```text
bookshelf_entry.user_id == bookshelf_entry.bookshelf.user_id
```

또한 한 사용자 기준 같은 책은 중복된 `BookshelfEntry`를 가질 수 없다.

```text
user_id + book_id = unique
```

이 정책은 validation과 테스트로 보강한다.

---

## Bookshelf visibility

Bookshelf는 공개 범위를 가진다.

지원하는 visibility는 다음 세 가지다.

```text
public
book_friends
private
```

| visibility | 의미 |
| --- | --- |
| `public` | 관계 없는 사용자와 follow-only 사용자도 책 목록을 볼 수 있다. |
| `book_friends` | accepted book_friend 이상만 책 목록을 볼 수 있다. |
| `private` | 본인만 볼 수 있다. |

기본 책장 “내 책장”의 visibility는 `public`이다.

기본 책장을 `public`으로 두는 이유는 다음과 같다.

- 초기 사용자는 대부분 기본 책장만 가진다.
- 기본 책장이 `book_friends`이면 stranger/follow-only 사용자가 프로필에서 책 목록을 거의 볼 수 없다.
- Checkjjaek4는 책 기반 SNS 성격을 가지므로 기본적인 발견성이 필요하다.

---

## 관계별 프로필 책장 노출

프로필에서 볼 수 있는 책장은 Bookshelf visibility를 기준으로 한다.

| viewer 관계 | 볼 수 있는 책장 |
| --- | --- |
| self | `public` + `book_friends` + `private` |
| accepted book_friend | `public` + `book_friends` |
| follow-only | `public` |
| stranger | `public` |

follow-only 사용자는 Bookshelf visibility 기준에서는 stranger와 동일하게 `public` 책장만 볼 수 있다.

---

## 책 목록 노출과 상태/스티커 노출 분리

책 목록을 볼 수 있다는 것이 상태/스티커까지 볼 수 있다는 뜻은 아니다.

| viewer 관계 | 책 제목/표지/저자 | 상태/스티커 |
| --- | --- | --- |
| self | 볼 수 있음 | 볼 수 있음 |
| accepted book_friend | 볼 수 있음 | 볼 수 있음 |
| follow-only | public 책장에 한해 볼 수 있음 | 볼 수 없음 |
| stranger | public 책장에 한해 볼 수 있음 | 볼 수 없음 |

즉, stranger/follow-only는 public 책장의 책 제목, 표지, 저자 정도만 볼 수 있다.  
하지만 상태 배지와 스티커는 볼 수 없다.

---

## BookActivity visibility

BookActivity visibility는 Bookshelf visibility와 아직 연동하지 않는다.

현재 정책은 다음과 같다.

- self는 자신의 BookActivity를 볼 수 있다.
- accepted book_friend는 상대의 BookActivity를 볼 수 있다.
- follow-only는 상대의 BookActivity를 볼 수 없다.
- stranger는 상대의 BookActivity를 볼 수 없다.

즉, 책장이 `public`이어도 BookActivity는 public으로 열지 않는다.

아래 내용은 후속 판단으로 남긴다.

- Bookshelf visibility와 BookActivity visibility 연동
- BookActivity visibility snapshot 저장
- action별 BookActivity visibility 분리
- books/:id timeline에 BookActivity 추가

---

## 사용자별 책 문맥 화면

현재 `/books/:id`는 전역 책 상세 화면이다.

아래와 같은 사용자별 책 문맥 화면은 아직 만들지 않는다.

```text
/users/:user_id/books/:book_id
```

사용자별 책 문맥 화면은 책장/visibility 정책이 더 안정된 뒤 후속으로 판단한다.

---

## Rails enum 주의사항

Bookshelf visibility 값은 다음 세 가지를 사용한다.

```text
public
book_friends
private
```

다만 `public`과 `private`은 Ruby/Rails 메서드명과 충돌할 수 있다.

따라서 Rails enum을 정의할 때는 prefix 또는 suffix를 사용해 충돌을 피한다.

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

정확한 구현 방식은 현재 Rails 버전과 기존 enum 스타일을 따른다.

---

## 테스트 기준

최소한 다음 정책은 테스트로 고정한다.

1. User 생성 시 기본 Bookshelf가 생성된다.
2. 기본 Bookshelf 이름은 “내 책장”이다.
3. 기본 Bookshelf visibility는 `public`이다.
4. 기본 Bookshelf는 `is_default: true`이다.
5. 사용자당 기본 Bookshelf는 하나만 존재할 수 있다.
6. 기본 Bookshelf는 직접 삭제할 수 없다.
7. 기본 Bookshelf 이름은 변경할 수 없다.
8. 기본 Bookshelf의 `is_default` 값을 `false`로 바꿀 수 없다.
9. User 삭제 시 해당 User의 Bookshelf와 BookshelfEntry는 삭제된다.
10. User 삭제 시 Book은 삭제되지 않는다.
11. BookshelfEntry는 자신의 User의 Bookshelf에만 속할 수 있다.
12. 한 사용자 기준 같은 `book_id`의 BookshelfEntry가 중복 생성되지 않는다.
13. visibility scope가 self / accepted book_friend / stranger 기준으로 동작한다.
14. BookActivity visibility 기존 정책이 깨지지 않는다.

---

## 구현 시 주의사항

- Rails way를 우선한다.
- 과한 추상화를 피한다.
- 작은 diff를 우선한다.
- 기존 `BookshelfEntry.user_id`는 당장 제거하지 않는다.
- `BookshelfEntry`에 `bookshelf_id`를 직접 둔다.
- 조인 모델은 도입하지 않는다.
- BookActivity visibility는 건드리지 않는다.
- Notification과 연결하지 않는다.
- 빌드 산출물을 커밋하지 않는다.

커밋하지 말아야 할 예:

```text
app/assets/builds/tailwind.css
```

---

## 관련 문서

- `docs/specs/bookshelf_ui.md`
- `docs/architecture/current_system.md`
- `docs/architecture/authorization.md`
