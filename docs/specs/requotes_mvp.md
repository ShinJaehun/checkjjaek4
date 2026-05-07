# Requotes MVP Spec

## 목적

이 문서는 checkjjaek4의 ReJjaek(다시짹) 기능 중,
**원본 Jjaek을 다시짹한 글 목록을 조회하는 MVP 기능**의 기준을 정리한다.

이 문서는 기존 ReJjaek 생성, visibility 제약, 알림, 피드 노출 정책을 대체하지 않는다.

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

- `quoted_jjaek_id`가 없다.
- viewer가 볼 수 있어야 한다.
- `private_jjaek`이면 다시짹 목록 접근 대상이 아니다.

### ReJjaek

원본 Jjaek을 참조하는 Jjaek이다.

기술적으로는 다음 조건을 가진다.

- `quoted_jjaek_id`가 있다.
- `quoted_jjaek`은 다른 ReJjaek이면 안 된다.
- 원문보다 더 넓은 visibility를 가질 수 없다.

---

## 현재 구현 기준

현재 ReJjaek 관련 핵심 구현은 아래 구조를 따른다.

- `Jjaek#requote?`
  - `quoted_jjaek_id.present?`로 ReJjaek 여부를 판단한다.

- `Jjaek#requotes`
  - 원본 Jjaek에 연결된 ReJjaek 목록 association이다.

- `JjaekPolicy#requote?`
  - 원본이 viewer에게 보여야 한다.
  - 원본이 `private_jjaek`이면 안 된다.
  - 원본 자체가 ReJjaek이면 안 된다.

- `JjaekPolicy::Scope`
  - viewer가 볼 수 있는 Jjaek만 반환한다.
  - ReJjaek은 quoted 원문도 viewer에게 보여야 노출된다.

- `ApplicationController#prepare_visible_requote_counts_for`
  - 원본 Jjaek 카드에 표시할 visible ReJjaek count를 계산한다.

- `Notification.notify_requote_created`
  - 다른 사용자가 내 Jjaek을 다시짹했을 때 알림을 만든다.

이번 MVP에서는 이 구조를 유지한다.

새 조회 기능을 만들기 위해 기존 생성, 알림, visibility validation 코드를 크게 이동하지 않는다.

---

## 기능 범위

### 포함

1. 원본 Jjaek의 “다시짹 N개”에서 ReJjaek 목록으로 이동할 수 있다.
2. ReJjaek 목록 페이지에서 해당 원본을 다시짹한 글들을 볼 수 있다.
3. 목록에는 viewer가 볼 수 있는 ReJjaek만 표시한다.
4. viewer 본인이 작성한 `private_jjaek` ReJjaek은 viewer에게 표시될 수 있다.
5. viewer가 원본 Jjaek을 볼 수 없으면 ReJjaek 목록에도 접근할 수 없다.
6. `private_jjaek` 원본 Jjaek은 ReJjaek 목록 접근 대상이 아니다.
7. ReJjaek 자체에 대해서는 다시 ReJjaek 목록을 제공하지 않는다.
8. 기존 Jjaek 카드 partial을 재사용해 목록을 렌더링한다.

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
2. `authorize @jjaek, :requote?`로 접근 가능 여부를 확인한다.
3. `policy_scope(@jjaek.requotes)`로 viewer가 볼 수 있는 ReJjaek만 가져온다.
4. `recent` 순서로 표시한다.

예상 형태:

```ruby
class RequotesController < ApplicationController
  def index
    @jjaek = Jjaek.find(params[:jjaek_id])
    authorize @jjaek, :requote?

    @requotes = policy_scope(@jjaek.requotes)
      .includes(:user, :book, :target_user, :likes, :comments, quoted_jjaek: [ :user, :book ])
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

단, visible ReJjaek count가 0이면 기존처럼 표시하지 않는다.

---

## 권한 규칙

### 원본 접근

ReJjaek 목록은 원본 Jjaek을 다시짹할 수 있는 viewer에게만 열린다.

기준:

```ruby
authorize @jjaek, :requote?
```

따라서 아래는 접근 불가다.

- 로그인하지 않은 사용자
- viewer가 볼 수 없는 원본
- `private_jjaek` 원본
- ReJjaek 자체

### 목록 노출

목록은 아래 기준으로 가져온다.

```ruby
policy_scope(@jjaek.requotes)
```

따라서 아래는 표시되지 않는다.

- viewer가 볼 수 없는 ReJjaek
- 다른 사람의 `private_jjaek` ReJjaek
- quoted 원문 visibility 규칙을 통과하지 않는 ReJjaek

아래는 표시될 수 있다.

- `public_jjaek` ReJjaek
- viewer가 볼 수 있는 `book_friends` ReJjaek
- viewer 본인의 `private_jjaek` ReJjaek

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
6. private original Jjaek이면 접근할 수 없다.
7. ReJjaek 자체에 대한 ReJjaek 목록 접근은 허용하지 않는다.
8. 로그인하지 않은 사용자는 sign-in 페이지로 redirect된다.
9. 원본 Jjaek 카드의 “다시짹 N개”는 ReJjaek 목록 링크로 렌더링된다.

---

## 구현 원칙

1. Rails 관례에 맞춰 별도 `RequotesController#index`를 둔다.
2. 기존 `JjaekPolicy#requote?`와 `policy_scope`를 재사용한다.
3. 기존 `Jjaek#requotes` association을 재사용한다.
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
