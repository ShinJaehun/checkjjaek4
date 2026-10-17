# 공개 URL

이 문서는 User와 Group의 공개 URL 정책을 정의한다. URL의 식별자는 조회 대상만 정하며, 인증·인가와 콘텐츠 visibility는 기존 Pundit policy와 scope를 따른다.

## User handle

- 새 공개 회원가입에는 handle이 필수다. 기존 User는 NULL 상태로 남고 계정 설정에서 한 번 지정할 수 있다. 이름이나 이메일에서 자동 생성하지 않는다.
- handle은 영문자로 시작하는 영문 소문자·숫자·밑줄 3~30자다. 입력한 대문자는 소문자로 정규화한다.
- 숫자로만 된 기존 ID 주소와 충돌하지 않는다. `admin`, `account`, `books`, `groups`, `jjaeks`, `users`, `settings`, `sign_in`, `sign_out`, `sign_up`은 예약한다.
- handle은 대소문자 구분 없이 고유하며 DB 고유 인덱스로 동시 가입 충돌도 막는다. 최초 저장 후 변경할 수 없다.
- 활성 User에 대해 생성되는 공개 링크는 `/users/:handle`을 사용한다. 기존 `/users/:id`도 계속 조회된다. 기존 User에 handle이 없으면 숫자 ID 링크를 사용한다.
- 프로필, 서재, 팔로우, 책친구 중첩 경로는 handle과 숫자 ID를 모두 조회한다. 기존 인증·인가 검사를 유지하며 상태 변경 요청은 URL 정규화를 이유로 리다이렉트하지 않는다.
- 관리자 내부 조회는 숫자 ID와 handle 링크를 모두 받아 기존 운영 링크를 보존한다.
- 탈퇴 후 handle은 User row에 비공개로 보존한다. 이는 `docs/specs/account_group_lifecycle.md`의 식별정보 익명화에 대한 제한된 예외이며, 과거 주소가 다른 계정을 가리키지 않도록 영구 재사용을 막는 용도로만 사용한다.
- 탈퇴자의 공개 링크는 숫자 ID를 사용하고 과거 `/users/:handle`은 조회되지 않는다. `/users/:id`는 익명화된 프로필을 표시한다. 보존된 handle은 화면에 노출하지 않는다.

## Group 이름 주소

- Group의 기본키는 숫자 ID다. 새 링크는 `/groups/:id-:name` 형식으로 만들고 한글·영문 이름을 URL에 남긴다.
- 이름이 같은 Group도 ID로 구분한다. 이름 변경 전 주소와 기존 `/groups/:id`는 계속 같은 Group으로 조회된다.
- 이름 부분은 표시용이다. 상세·관리·회원·콘텐츠·게시물 중첩 경로는 앞의 ID로 Group을 찾고 기존 policy와 scope를 적용한다.
- 영속 slug 컬럼과 새 gem은 추가하지 않는다.

## 범위와 검증

- `/jjaeks/:id`, Jjaek·Comment의 식별자와 관계, 기존 Pundit 권한은 변경하지 않는다.
- 공개 handle 형식·중복·가입·최초 설정, 숫자 링크, 중첩 사용자 경로, Group의 한글 이름·이전 주소·중첩 경로, 탈퇴 후 식별정보와 재사용 경계를 검증한다.
