# Requotes MVP Spec

## 목적

이 문서는 checkjjaek4의 ReJjaek(다시짹) 기능 중,
**원본 Jjaek을 다시짹한 글 목록을 조회하는 MVP 기능**의 기준을 정리한다.

이 문서는 기존 ReJjaek 생성, visibility 제약, 알림, 피드 노출 정책을 대체하지 않는다.
개인·동아리 A·B·C 생성 규칙은 `group_sharing_requotes.md`를 따른다. 이 목록에는 현재 원문에 연결된 세 경로의 다시짹을 함께 포함한다.

이 문서가 고정하는 범위는 다음이다.

- 원본 Jjaek 카드의 “다시짹 N개”에서 진입하는 목록 조회
- 목록 접근 권한
- 목록에 표시할 ReJjaek의 visibility 기준
- MVP에서 포함하지 않을 범위

---

## 용어

### ReJjaek / 다시짹

다른 사용자의 Jjaek을 인용하고,
그 위에 내 의견을 덧붙여 새 Jjaek을 만드는 기능이다.

사용자 화면에서는 **다시짹**이라고 부른다.

코드 내부에서는 기존 이름에 맞춰 아래 용어를 사용한다.

- `requote`
- `requotes`
- `quoted_jjaek`

### 원본 Jjaek

다시짹의 대상이 되는 Jjaek이다.

기술적으로는 다음 조건을 가진다.

- `Jjaek#requote?`가 false다. 즉 `quoted_jjaek_id`가 없고 deleted-source snapshot도 없다.
- viewer가 볼 수 있어야 한다.
- 목록 조회는 원문을 현재 읽을 수 있는지로 판단한다. `private_jjaek` 원문은 작성자만 접근할 수 있다.

### ReJjaek

원본 Jjaek을 참조하는 Jjaek이다.

기술적으로는 다음 조건을 가진다.

- `quoted_jjaek_id`가 있거나 source 삭제 snapshot이 남아 있다.
- `quoted_jjaek`은 다른 ReJjaek이면 안 된다.
- 개인 다시짹 A는 원문보다 더 넓은 visibility를 가질 수 없다. B·C는 목적지 동아리의 접근 권한을 따른다.

---

## 현재 구현 기준

현재 ReJjaek 관련 핵심 구현은 아래 구조를 따른다.

- `Jjaek#requote?`
  - `quoted_jjaek_id.present? || quoted_source_deleted?`로 ReJjaek 여부를 판단한다.
  - source 삭제로 association이 제거된 deleted-source ReJjaek도 계속 ReJjaek으로 취급한다.

- `Jjaek#requotes`
  - 원본 Jjaek에 연결된 ReJjaek 목록 association이다.

- `JjaekPolicy#requote?`
  - 개인 피드에 새 다시짹을 작성할 수 있는 원문인지를 판단한다. 동아리 원본의 개인 반출은 active 공개 동아리만 허용한다.
- `JjaekPolicy#view_requotes?`
  - 원문을 현재 읽을 수 있는지와 원본 여부를 판단한다. 새 다시짹 작성 가능 여부는 요구하지 않는다.

- `JjaekPolicy::Scope`
  - viewer가 볼 수 있는 Jjaek만 반환한다.
  - ReJjaek은 quoted 원문도 viewer에게 보여야 노출된다.

- `ApplicationController#prepare_visible_requote_counts_for`
  - 원본 Jjaek 카드에 표시할 visible ReJjaek count를 계산한다.

- `Notification.notify_requote_created`
  - 다른 사용자가 내 Jjaek을 다시짹했을 때 알림을 만든다.

이번 MVP에서는 이 구조를 유지한다.

새 조회 기능을 만들기 위해 기존 생성, 알림, visibility validation 코드를 크게 이동하지 않는다.

### source 상태와 기존 ReJjaek

- 살아 있는 source가 hidden되면 기존 ReJjaek row와 `quoted_jjaek` 관계는 유지하되 일반 read scope에서는 함께 비노출한다.
  source가 restore되면 보존된 관계를 기준으로 현재 접근 권한을 다시 판단한다.
- source가 살아 있어도 viewer가 friendship, visibility 또는 Group context의 현재 read 권한을 잃으면 기존 ReJjaek도 볼 수 없다.
  과거에 source를 읽었다는 사실은 현재 source visibility를 우회하지 않으며 ReJjaek을 자동으로 private 전환하지 않는다.
- source가 hard delete되거나 tombstone이 되면 기존 ReJjaek의 `quoted_jjaek_id`를 제거하고 삭제 source snapshot을 보존하며
  ReJjaek visibility를 `private_jjaek`으로 축소한다. source 원문 body는 보존하거나 노출하지 않는다.
- deleted-source ReJjaek 자체는 삭제된 Jjaek이 아니다. 작성자 자신의 콘텐츠로 남아 일반 personal Jjaek의 수정·삭제와
  살아 있는 Jjaek에 허용되는 Comment·Like interaction 계약을 그대로 따른다.
- ReJjaek 자체의 hide/delete에도 별도 예외를 두지 않고 일반 Jjaek lifecycle/moderation 계약을 적용한다.

---

## 기능 범위

### 포함

1. 원본 Jjaek의 “다시짹 N개”에서 ReJjaek 목록으로 이동할 수 있다.
2. ReJjaek 목록 페이지에서 해당 원본을 다시짹한 글들을 볼 수 있다.
3. 일반 독자의 목록에는 현재 읽을 수 있는 ReJjaek만 표시한다. 원문 작성자는 읽을 수 없는 유효 동아리 다시짹을 제한 카드로 확인할 수 있다.
4. viewer 본인이 작성한 `private_jjaek` ReJjaek은 viewer에게 표시될 수 있다.
5. viewer가 원본 Jjaek을 볼 수 없으면 ReJjaek 목록에도 접근할 수 없다.
6. `private_jjaek` 원본 Jjaek의 목록은 원문 작성자에게만 열리며, 현재 보이는 다시짹만 표시한다.
7. ReJjaek 자체에 대해서는 다시 ReJjaek 목록을 제공하지 않는다.
8. 기존 Jjaek 카드 partial을 재사용해 목록을 렌더링한다.
9. 한 사용자는 같은 원문을 개인 피드에 한 번, 목적지 동아리별로 한 번씩 다시짹할 수 있다.
10. 다른 사용자가 같은 원문을 ReJjaek하는 것은 허용한다.

### 제외

1. ReJjaek 생성 방식 변경
2. ReJjaek notification 정책 변경
3. ReJjaek visibility validation 변경
4. ReJjaek의 ReJjaek 허용
5. modal UI
6. pagination
7. “다시짹한 사용자만” 보여주는 축약형 목록
8. 기존 홈/프로필 피드 카드 레이아웃 변경
9. 기존 ReJjaek 생성 관련 request spec 재배치
10. 기존 ReJjaek 관련 model/policy 코드 리팩토링

### 버튼 노출

- 이미 같은 원문을 ReJjaek한 사용자에게는 새 ReJjaek 버튼을 숨기거나 “내 다시짹 보기”로 대체할 수 있다.
- MVP에서는 버튼 숨김만으로 충분하다.
- 원문 자체가 ReJjaek이면 중첩 ReJjaek 금지 원칙에 따라 새 ReJjaek 버튼을 보여주지 않는다.
- deleted-source private 상태는 살아 있는 원문에 대한 중복 ReJjaek 제한과 별도 상태로 구분한다.

---

## 라우팅

MVP 라우트는 다음을 사용한다.

```ruby
resources :jjaeks, only: %i[new show create edit update destroy] do
  resources :requotes, only: :index
  resources :comments, only: %i[create update destroy]
  resource :like, only: %i[create destroy]
end
```

결과 경로:

```text
GET /jjaeks/:jjaek_id/requotes
```

path helper:

```ruby
jjaek_requotes_path(jjaek)
```

---

## 컨트롤러

새 컨트롤러를 사용한다.

```text
app/controllers/requotes_controller.rb
```

`JjaeksController`에 `requotes` 액션을 추가하지 않는다.

예상 흐름:

1. `params[:jjaek_id]`로 원본 Jjaek을 찾는다.
2. `authorize @jjaek, :view_requotes?`로 원문 목록 접근 가능 여부를 확인한다.
3. `policy_scope(Jjaek).where(quoted_jjaek_id: @jjaek.id)`로 viewer가 볼 수 있는 A·B·C 다시짹만 가져온다. 원문의 개수에도 같은 scope를 사용한다.
4. `recent` 순서로 표시한다.

예상 형태:

```ruby
class RequotesController < ApplicationController
  def index
    @jjaek = Jjaek.find(params[:jjaek_id])
    authorize @jjaek, :view_requotes?

    @requotes = policy_scope(Jjaek).where(quoted_jjaek_id: @jjaek.id)
      .includes(:user, :book, :group, :target_user, :likes, :comments, quoted_jjaek: [ :user, :book, :group ])
      .recent
  end
end
```

구현 시 실제 includes 범위는 기존 `jjaeks/_jjaek` 렌더링에 필요한 association 기준으로 조정할 수 있다.

---

## View

새 view를 사용한다.

```text
app/views/requotes/index.html.erb
```

MVP 화면 구성:

1. 제목
   - “다시짹”
   - 또는 “이 짹을 다시짹한 글”

2. 원본 Jjaek 요약
   - 기존 `jjaeks/_quoted_jjaek`을 재사용하거나,
   - 단순한 원문 요약 블록을 둔다.

3. ReJjaek 목록
   - 기존 `jjaeks/_jjaek` partial을 재사용한다.

4. 빈 상태
   - “아직 다시짹이 없습니다.”

MVP에서는 새 카드 partial을 만들지 않는다.

---

## 원본 카드의 count 링크

기존 Jjaek 카드의 `다시짹 N개` 텍스트는 링크로 바꾼다.

현재 의미:

```text
다시짹 2개
```

변경 후 의미:

```text
다시짹 2개 → /jjaeks/:id/requotes
```

단, 일반 독자의 읽을 수 있는 다시짹과 원문 작성자의 제한 카드까지 합한 개수가 0이면 표시하지 않는다.

---

## 권한 규칙

### 원본 접근

ReJjaek 목록은 원본 Jjaek을 현재 읽을 수 있는 viewer에게 열린다. 새 다시짹 작성 가능 여부와는 독립적이다.

기준:

```ruby
authorize @jjaek, :view_requotes?
```

따라서 아래는 접근 불가다.

- 로그인하지 않은 사용자
- viewer가 볼 수 없는 원본
- 숨김·삭제된 원본
- ReJjaek 자체

### 목록 노출

목록은 아래 기준으로 가져온다.

```ruby
policy_scope(Jjaek).where(quoted_jjaek_id: @jjaek.id)
```

따라서 아래는 표시되지 않는다.

- 일반 독자가 볼 수 없는 ReJjaek. 원문 작성자에게는 숨김·삭제되지 않은 동아리 다시짹을 제한 카드로만 표시할 수 있다.
- 다른 사람의 `private_jjaek` ReJjaek
- quoted 원문 visibility 규칙을 통과하지 않는 ReJjaek

아래는 표시될 수 있다.

- `public_jjaek` ReJjaek
- viewer가 볼 수 있는 `book_friends` ReJjaek
- viewer 본인의 `private_jjaek` ReJjaek
- 읽을 수 있는 목적지 동아리의 B·C 다시짹

---

## 테스트 기준

RSpec 파일은 다음을 추가한다.

```text
spec/requests/requotes_spec.rb
```

테스트해야 할 흐름:

1. 로그인한 사용자는 visible original Jjaek의 visible ReJjaek 목록을 볼 수 있다.
2. 목록에는 ReJjaek 작성자 이름과 ReJjaek 본문이 표시된다.
3. 목록에는 viewer가 볼 수 없는 private ReJjaek이 표시되지 않는다.
4. viewer 본인의 private ReJjaek은 목록에 표시된다.
5. viewer가 볼 수 없는 original Jjaek이면 접근할 수 없다.
6. private original Jjaek은 작성자만 접근할 수 있다.
7. ReJjaek 자체에 대한 ReJjaek 목록 접근은 허용하지 않는다.
8. 로그인하지 않은 사용자는 sign-in 페이지로 redirect된다.
9. 원본 Jjaek 카드의 “다시짹 N개”는 ReJjaek 목록 링크로 렌더링된다.

---

## 구현 원칙

1. Rails 관례에 맞춰 별도 `RequotesController#index`를 둔다.
2. 목록 진입에는 `JjaekPolicy#view_requotes?`를 사용한다. 일반 카드는 기존 `policy_scope`로 제한하고, 원문 작성자의 제한 카드와 추가 개수는 같은 `RestrictedRequoteScope`를 사용한다.
3. 기존 `Jjaek#requotes` 관계와 `quoted_jjaek_id`를 재사용한다.
4. 기존 ReJjaek 생성, 검증, 알림 코드는 옮기지 않는다.
5. 홈/프로필 피드의 ReJjaek 카드 레이아웃은 변경하지 않는다.
6. 새 helper/service는 만들지 않는다.
7. 중복이 커질 때만 후속 리팩토링으로 분리한다.
8. 기존 `jjaeks_spec.rb`의 ReJjaek 생성/알림/상세 테스트는 이번 작업에서 이동하지 않는다.

---

## 후속 작업 후보

MVP 이후 아래를 검토할 수 있다.

1. ReJjaek 목록 pagination
2. “다시짹한 사용자만 보기” 축약 목록
3. modal 형태의 빠른 목록
4. ReJjaek count와 목록의 N+1 점검
5. 기존 `jjaeks_spec.rb`에 흩어진 ReJjaek 생성/알림/상세 테스트 정리
6. ReJjaek은 `book_id`를 직접 가지지 않는다는 모델 invariant 추가 여부 검토
