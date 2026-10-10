# 기본 Rate Limit 명세

## 상태와 목적

이 문서는 기본 Rate Limit의 **승인된 설계와 구현 상태**를 기록한다. 회원가입·로그인·짹·댓글·좋아요 및 동아리 개설·가입·초대 제한을 구현했다. 아래 수치는 운영 중 정상 사용과 차단 현황을 보며 조정할 초기 정책이다.

반복적인 인증 및 쓰기 요청으로 인한 서버 부담과 남용을 완화한다. 기존 Devise 인증, 계정 정지, Pundit 권한, 동아리 운영 정책 및 데이터 중복 방지 규칙은 유지한다. 제한은 요청을 처리하기 전에 적용하며 성공·실패 여부와 관계없이 요청 횟수를 계산한다.

## 현재 구조

- Rails 8.1.3.1의 `ActionController::RateLimiting#rate_limit`을 사용할 수 있다. 지정한 action의 요청을 캐시 카운터로 제한하고, 초과 시 기본적으로 `ActionController::TooManyRequests`와 HTTP 429를 사용한다.
- 회원가입은 `Users::RegistrationsController#create`에서 Devise의 기존 create 흐름을 사용한다. 로그인은 `Users::SessionsController#create`가 정지 계정의 올바른 비밀번호 입력을 별도로 처리하고 그 외에는 Devise에 위임한다. 로그인 실패만 세는 별도 계측은 이번 범위에 없다.
- `ApplicationController`는 Devise 인증, 정지 세션 차단, Pundit 권한 처리를 담당한다. Devise controller는 일반 로그인 필수 before action의 예외다.
- 운영 환경은 별도 cache DB를 사용하는 Solid Cache, 개발 환경은 프로세스별 MemoryStore, 테스트 환경은 NullStore다. Rate Limit request spec은 별도 MemoryStore로 카운터를 검증한다.
- 좋아요의 사용자·글 고유성, 동아리 membership의 사용자·동아리 고유성, 일부 인용 다시짹 중복 방지와 동아리 쓰기의 row lock은 기존 중복·동시성 방어다. 요청 횟수 제한을 대신하지 않는다.

## 적용 요청과 초기 상한

각 상한은 해당 기준별 시간 범위 내 요청 수다. 한계를 넘으면 요청을 실행하지 않고 HTTP 429와 지역화된 안내를 반환한다. 로그인 외의 로그인 사용자 요청은 사용자 ID를 기준으로 하며, 계정·동아리 권한 검사는 계속 기존 정책을 따른다.

| 대상 | Controller#action | 기존 보호 | 제한 기준 및 초기 상한 | 정상 반복 사용에 미치는 영향 |
| --- | --- | --- | --- | --- |
| 회원가입 | `Users::RegistrationsController#create` | Devise 검증, 이메일 고유성 | 실제 클라이언트 IP당 60회/1시간 | 학교 등 공유 IP에서 동시 가입 가능성을 고려한 상한. 대규모 일괄 가입은 여전히 제한될 수 있음 |
| 로그인 시도 | `Users::SessionsController#create` | Devise 인증, 정지 계정 처리 | IP당 120회/5분 **및** 같은 IP＋정규화 이메일 조합당 8회/5분 | 성공·실패 모두 계산. 같은 IP에서 동일 계정으로 반복 로그인하면 잠시 제한될 수 있음 |
| 개인 짹·책짹·동아리 게시물 작성 | `JjaeksController#create` | Pundit, 유효성 검사, 일부 인용 중복 방지 | 사용자당 합계 30회/5분 | 여러 게시 공간에 연속 작성하면 공유 상한에 도달함 |
| 댓글 작성 | `CommentsController#create` | 부모 글 접근 권한, 유효성 검사 | 사용자당 30회/5분 | 매우 활발한 연속 댓글 작성에 영향 가능 |
| 좋아요·취소 | `LikesController#create/destroy` | Pundit, 사용자·글 고유성 | 사용자당 두 action 합계 60회/5분 | 빠른 반복 토글에 영향 가능 |
| 동아리 생성 | `GroupsController#create` | 승인 lifecycle, 유효성 검사 | 사용자당 5회/24시간 | 모든 동아리 유형과 global admin 개설을 합산함 |
| 공개 동아리 가입·승인 동아리 가입 신청 | `GroupMembershipsController#create` | Pundit, 사용자·동아리 고유성, row lock | 사용자당 합계 15회/1시간 | 여러 동아리에 연속 가입하면 제한될 수 있음 |
| 비공개 동아리 회원 초대 | `GroupMembershipsController#invite` | Pundit, 중복 방지, row lock | 초대자당 30회/1시간 | 큰 동아리의 연속 초대 작업에 영향 가능 |

두 로그인 제한은 각각 다른 `name`을 사용해 별도 카운터로 운영한다. 이메일은 Devise의 공백 제거·소문자화와 같은 방식으로 정규화한 뒤, 서버 비밀키를 사용하는 단방향 HMAC으로 변환해 IP와 조합한다. 원문 이메일이나 비밀번호를 Rate Limit 저장소 키 또는 초과 로그에 넣지 않는다. 계정 존재 여부와 관계없이 같은 키 생성 규칙을 적용한다. 전역 이메일 단독 제한이나 Devise `:lockable`은 사용하지 않아 다른 IP에서 특정 계정을 임의로 잠그는 경로를 만들지 않는다. 분산된 여러 IP의 공격까지 완전히 막는 정책은 아니다.

## 구현 방식

- Rails 내장 `rate_limit`을 해당 controller action에 적용한다. 인증 전 회원가입·로그인은 신뢰할 수 있는 `request.remote_ip`를, 인증된 쓰기 요청은 `current_user.id`를 제한 기준으로 사용한다. 같은 controller에서 독립된 제한을 여러 개 둘 때 `name`을 구분한다. 좋아요 create/destroy처럼 상한을 공유하는 action은 같은 범위를 사용한다.
- 운영 환경에서는 기존 Solid Cache를 카운터 저장소로 사용해 여러 Rails 프로세스가 제한 상태를 공유한다. 새 gem, Redis, 별도 DB 테이블 또는 외부 서비스는 추가하지 않는다.
- Rack::Attack은 이번 범위에 포함하지 않는다. Rails controller 전에 전체 경로를 제한하거나 인증 실패 결과만 별도로 계측할 필요가 확인되면 다시 검토한다. Solid Cache는 제한 규칙이 아니라 카운터 저장소다.
- Rails 내장 제한은 action 실행 전 요청을 계산한다. 로그인 성공·실패 및 유효성 검사 실패도 카운터를 사용한다. 동아리 개설·가입·초대는 첫 Pundit 권한 검사 뒤에 카운터를 적용해 비인가 요청을 제외한다. 회원가입과 로그인 실패 **전용** 카운터는 구현하지 않는다.
- 개발 환경의 MemoryStore는 프로세스 간 카운터를 공유하지 않는다. 테스트 환경의 기본 NullStore는 카운터 동작을 검증할 수 없으므로 Rate Limit request spec에서 실제 카운터가 작동하는 테스트용 캐시 저장소를 명시하고 예제 간 상태를 격리한다.

## 초과 응답과 사용자 안내

HTML과 Turbo 요청 모두 HTTP 429와 한국어·영어 locale 기반의 안내를 제공한다. 회원가입 초과 안내는 “요청이 너무 빠릅니다. 잠시 후 다시 시도해 주세요.”를 유지한다. 로그인 초과 안내는 “로그인이 일시적으로 제한되었습니다.”로 시작하고, 5분 뒤 재시도를 안내한다. 짹·책짹, 댓글, 좋아요 초과 안내는 각각 제한 이유와 5분 뒤 재시도를 설명한다. 동아리 개설은 24시간 뒤, 가입·초대는 1시간 뒤 재시도를 안내한다. 이 시간은 정확한 남은 시간이 아닌 재시도 안내다. 콘텐츠와 동아리 Turbo Stream 요청에서는 `flash-messages`만 갱신해 작성 중인 입력과 기존 화면 상태를 유지한다. HTML 요청에서는 429와 안내를 표시하며, 짹·댓글·동아리 개설은 제출한 입력을 유지한다. 로그인 초과 안내는 계정 존재 여부, 비밀번호 정답 여부, 정지 여부를 드러내지 않는다.

## 운영과 보안 확인

- 배포 프록시가 전달한 실제 클라이언트 IP가 `request.remote_ip`로 안정적으로 해석되는지 확인한다. 신뢰 프록시와 전달 헤더 설정이 잘못되면 우회되거나 여러 사용자가 한 카운터를 공유할 수 있다.
- 학교 네트워크처럼 공인 IP를 공유하는 환경을 고려해 IP 단독 상한을 비교적 높게 둔다. 운영 기록에서 정상 사용자의 429 빈도와 관리자 생성·초대 작업 영향을 확인하고 수치를 조정한다.
- Rate Limit은 기존 CSRF, 인증, Pundit, 모델 검증, 데이터베이스 고유성 제약을 대체하지 않는다. 캐시 장애 시의 동작과 운영 관측 방식은 구현 검토 때 기존 캐시 동작을 확인한다.

## 예상 구현 파일과 검증

인증·콘텐츠 제한에 이어 `GroupsController#create`, `GroupMembershipsController#create/invite`에 사용자별 제한을 적용했다. 가입과 초대는 별도 이름의 카운터를 사용하며, 권한 확인을 카운터 앞에 둔다. 공통 Turbo Stream 429 안내와 기능별 한국어·영어 locale, request spec을 사용한다.

Request spec에서는 각 action의 경계값과 초과 직후 429, 카운터 만료 후 재허용, IP·사용자·로그인 IP＋이메일 조합 간 분리, 로그인 성공·실패 모두 카운트, 정지 계정 처리 유지, HTML·Turbo 안내, 기존 권한·중복 방지의 보존을 확인한다. 학교 공유 IP 사례와 동아리 가입·초대 및 좋아요 두 action의 공유 상한도 확인한다.

## 제외 범위

로그인 실패만 별도로 계측하기, Student PIN 로그인, 계정 잠금, 분산 IP 공격 대응, 별도 추천·개인화 정책, Redis·새 테이블·외부 제한 서비스는 이번 MVP에서 제외한다. 교실 기능은 아직 구현되지 않았다.

## 기술 참고

- [Rails 8.1 `rate_limit` API](https://api.rubyonrails.org/v8.1.3/classes/ActionController/RateLimiting/ClassMethods.html)
- [Rails 8.1.3.1 제한 카운터 구현](https://github.com/rails/rails/blob/v8.1.3.1/actionpack/lib/action_controller/metal/rate_limiting.rb)
- [Devise 5.0.4 로그인 controller](https://github.com/heartcombo/devise/blob/v5.0.4/app/controllers/devise/sessions_controller.rb)
- [Solid Cache](https://github.com/rails/solid_cache)
