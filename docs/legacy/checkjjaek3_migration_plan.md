# Migration Plan — checkjjaek3 → checkjjaek4

## 상태

이 문서는 `checkjjaek4` 초기 재구축 시점의
레거시 분석 / 마이그레이션 판단 기록이다.

현재 활성 구현 기준은 아래 두 문서다.

- `docs/specs/bookjjaek_reboot_spec.md`
- `docs/reboot/reboot_plan.md`

즉, 이 문서는 checkjjaek3 및 초기 재구축 판단을 보관하는
`docs/legacy/` 문서이며, 현재 리부트 범위의 직접 구현 기준은 아니다.

---

## 목적

`checkjjaek4`의 목표는 `checkjjaek3`를 그대로 복제하는 것이 아니다.

목표는 다음과 같다.

- `checkjjaek3`의 핵심 도메인과 사용자 흐름을 분석한다.
- 레거시 구현 세부를 무비판적으로 옮기지 않는다.
- 최신 Rails 방식에 맞게 더 단순하고 읽기 쉬운 구조로 재구축한다.
- 먼저 핵심 기능을 안정적으로 복원하고, 부가 기능은 뒤로 미룬다.

---

## 작업 전제

- 현재 실제 작업 대상은 `checkjjaek4` 저장소다.
- 레거시 분석이 필요할 때만 상위 경로의 `../checkjjaek3`를 읽기 전용 참고 대상으로 참조한다.
- 레거시 저장소는 수정 대상으로 취급하지 않는다.
- `checkjjaek4`는 `checkjjaek3`를 그대로 복제하는 프로젝트가 아니라, 핵심 도메인과 사용자 흐름을 재구축하는 프로젝트다.

## 레거시 checkjjaek3 개괄

레거시 `checkjjaek3`는 다음 특징을 가진다.

- Rails 6.0 계열, Ruby 2.7.0 기반
- Devise 사용
- 권한은 CanCanCan + Rolify 기반
- Webpacker/Turbolinks 기반 프론트엔드 구조
- `Post`가 `postable` polymorphic 구조를 사용
- `Book`, `Message`, `Photo` 각각이 post를 가지는 방식
- `Comment`도 polymorphic + `parent_id` 구조를 가짐
- 그룹/가입 상태(`groups.group_state`, `user_groups.state`) 개념이 존재한다

이 구조는 당시에는 합리적이었지만, `checkjjaek4`에서 그대로 유지해야 하는 전제는 아니다.

---

## checkjjaek4의 기본 방향

### 기술 방향

- Rails 8 기본 흐름을 따른다.
- PostgreSQL 사용
- Tailwind 사용
- JS는 기본 importmap 흐름에서 시작
- Hotwire/Turbo를 기본 전제로 사용
- 문자열은 처음부터 `locales`를 고려한다.
- 권한은 Pundit policy 중심으로 설계한다.

### 기본 원칙

- Rails way 우선
- 작은 단위로 진행
- spec 기반 작업
- diff 제시 → 승인 → 반영
- view 로직 최소화
- Turbo/HTML 응답 일관성 유지
- 코드 스타일/구조의 일관성 유지

---

이 문서에서는 레거시 이름 `UserGroup`을 설명할 때,
checkjjaek4에서의 후보 이름으로 `Membership`을 함께 사용한다.

## 레거시에서 가져올 것과 버릴 것

### 가져올 것

- 핵심 도메인 개념
  - User
  - Group
  - UserGroup(또는 Membership 성격의 가입 관계)
  - Book
  - Post
  - Comment
  - Follow / Like / Tag 여부 검토
- 핵심 사용자 흐름
  - 사용자 인증
  - 그룹 생성/참여/승인
  - 책 검색/책 연결
  - 글 작성/조회
  - 댓글/대댓글
  - 사용자/그룹 기반 피드
- 상태 개념
  - 그룹 상태
  - 그룹 가입 상태
  - 필요한 경우 댓글 계층

### 그대로 가져오지 않을 것

- CanCanCan + Rolify 권한 구조
- Webpacker/Turbolinks 전제
- Bootstrap 시대의 뷰 구조
- `Post` 중심 구조를 불필요하게 복잡하게 만드는 polymorphic 설계
- 레거시 시절의 gem/workaround 중심 구현 방식
- “예전에 필요했기 때문에 존재했던” 분리 모델들

---

## 가장 중요한 구조 판단

### 1. Post 중심 단순화

레거시 `checkjjaek3`는 `Post`가 `Book`, `Message`, `Photo`에 각각 polymorphic으로 붙는 구조를 사용한다.

하지만 `checkjjaek4`에서는 1차적으로 이 구조를 그대로 가져가지 않는다.

이유:

- 지금은 하나의 `Post`가 richer content를 충분히 표현할 수 있다.
- 책 관련 글은 `Post + book_id(optional)`로 표현 가능하다.
- 사진 관련 글은 `Post + 첨부 이미지`로 표현 가능하다.
- 메시지성 글도 별도 모델보다 `Post`의 대상/공개 범위 개념으로 먼저 검토할 수 있다.
- polymorphic은 form, partial, policy, query, 테스트를 모두 더 복잡하게 만들 수 있다.

따라서 초기 재구축에서는 다음 방향을 우선 검토한다.

- `Post` 단일 모델 중심
- `book_id` nullable
- 이미지 첨부는 Active Storage
- 대상/공개 범위는 post의 속성 또는 연결 모델로 명시
- 정말 별도 수명주기와 규칙이 필요해질 때만 나중에 분리

즉, `checkjjaek4`의 기본 방향은 “postable 복제”가 아니라 “Post 중심으로 단순화”이다.

---

### 2. CanCanCan → Pundit 전환

레거시 `checkjjaek3`는 CanCanCan + Rolify 기반이다.

하지만 `checkjjaek4`에서는 이를 그대로 이식하지 않는다.

대신 다음 원칙을 따른다.

- 서버측 권한 판단은 Pundit policy 중심으로 설계한다.
- `authorize`, `policy_scope` 흐름으로 읽기 쉽게 유지한다.
- 레거시 ability 규칙을 기계적으로 1:1 복제하지 않는다.
- 현재 필요한 사용자 흐름을 기준으로 policy와 scope를 다시 설계한다.
- view에서 권한 분기를 남발하지 않는다.

초기 우선 policy 후보:

- GroupPolicy
- Membership(UserGroup) 관련 policy
- PostPolicy
- CommentPolicy
- BookPolicy 또는 book 관련 읽기/연결 정책
- UserPolicy(프로필/팔로우 관련 범위가 필요하면)

---

## 단계별 진행 계획

### Step 0. 문서화

먼저 아래 문서를 작성/보강한다.

- `docs/migration/plan.md`
- `docs/legacy/models.md`
- `docs/legacy/features.md`

목표:
- 레거시 구조를 “복제 대상”이 아니라 “분석 대상”으로 정리한다.
- checkjjaek4에서 유지/단순화/폐기할 대상을 분리한다.

---

### Step 1. 핵심 도메인 재정의

초기 핵심 도메인 후보:

- User
- Group
- Membership(기존 `UserGroup`의 역할 재해석)
- Book
- Post
- Comment

이 단계 목표:

- 레거시 모델 이름/구조를 그대로 따르지 않고,
  checkjjaek4 기준으로 책임을 다시 정의한다.
- 특히 `Post`를 중심으로 도메인을 단순화할 수 있는지 먼저 결정한다.
- 그룹 상태/가입 상태가 실제로 필요한지, 어떤 enum/state가 적절한지 정리한다.

---

### Step 2. 인증과 최소 레이아웃

목표:

- Devise 기반 인증 흐름 정리
- 기본 layout과 navigation 확정
- Turbo/HTML 응답 스타일 일관성 확보
- locales 구조 시작

이 단계에서는 화면을 많이 만들기보다
“앱이 기본적으로 동작하는 뼈대”를 먼저 안정화한다.

---

### Step 3. 권한 구조 정착

목표:

- Pundit 도입
- ApplicationPolicy, policy scope 기본 구조 확정
- 핵심 리소스에 대한 authorize 흐름 정리
- view에서의 권한 조건 최소화

원칙:

- checkjjaek3의 CanCanCan을 흉내내지 않는다.
- 현재 필요한 사용자 행위 중심으로 policy를 만든다.

---

### Step 4. 그룹/가입 흐름

목표:

- 그룹 생성/조회
- 그룹 가입 신청
- 가입 승인/상태 변경
- 그룹 멤버십 상태 표현

이 단계는 레거시에서 중요했던 `group_state`, `user_groups.state` 개념을
현재 구조에서 어떻게 단순하고 명확하게 표현할지 결정하는 단계다.

---

### Step 5. Post 중심 피드 복원

목표:

- Post 생성/조회
- 책 연결 post
- 이미지 첨부 post
- 사용자/그룹 맥락의 post
- 댓글/대댓글

이 단계의 핵심은
레거시의 polymorphic 구조를 복제하지 않고도
사용자 경험을 충분히 복원할 수 있는지 확인하는 것이다.

---

### Step 6. 책 검색과 연결

목표:

- 외부 책 검색 API 연결
- Book 저장 또는 참조 전략 확정
- post와 book 연결

원칙:

- API 연동은 처음부터 과하게 일반화하지 않는다.
- 작은 adapter/service 수준에서 시작한다.
- 실패 처리와 결과 구조를 단순하게 유지한다.

`checkjjaek4`의 책 검색 연동은 레거시 구현을 그대로 복사하지 않는다.
현재 시점의 Kakao Developers 공식 문서를 기준으로
엔드포인트, 인증 방식, 요청 파라미터, 쿼터를 다시 확인한 뒤 반영한다.

앱 내부에서는 외부 API 의존을 직접 흩뿌리지 않고,
얇은 adapter/service 계층에서 감싸는 방향을 우선 검토한다.

---

### Step 7. 후순위 기능

아래 기능은 기본 도메인이 자리잡은 뒤 검토한다.

- follow
- like
- hashtag/tag
- 고급 검색
- 관리자 기능
- 메시지 전용 흐름이 정말 필요한지에 대한 재평가

---

## 초기 이식 우선순위

현재 기준 추천 순서는 다음과 같다.

1. 문서화
2. 인증 + 기본 layout
3. Pundit 권한 구조
4. Group + Membership
5. Post + Comment
6. Book 검색/연결
7. Follow / Like / Tag 등 부가 기능

이 순서를 따르는 이유는,
레거시의 세부 구현보다 현재 앱의 뼈대와 권한 구조를 먼저 안정화해야
나중 기능이 덜 흔들리기 때문이다.

---

## migration 완료 이후 문서 우선순위

재구축 초반에는 `docs/migration`과 `docs/legacy`가 중요하다.

하지만 핵심 도메인이 안정화되면:

- `docs/specs/*.md`
- `docs/architecture/*.md`
- `docs/testing/*.md`

가 더 중요한 기준이 된다.

즉, migration/legacy 문서는 시간이 갈수록
“초기 판단의 근거를 보관하는 문서”로 남고,
일상적인 구현의 직접 기준은 점점 아니게 되는 상태를 목표로 한다.

---

## 하지 않을 것

- 레거시 구조를 대량 복사하는 작업
- CanCanCan ability를 그대로 재현하는 작업
- `postable` polymorphic을 무비판적으로 복원하는 작업
- Webpacker/Bootstrap 전제를 되살리는 작업
- 초기 단계에서 지나치게 많은 service/query object를 만드는 작업
- 미래 확장을 이유로 현재 복잡도를 과하게 높이는 작업

---

## 문서 갱신 규칙

아래와 같은 판단이 생기면 이 문서를 갱신한다.

- 핵심 도메인 분리가 달라졌을 때
- `Post` 구조 단순화 방향이 바뀌었을 때
- Pundit policy 구조 범위가 크게 달라졌을 때
- 우선 이식 순서가 바뀌었을 때
- migration 단계가 사실상 끝났다고 판단될 때

