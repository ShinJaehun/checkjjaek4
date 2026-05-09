# User Avatar MVP

## 상태

이 문서는 checkjjaek4의 사용자 avatar 기능을 위한 활성 하위 spec이다.

이 spec은 아래 문서를 전제로 한다.

- `docs/specs/bookjjaek_reboot_spec.md`
- `docs/architecture/current_system.md`
- `docs/reboot/reboot_plan.md`

---

## 목적

checkjjaek4에서 사용자를 시각적으로 구분할 수 있도록 기본 avatar 이미지를 도입한다.

이 단계의 목표는 다음과 같다.

- 모든 사용자에게 기본 avatar를 제공한다.
- 사용자가 직접 이미지를 업로드하지 않아도 프로필, 짹, 댓글 등에서 일관된 사용자 이미지를 보여준다.
- 기존 `suksuk_praise`의 `user_profile_XX_128.png`, `user_profile_XX_512.png` asset을 재사용한다.
- 나중에 Active Storage 기반 custom avatar로 확장할 수 있는 구조를 먼저 마련한다.
- bulk 사용자 생성 시 같은 avatar가 지나치게 몰리지 않도록 한다.

---

## 포함 범위

- 기본 avatar 이미지 asset 추가
  - `app/assets/images/avatars/user_profile_01_128.png` ~ `user_profile_32_128.png`
  - `app/assets/images/avatars/user_profile_01_512.png` ~ `user_profile_32_512.png`
- `users.default_avatar_index` 컬럼 추가
- `User` 모델의 default avatar index 검증
- 신규 사용자 생성 시 기본 avatar index 자동 배정
- avatar helper 추가
- profile header, Jjaek 카드, 댓글 등 주요 사용자 표시 위치에 avatar 표시
- 나중에 Active Storage custom avatar를 붙일 수 있도록 helper 구조 준비

---

## 제외 범위

이번 MVP에서는 아래를 구현하지 않는다.

- 사용자가 직접 avatar 이미지를 업로드하는 UI
- Active Storage custom avatar 업로드/삭제 화면
- 이미지 crop/edit UI
- 관리자용 avatar 변경 화면
- 사용자가 기본 avatar를 직접 고르는 화면
- avatar 이미지 생성/관리 기능

---

## 기본 정책

- 사용자는 하나의 `default_avatar_index`를 가진다.
- `default_avatar_index`는 1..32 범위의 정수다.
- 기본 avatar asset 파일명은 아래 규칙을 따른다.

```text
avatars/user_profile_XX_128.png
avatars/user_profile_XX_512.png
```

예:

```text
avatars/user_profile_01_128.png
avatars/user_profile_01_512.png
```

- `XX`는 2자리 zero-padding 숫자다.
- 작은 UI에서는 128px asset을 사용한다.
- profile header처럼 큰 UI에서는 512px asset을 사용할 수 있다.
- 화면에서 표시되는 실제 크기는 CSS class로 제어한다.

---

## 기본 avatar 배정 정책

신규 사용자가 생성될 때 `default_avatar_index`가 비어 있으면 자동으로 값을 배정한다.

단순 완전 랜덤 대신, 중복을 최대한 줄이기 위해 아래 방식을 사용한다.

1. 현재 사용자들의 `default_avatar_index` 사용 빈도를 계산한다.
2. 1..32 중 사용 빈도가 가장 낮은 index 후보들을 찾는다.
3. 가장 적게 사용된 후보들 중 하나를 랜덤으로 선택한다.
4. 선택한 값을 신규 사용자의 `default_avatar_index`로 저장한다.

예:

```text
1번 avatar: 3명
2번 avatar: 1명
3번 avatar: 1명
4번 avatar: 0명
...
```

이 경우 사용 빈도 0인 index들 중에서 랜덤 선택한다.

이 방식은 중복을 완전히 막지는 않는다. 다만 bulk 사용자 생성 시 특정 avatar에 지나치게 몰리는 현상을 줄인다.

---

## Active Storage 확장 정책

MVP에서는 custom avatar 업로드 UI를 만들지 않는다.

다만 나중에 확장할 수 있도록 `User` 모델에는 아래 구조를 둘 수 있다.

```ruby
has_one_attached :avatar
```

avatar 표시 helper는 아래 우선순위를 따른다.

1. 사용자가 직접 업로드한 `avatar`가 있으면 Active Storage variant를 사용한다.
2. 업로드 avatar가 없으면 `default_avatar_index` 기반 asset avatar를 사용한다.

MVP에서는 2번 기본 avatar 표시를 우선 구현한다. 1번 custom avatar 업로드 기능은 후속 작업으로 둔다.

---

## Helper 정책

avatar 출력은 view에서 직접 asset path를 조립하지 않고 helper를 사용한다.

예상 helper:

```ruby
user_avatar_path(user, size:)
user_avatar_image(user, size:, **options)
```

기본 동작:

- `user.default_avatar_index`가 1..32 범위면 해당 index를 사용한다.
- 값이 없거나 범위 밖이면 1번 avatar를 fallback으로 사용한다.
- `size: 128`이면 `user_profile_XX_128.png`를 사용한다.
- `size: 512`이면 `user_profile_XX_512.png`를 사용한다.
- 향후 `user.avatar.attached?`가 true이면 Active Storage variant를 우선 사용할 수 있다.

---

## 표시 위치

MVP에서는 아래 위치에 우선 적용한다.

### 1. Profile header

- 사용자 이름 근처에 큰 avatar를 표시한다.
- 512px asset을 사용하되, 실제 화면 크기는 CSS로 제한한다.

### 2. Jjaek 카드

- Jjaek 작성자 이름 옆에 작은 avatar를 표시한다.
- 128px asset을 사용한다.

### 3. 댓글 목록

- 댓글 작성자 이름 옆에 작은 avatar를 표시한다.
- 128px asset을 사용한다.

### 4. 알림 / 관계 화면

- MVP에서는 필수는 아니다.
- 필요하면 후속 polish에서 적용한다.

---

## 구현 원칙

- view에서 avatar 파일명을 직접 조립하지 않는다.
- helper를 통해서만 avatar 이미지를 출력한다.
- `default_avatar_index` 배정 로직은 모델 callback 또는 별도 service로 분리한다.
- bulk 사용자 생성 시에도 같은 로직을 타게 한다.
- avatar index는 사용자 생성 후 자동으로 배정되어야 한다.
- 기존 사용자에게는 migration 또는 task로 default avatar index를 backfill할 수 있어야 한다.

---

## 기존 사용자 처리

기존 사용자에게 `default_avatar_index`가 없는 경우가 생길 수 있다.

MVP에서는 migration 또는 별도 task를 통해 기존 사용자에게 값을 채운다.

처리 기준:

- `default_avatar_index`가 nil인 사용자만 대상으로 한다.
- 신규 사용자와 같은 배정 정책을 사용한다.
- 이미 값이 있는 사용자는 건드리지 않는다.

---

## 테스트 기준

### Model / service

- 신규 사용자는 생성 시 `default_avatar_index`를 가진다.
- `default_avatar_index`는 1..32 범위다.
- 이미 `default_avatar_index`가 지정되어 있으면 덮어쓰지 않는다.
- bulk 생성 시 가능한 한 사용 빈도가 낮은 avatar index가 선택된다.
- 범위 밖 index는 validation error가 난다.

### Helper

- `user_avatar_path(user, size: 128)`은 `avatars/user_profile_XX_128.png`를 반환한다.
- `user_avatar_path(user, size: 512)`은 `avatars/user_profile_XX_512.png`를 반환한다.
- index가 nil이거나 범위 밖이면 fallback index를 사용한다.
- `user_avatar_image`는 image tag를 반환한다.

### Request / view

- profile page에 사용자의 avatar 이미지가 표시된다.
- Jjaek 카드에 작성자의 avatar 이미지가 표시된다.
- 댓글이 있는 경우 댓글 작성자의 avatar 이미지가 표시된다.

---

## 후속 작업

아래는 MVP 이후 작업이다.

- 사용자가 직접 custom avatar를 업로드하는 UI
- Active Storage avatar variant 최적화
- avatar 변경 화면
- 기본 avatar 선택 화면
- 관리자 또는 교사용 bulk 사용자 생성 시 avatar 중복 최소화 개선
- 알림 / 관계 화면 avatar 적용 확대

---

## 구현 방향 판단

`checkjjaek4`의 avatar MVP는 `suksuk_praise`의 구조를 기준으로 삼는다.

- `users.default_avatar_index`로 기본 avatar를 고정한다.
- 기본 이미지는 `app/assets/images/avatars/user_profile_XX_128.png`, `user_profile_XX_512.png`를 사용한다.
- helper는 기본 asset avatar와 향후 Active Storage custom avatar를 모두 고려해 설계한다.
- 신규 사용자 생성 시에는 `default_avatar_index`를 자동 배정한다.
- 단순 완전 랜덤보다는 현재 사용 빈도가 가장 낮은 avatar index 후보 중에서 랜덤 선택하는 방식을 우선 검토한다.

`checkjjaek3`는 Active Storage custom avatar 구조를 참고하는 정도로만 본다. MVP에서는 기본 asset avatar 표시를 먼저 구현하고, custom avatar 업로드 UI는 후속 작업으로 둔다.
