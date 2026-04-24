# Checkjjaek4 Reboot Plan

## 목적

이 문서는 기존 checkjjaek4를
post 중심 SNS 구조에서
Jjaek 흐름을 중심으로 하고 책과 서재를 중요한 문맥으로 다루는
독서 커뮤니티 서비스로 전환하기 위한 구현 계획 문서다.

이 작업은 새 repo를 만드는 작업이 아니다.
같은 repo에서 새 브랜치로 진행하는 **도메인 리부트** 작업이다.

---

## 현재 상태 진단

현재 checkjjaek4는 다음에 가깝다.

- 짧은 글 중심 SNS
- Post 기반 피드
- Comment / Like / Follow 중심 상호작용
- 사용자 프로필과 팔로우 구조는 존재
- 책 자체가 핵심 엔티티로 들어와 있지 않음

즉 현재 구조는 `Post`가 중심이고,
새 bookjjaek은 `Jjaek + User/Relationship + Book/BookshelfEntry`가
함께 맞물리는 구조로 재정렬되어야 한다.

따라서 이 작업은 단순 기능 추가가 아니라
앱의 중심 도메인을 옮기는 작업이다.

---

## 방향 결정

### 유지
- repo 자체
- Rails 앱 골격
- Devise 기반 인증
- User 모델
- Follow 기본 구조
- Pundit 기반 권한 흐름
- 일부 공통 UI/레이아웃 자산

### 폐기 또는 축소
- Post 중심 홈/피드 구조
- Post를 중심으로 한 프로필 흐름
- Post 전용 개념으로 고정된 UI/용어
- 기존 테스트용 posts 데이터

### 새로 도입
- Book
- BookshelfEntry
- StickerDefinition
- BookshelfEntrySticker
- Jjaek
- BookFriendship

추후 도입:
- BookActivity
- Bookshelf
- BookshelfMembership
- Group
- GroupMembership

---

## DB 전략

기존 DB 데이터는 테스트용 데이터로 간주한다.

원칙:
- 기존 posts 데이터를 새 구조로 정교하게 마이그레이션하지 않는다.
- 필요 시 개발 DB를 drop / recreate 한다.
- 기존 구조를 억지로 살려서 새 도메인에 맞추지 않는다.

즉:
- 코드/앱 골격은 재사용
- 데이터는 사실상 새로 시작

---

## 브랜치 전략

추천 브랜치명:

- reboot/book-domain
- refactor/bookjjaek-core

이 작업은 반드시 별도 브랜치에서 진행한다.

---

## 구현 우선순위

### 1단계: 새 도메인 뼈대 추가
먼저 아래 모델을 추가한다.

- Book
- BookshelfEntry
- StickerDefinition
- BookshelfEntrySticker
- Jjaek
- BookFriendship

이 단계에서는 아직 기존 post 흐름을 완전히 제거하지 않아도 된다.
먼저 새 중심축을 세운다.

---

### 2단계: 관계 의미 전환
기존 Follow는 유지하되,
UX 용어를 `소식받기`로 전환한다.

원칙:
- Follow = 피드 구독 관계
- BookFriendship = 신청/수락 기반 신뢰 관계

즉 Follow를 책친구로 재해석하지 않는다.

---

### 3단계: Jjaek 재정의
우선 `Jjaek`를 책 전용 글이 아니라
사용자의 기본 콘텐츠 단위로 재정의한다.

원칙:
- Jjaek는 책 없이도 존재할 수 있다.
- 책은 Jjaek에 선택적으로 연결될 수 있다.
- UI 문맥상 `짹`, `책짹`, `다시짹`이라는 용어를 사용할 수 있다.
- 다만 기본 모델은 가능한 한 `Jjaek`로 단순하게 유지한다.

---

### 4단계: 새 루트/홈 설계
기존 `posts#index` 중심 홈을 제거하고,
새 홈을 Jjaek 흐름 중심 구조로 바꾼다.

초기 홈은 피드 중심으로 작게 유지한다.
아래는 후속 단계로 미룬다.

- 책친구 요청 위젯
- 내 서재 요약 위젯
- BookActivity 요약
- 그룹 관련 요소

즉, 초기 홈은 "읽기 중심 피드"이고
복합 대시보드가 아니다.

초기 홈은 너무 복잡하게 가지 않는다.

최소 구성:
- 내가 남긴 짹
- 내가 소식받는 사람들의 공개 짹
- 책친구 공개 짹 일부
- 사람 문맥에서 남긴 visible `profile-context Jjaek`
- 일반 `짹` 입력창
- 책 검색 진입
- 내 서재 보기 진입

책활동 피드는 후속 단계에서 `BookActivity` 도입과 함께 확장한다.

---

### 5단계: 서재 기능 구현
가장 먼저 보여야 할 핵심 화면 중 하나는 내 서재다.

필수 기능:
- 책 검색 후 서재에 담기
- 대표 상태 선택
- 스티커 붙이기
- 내 서재 목록 보기

원칙:
- 서재 화면은 서재 관리에 집중한다.
- 내 서재 목록 자체는 별도 화면으로 유지한다.
- 다만 특정 책에 대한 상태/스티커 수정과 책짹 작성은 `books/:id`에서도 함께 수행할 수 있다.
- `서재에 담기`라는 용어는 검색 결과 화면에서의 **첫 등록 동작**에만 사용한다.
- `books/:id`에서는 이미 서재에 들어온 책을 다룬다고 보고,
  상태/스티커 영역은 `저장` 또는 `상태 저장` 의미로 표현한다.
- 검색 결과의 `서재에 담기`는 외부 책 정보를
  우리 서비스 DB와 사용자 서재로 가져오는 import 성격의 동작이다.

이 단계에서 bookjjaek은 기존 SNS와 다른 제품 방향을 갖기 시작한다.

---

### 6단계: Jjaek 기능 구현
`Post` 대신 `Jjaek`를 중심으로
일반 짹, 책이 연결된 책짹, 인용/응답 짹을 작성하게 한다.

필수 기능:
- 홈에서 일반 짹 작성
- 특정 책에 책짹 작성
- 공개 범위 선택
- Jjaek 상세
- 댓글/좋아요 연결

원칙:
- 홈은 일반 짹 흐름의 중심 화면이다.
- 홈 피드는 일반 짹만이 아니라, 공개 범위 규칙을 통과한 `profile-context Jjaek`도 함께 다룬다.
- `books/:id`는 책 메타데이터와 그 책에 연결된 책짹을 다루는
  책 문맥 화면이다.
- `users/:id`는 관계에 따라 그 사람의 책과 짹을 보고 상호작용하는
  사람 문맥 화면이다.
- `users/:id`의 작성 입력은 해당 사용자를 향한 DM이 아니라,
  `target_user_id`를 가지는 공개/관계기반 `profile-context Jjaek` 작성 흐름이다.
- 책 상세에서는 아래를 함께 다룬다.
  - 책 메타데이터 확인
  - 그 책에 연결된 visible 책짹 목록 확인
  - 책짹 작성
  - 공개 범위 선택
  - 대표 상태 선택
  - 스티커 선택
- 즉, 초기 MVP에서는 책 상세 안에서
  `BookshelfEntry` 수정과 `책짹` 작성이 함께 일어날 수 있다.
- 다만 저장 책임은 분리한다.
  - 상태/스티커는 `BookshelfEntry`
  - 글 본문/공개 범위는 `Jjaek`
- 같은 화면에 두 기능이 공존하더라도 하나의 저장 흐름으로 합치지 않는다.
  - 상태/스티커 저장: 별도 form, 별도 엔드포인트
  - 책짹 작성: 별도 form, 별도 엔드포인트
- 버튼 의미도 분리한다.
  - 상태/스티커 영역: `저장` 또는 `상태 저장`
  - 일반 작성 영역: `짹`
  - 책 연결 작성 영역: `책짹`

초기에는 `Post`의 일부 구현을 참고하되,
도메인 기준은 반드시 `Jjaek`에 둔다.

---

### 7단계: ReJjaek 도입
기본 Jjaek 흐름이 안정되면
ReJjaek을 self-reference 형태로 도입한다.

원칙:
- 원문보다 넓게 공개 불가
- 원문 나만 보기는 ReJjaek 불가
- 원문 접근 권한이 사라지면 ReJjaek도 비노출
- ReJjaek 가능 여부의 핵심 기준은 BookshelfEntry가 아니라 원문 접근 권한이다
- 초기 MVP에서는 구현 단순성과 권한 일관성을 위해
  ReJjaek이 다른 ReJjaek을 다시 인용하는 중첩 ReJjaek은 허용하지 않는다.
- ReJjaek은 별도 모델로 성급히 분리하지 않고,
  우선 `Jjaek`의 인용/응답 문맥으로 유지한다.
- UI 문맥에서는 `다시짹`이라는 작성 진입을 둘 수 있다.

---

### 8단계: 책활동 도입
초기 Jjaek/서재 흐름이 자리를 잡은 뒤
책활동 피드를 위한 `BookActivity`를 도입한다.

원칙:
- BookActivity는 피드용 이벤트 모델이다.
- Jjaek과 책활동은 저장 모델을 하나로 합치지 않는다.
- 사용자에게는 하나의 흐름처럼 보이게 할 수 있다.

정의:
- `BookActivity`는 `BookshelfEntry`나 `BookshelfEntrySticker`의 상태 변화를
  피드에서 소비하기 좋은 이벤트로 표현하는 모델이다.
- 이 모델은 현재 상태의 source of truth가 아니다.
- 현재 상태는 계속 `BookshelfEntry`, `BookshelfEntrySticker`가 담당한다.
- 본문 글은 계속 `Jjaek`가 담당한다.

책임 경계:
- `BookshelfEntry`: 대표 상태 저장
- `BookshelfEntrySticker`: 스티커 부착 상태 저장
- `Jjaek`: 사용자가 작성한 본문 글 저장. 책은 선택적으로 연결될 수 있다
- `BookActivity`: 위 변화들을 피드용 이벤트로 표현

즉, `BookActivity`는 상태 저장 모델이 아니라
나중에 홈 피드 확장을 위해 도입하는 **이벤트 표현 모델**이다.

---

### 9단계: 기존 Post 흐름 정리
새 홈, 서재, Jjaek 흐름이 자리를 잡은 뒤
기존 `Post`와 관련된 구조를 정리한다.

선택지:
- 완전 제거
- 일시 read-only 유지 후 제거

현재 데이터가 테스트용뿐이라면
최종적으로는 제거하는 쪽을 기본으로 본다.

---

## 1차 MVP 범위

### 반드시 포함
- User
- Follow(소식받기)
- Book
- BookshelfEntry
- StickerDefinition
- BookshelfEntrySticker
- Jjaek
- BookFriendship
- Comment
- Like
- 새 홈
- 내 서재
- 책 상세
- Jjaek 작성/상세
- ReJjaek

### 나중으로 미룸
- BookActivity
- 여러 책장 지원
- Group
- GroupMembership
- 홈 부가 위젯(책친구 요청, 서재 요약, 활동 요약)
- 검색 결과에서의 direct write / direct shelf mutation 확장
- 자동 생성 학생 계정 전환 흐름
- 고급 피드 정렬/추천
- 그룹 전용 공개 범위
- 복잡한 알림 고도화
- 작가 정규화
- 사용자 생성 인용문 카드

`BookActivity`를 지금 미루는 이유:
- 초기 MVP에서는 `Jjaek` 중심 피드만으로도 핵심 흐름을 검증할 수 있다.
- 상태/스티커 저장과 피드 이벤트 생성까지 동시에 고정하면
  생성 타이밍과 노출 규칙이 과하게 복잡해진다.
- 우선은 `BookshelfEntry` / `BookshelfEntrySticker` / `Jjaek`의 책임을 먼저 고정하는 것이 더 중요하다.

나중에 `BookActivity`가 맡을 역할:
- 서재 담기, 상태 변경, 스티커 추가/제거를 시간순 피드 이벤트로 표현
- 홈 피드에서 `Jjaek`과 함께 읽히는 활동 흐름 구성
- 본문 글이 아닌 행동 로그를 사용자에게 자연스럽게 노출

---

## 파일/코드 관점 기본 방침

### 재사용 우선
- authentication
- user-related base flows
- follows
- pundit base setup
- layout/shared partials

### 신설 우선
- models for book domain
- controllers/views for shelf/book/jjaek
- new root/home
- new policies for visibility and book friendship

### 억지 재사용 금지
- Post를 모든 새 개념의 공통 모델처럼 억지 확장
- 기존 post feed를 계속 중심으로 두기
- 기존 테스트용 데이터를 살리기 위한 과도한 변환 코드

---

## Codex 작업 방식

Codex에게 처음부터 전체 구현을 맡기지 않는다.

권장 순서:

### 첫 요청
- 문서를 읽고 현재 repo 구조 분석
- 유지/폐기/신설 대상 정리
- 1차 구현 계획과 diff 제안
- 아직 실제 코드는 크게 건드리지 않음

### 두 번째 요청
- Book / BookshelfEntry / StickerDefinition / BookshelfEntrySticker / Jjaek / BookFriendship
  마이그레이션 및 모델 추가
- 기본 연관관계/validation/policy 초안 작성

### 세 번째 요청
- 새 홈 / 서재 / 책 상세 / Jjaek 작성 흐름 초안 구현

이 단계에서는 반드시
- 화면별 책임을 분리하고
- 홈은 일반 짹 작성과 Jjaek 피드가 있는 짹 흐름 중심 화면으로 두며
- 프로필(`users/:id`)은 관계에 따라 그 사람의 책과 짹을 보고,
  필요하면 `target_user_id` 기반의 공개/관계기반 `profile-context Jjaek` 작성 진입을 둘 수 있는 사람 문맥 화면으로 두고
- 책 상세(`books/:id`)는 서비스 전체의 절대 중심이 아니라
  책 메타데이터와 그 책에 연결된 책짹을 다루는 책 문맥 화면으로 두며
- 그 안에서 `BookshelfEntry` 수정과 책짹 작성을 함께 다루되 저장 책임은 분리하고
- 후속 위젯/요약 패널은 보류 상태로 둔다.

### 네 번째 요청
- ReJjaek 도입
- 권한 규칙 검증
- 기존 Post 흐름 정리 계획 제안

---

## 초기 검증 질문

각 단계에서 아래 질문을 반복 확인한다.

1. 지금 이 변경은 Post 중심 설계를 더 키우는가?
2. 지금 이 변경은 Book / BookshelfEntry / Jjaek 중심 설계를 강화하는가?
3. 지금 이 기능은 MVP에 반드시 필요한가?
4. 지금 이 재사용은 실제로 도움이 되는가, 아니면 기술 부채를 늘리는가?

---

## 최종 원칙 요약

1. 새 repo를 만들지 않는다.
2. 같은 repo에서 새 브랜치로 리부트한다.
3. 기존 테스트 데이터는 버린다.
4. Jjaek를 사용자의 기본 콘텐츠 단위로 재정의한다.
5. 책은 중요하지만, 모든 콘텐츠의 필수 부모로 강제하지 않는다.
6. Follow는 소식받기, BookFriendship는 책친구로 분리한다.
7. 홈 / 책 / 사람 화면의 책임을 분리한다.
8. 기존 Post 중심 구조는 점진적으로 제거한다.
9. Jjaek과 책활동은 분리된 도메인으로 두고, 피드에서 함께 보여준다.
10. 여러 책장, 그룹, 학생 계정 전환 흐름은 후속 확장으로 남긴다.
