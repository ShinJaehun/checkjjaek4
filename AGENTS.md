# AGENTS.md

## 목적과 적용 기준

이 문서는 `checkjjaek4` 저장소에만 적용되는 도메인 정책, 권한 구조,
아키텍처와 구현 관례, 문서 탐색 기준을 정의한다.

Rails 프로젝트에 공통인 spec-driven 개발 절차, 역할 분담, 승인과 실행,
컨텍스트 관리, Proposal / Specs / Design / Tasks, Delta Specs, 브랜치와 Git,
코드 복잡성 방지, 테스트 보존 및 검증 절차는
`~/.agents/skills/spec-driven-rails-development/SKILL.md`를 따른다.

공통 workflow보다 이 저장소의 도메인·권한·구현 규칙이 필요한 경우에는
이 문서와 관련 canonical spec 및 architecture 문서를 함께 따른다.

---

## 프로젝트 구현 원칙

- Rails 관례(Rails way)와 현재 코드베이스의 구조·naming·스타일을 우선한다.
- 비표준 구조, 과도한 메타프로그래밍과 불필요한 새 객체·계층을 추가하지 않는다.
- UI 문구나 markup만 보고 수정하지 않고 관련 도메인 흐름과 정책을 먼저 확인한다.
- view에는 표현 로직만 두고 권한·도메인 판단은 model, policy, controller 등 적절한 계층에 둔다.
- 기존 partial 분리와 controller 책임을 확인하고 같은 흐름을 유지한다.
- 새 문자열이나 문구 변경은 `ko`와 `en` locale 및 기존 UI 용어의 일관성을 함께 고려한다.
- 사용자가 만든 변경과 현재 작업에 무관한 변경은 수정하거나 되돌리지 않는다.

---

## 문서 탐색과 책임

모든 문서를 고정된 순서로 읽지 않는다. `AGENTS.md`를 확인한 뒤 현재 작업에
직접 관련된 canonical spec, architecture 및 testing 문서만 필요한 범위에서 읽는다.

- 현재 구현 상태와 주요 화면·데이터 흐름:
  `docs/architecture/current_system.md`
- 권한 구조와 Pundit 경계:
  `docs/architecture/authorization.md`
- Jjaek visibility와 조회 범위:
  `docs/architecture/jjaek_visibility.md`
- 제품 방향과 핵심 도메인:
  `docs/specs/bookjjaek_reboot_spec.md`
- 기능별 확정 정책과 Acceptance Criteria:
  관련 `docs/specs/*.md`
- 테스트 전략:
  `docs/testing/rspec_strategy.md`

작업에 관련된 spec의 판단 근거가 architecture 또는 정책 문서에 있으면 함께 확인한다.
`docs/archive/*`와 `docs/legacy/*`는 사용자가 요청하거나 active 문서만으로 판단할 수
없을 때만 참고하며 현재 기준으로 사용하지 않는다.

문서와 구현 또는 active 문서끼리 충돌하면 조용히 한쪽에 맞추지 않는다.
현재 구현 사실과 목표 정책을 구분하고, 정책 결정이 필요한 충돌은 사용자에게 보고한다.

---

## 제품과 현재 구현 해석

`checkjjaek4`는 post 중심 SNS를 확장하는 프로젝트가 아니라 책과 서재가 중요한
문맥을 이루는 독서 커뮤니티 서비스다. 장기 제품 방향은
`docs/specs/bookjjaek_reboot_spec.md`, 현재 구현 사실은
`docs/architecture/current_system.md`를 기준으로 판단한다.

- 여러 책장과 새 책 담기 시 책장 선택은 현재 구현 범위다.
- Group과 moderation은 현재 구현된 기능이다. 세부 상태와 권한은 현재 시스템 문서와
  관련 Group·moderation canonical spec을 따른다.
- Classroom은 후속 개발 대상이다. Group에서 확립된 콘텐츠 접근 정책을 재사용할 수
  있지만 Group 승인 lifecycle을 자동 적용하지 않으며 별도 작업에서 정책을 확정한다.
- Topic, 작가 정규화, 인용문 기능과 범용 SNS 확장은 별도 승인된 spec 없이 추가하지 않는다.
- 새 저장소로 분리하기보다 현재 저장소와 기존 구조를 점진적으로 확장한다.

---

## ReJjaek과 동아리 다시짹

ReJjaek의 상세 생성·조회·visibility·수정·삭제 정책을 이 문서에 중복 정의하지 않는다.
작업 경로에 따라 다음 canonical 문서를 확인한다.

- 개인·동아리 다시짹 A/B/C의 공유 경로와 원문 삭제 후 처리 정책:
  `docs/specs/group_sharing_requotes.md`
- 다시짹 목록 조회와 노출 범위 정책:
  `docs/specs/requotes_mvp.md`
- 공통 visibility와 조회 권한:
  `docs/architecture/jjaek_visibility.md`
- 현재 구현 구조:
  `docs/architecture/current_system.md`

개인 다시짹 A와 동아리 인용 B/C의 원문 삭제 후 처리 방식은 동일하지 않다.
일반적인 ReJjaek 설명을 모든 경로에 확장하지 말고 해당 경로의 canonical spec을 우선한다.
정책은 model validation에만 두지 않고 policy, policy scope와 request 흐름에서 함께 강제한다.

---

## Group, moderation과 Classroom

- Group 생성·승인·membership·운영 lifecycle과 Group 콘텐츠는 현재 구현 범위다.
- Group 및 사용자 운영 정지, 회원 활동 정지·이용 제한, Jjaek·Comment 숨김/복구와
  감사 이력도 현재 moderation 구현 범위다.
- Group 접근과 moderation 권한은
  `docs/architecture/authorization.md`, 관련 Group·moderation spec 및
  `docs/architecture/current_system.md`를 따른다.
- 계정 탈퇴와 Group lifecycle의 목표 정책은
  `docs/specs/account_group_lifecycle.md`를 따른다.
- 개인 영역과 Group 영역은 게시 문맥과 접근 권한을 구분하며, 한 영역의 규칙을
  다른 영역에 자동 적용하지 않는다.
- Classroom은 현재 Group이나 moderation의 다른 이름이 아니다. 도입 시 재사용할 정책과
  새로 정할 lifecycle을 구분해 별도 spec으로 확정한다.

---

## 승인된 작업의 실행

목적, 정책과 수정 범위가 이미 승인된 작업은 같은 승인을 반복하거나 사전 diff 승인을
다시 요구하지 않고 승인된 범위를 직접 완료한다.

다음 상황에서는 영향을 받는 부분을 임의로 진행하지 않고 충돌과 필요한 결정을 보고한다.

- 새로운 제품 또는 권한 정책 결정이 필요한 경우
- 기존 불변 조건이나 테스트가 보장하는 동작을 변경해야 하는 경우
- 승인된 수정 범위를 실질적으로 확대해야 하는 경우
- canonical 문서와 실제 구현의 기준이 불명확하게 충돌하는 경우

승인된 범위 안의 코드·테스트·관련 canonical 문서 동기화는 하나의 동작을 완성하는 데
필요하면 인위적으로 분리하지 않는다. 반대로 독립적인 기능이나 무관한 리팩토링은 끼워
넣지 않는다.

---

## 권한과 구현 구조

- 서버측 권한 판단은 Pundit policy 중심으로 유지한다.
- 단건 권한은 policy, 목록 조회 범위는 policy scope에 둔다.
- controller는 가능한 한 `authorize`와 `policy_scope`를 호출하는 자리로 남기고 권한
  조건식을 화면별로 반복하지 않는다.
- view는 policy와 controller에서 정리된 상태를 소비하며 직접 권한 체계를 만들지 않는다.
- 화면마다 다른 조회 범위는 controller 조건문보다 policy 또는 scope 구조로 설명할 수
  있어야 한다.
- 레거시 `checkjjaek3`의 CanCanCan 구조는 참고 대상일 뿐 현재 권한 체계로 가져오지 않는다.
- Turbo와 HTML 응답을 모두 유지하고 같은 권한·도메인 결과를 반환하도록 한다.
- Turbo 전용 mutation과 HTML fallback의 책임을 기존 흐름과 일관되게 유지한다.

---

## 테스트 기준

테스트의 목적은 coverage 수치가 아니라 핵심 동작에 대한 confidence 확보다.
구체적인 레벨과 작성 순서는 `docs/testing/rspec_strategy.md`를 따른다.

우선 검증 대상은 다음과 같다.

- `Book`, `BookshelfEntry`, `BookshelfEntrySticker`
- 검색 결과 import 흐름
- `Jjaek`, 개인·동아리 ReJjaek
- Group과 moderation의 상태 전이 및 감사 경계
- visibility, policy와 policy scope
- 주요 request 흐름과 실패 경로

brittle한 HTML 구조 검증과 중복되는 저가치 테스트를 피한다. system spec은 핵심 happy
path 중심으로 제한하고 RSpec은 readable > clever 원칙을 따른다.

---

## 완료 보고

공통 완료 검토와 보고 형식은 `spec-driven-rails-development` 스킬을 따른다.
특히 변경된 파일과 이유, canonical 정책과 구현의 일치 여부, 남은 충돌, 사용자가 실행할
검증 명령을 간결하게 남긴다. 실제 실행하지 않은 테스트나 검증은 통과했다고 보고하지 않는다.
