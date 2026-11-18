# A17 사진 운영

코드 구현의 운영 인계 문서다. 이 작업에서 migration·RSpec·브라우저·OCI 검증을 실행하지 않았다.
정책과 AC는 [A17 명세](../specs/jjaek_photos_a17.md), 기본 배포는 [OCI 운영 배포](deploy_oci.md)를 따른다.

## 배포 설정

1. OCI에 공개 접근·공개 PAR이 없는 사진 전용 버킷을 준비한다. 공통 `OCI_STORAGE_*` 설정을 사용하며
   해당 principal에 사진 버킷의 object 읽기/쓰기/삭제 권한을 부여한다.
   사진 경로에 CDN 공개 캐시를 붙이지 않는다.
2. 운영 `.env`에 `OCI_PHOTO_BUCKET`을 추가한다. 저장소 `.env.example`과 `compose.prod.yml`을 함께 반영한다.
   기본 제한은 아래와 같다. 값 변경은 웹 컨테이너 재생성 후 반영된다.

   | 환경변수 | 기본값 |
   | --- | --- |
   | `JJAEK_PHOTO_UPLOADS_ENABLED` | `true` (`false`로 신규 업로드만 중지) |
   | `JJAEK_PHOTO_DAILY_LIMIT` | `4` |
   | `JJAEK_PHOTO_RETAINED_LIMIT` | `50` |
   | `JJAEK_PHOTO_STORAGE_LIMIT_BYTES` | `1073741824` |

3. `bin/rails db:migrate`로 `jjaek_photo_uploads`를 추가한다. schema 파일도 이 명령의 결과로 갱신한다.
   기존 Active Storage 테이블과 아바타 Blob은 이동하지 않는다.
   `draw_routes` 변경은 부팅 설정이므로 개발 서버도 재시작한다. 운영은 구 웹 컨테이너를 완전히 교체해
   기본 Active Storage 공개 라우트가 남은 프로세스와 혼용하지 않는다.
4. Nginx의 실제 서비스 server에 `client_max_body_size 25m;`을 반영한다.
   4×5MB와 multipart 여유를 포함하며 Cloudflare의 업로드 제한도 함께 확인한다.
5. `/jjaeks/*/photos/*`, `/users/*/avatar_image`는 Cookie 인증과 `Cache-Control: private, no-store`를 그대로 전달한다.
   Cloudflare Cache Everything/edge cache override와 Nginx proxy cache 대상에서 제외한다.
   이미지 proxy buffering으로 불필요한 메모리/임시파일을 누적하지 않도록 해당 location 설정을 점검한다.
   익명 요청과 관계 변경 뒤 재요청을 원본/Variant 모두 검사하며 `CF-Cache-Status: HIT`가 없어야 한다.
6. Solid Queue worker와 hourly `CleanupJjaekPhotosJob`이 실행되는지 확인한다.
   `PurgeJjaekPhotoJob`의 실패/재시도와 큐 지연을 모니터링한다.

## 업로드와 용량 계산

- 브라우저는 원본 5MB/지원 형식을 확인하고 2000px WebP로 만든다. Rails는 실제 형식·크기·디코딩을
  재검사하고 metadata를 제거한 WebP를 Active Storage의 최적화 원본으로 저장한다.
- 성공 이력은 `JjaekPhotoUpload`에 남고 삭제한 사진의 Blob FK는 null이 된다. 일일 수는 지워지지 않는다.
  날짜는 Asia/Seoul transaction 시작일이며 실패한 게시 요청은 성공 이력을 남기지 않는다.
  모든 사진 쓰기는 PostgreSQL 공통 advisory lock 안에서 한도 검사·첨부·이력을 처리한다.
- 전체 원본 용량은 `JjaekPhotoUpload.original_blobs.sum(:byte_size)`로 확인한다.
  staging/실패/삭제 대기 Blob도 포함해 실제 정리가 끝날 때까지 여유로 계산하지 않는다.
  실제 OCI에 쓰기 전 한도를 검사하므로 동시 staging 시 보수적으로 거절될 수 있다.
- 현재 보관 수는 사용자 소유 Jjaek의 실제 `photos` 첨부 수다. 숨김 사진도 포함한다.
  삭제/tombstone에서 첨부가 제거되며 비공개 및 삭제된 URL은 새 요청에서 현재 policy를 다시 검사한다.
- 원본 Blob row를 게시 transaction 전에 만들어 프로세스 중단에도 object key를 보존한다.
  정리 job은 파일을 먼저 지우고 행을 지운다. 실패하면 키와 bytes를 유지하며 재시도한다.
  hourly cleanup은 하루 이상 된 미첨부 원본을 회수한다. 일일 성공 이력은 삭제하지 않는다.
- 카드 800px/확대 1600px Variant는 처음 요청에서 생성해 같은 OCI 사진 버킷에 보관하고 재사용한다.
  tracked Variant와 아바타는 위 1GB 원본 budget에 포함하지 않는다. OCI 버킷 지표/실제 object 목록으로
  **사진 원본+Variant 전체**, 아바타 버킷, object version과 미완료 multipart를 따로 확인한다.
- OCI 비용/저장량 경보와 예산 알림을 설정한다. 버전 관리·삭제 보존이 켜져 있으면 현재 객체 삭제만으로
  과거 버전 비용이 없어지지 않는다. 미완료 multipart 정리 lifecycle도 운영 정책으로 설정한다.
  1GB 애플리케이션 제한은 과금의 절대 상한이 아니다.

## 메모리와 접근 경계

원본/Variant와 아바타는 Rails가 chunk 단위로 중계하며 OCI signed URL을 클라이언트에게 반환하지 않는다.
원본은 UI에서 요청하지 않는다. Range 요청은 분할 다운로드로 처리하지 않고 인증된 전체 파일을 반환한다.
libvips concurrency=1, cache 비활성화와 단일 컨테이너 공유 파일 잠금으로 이미지 처리량을 제한한다.
변환 대기 중인 요청은 변환 뒤 부모 policy와 첨부 소속을 재검사한다.

현재 잠금은 **단일 VM의 단일 웹 컨테이너**를 전제로 한다. 웹/변환 컨테이너를 늘릴 때는 공유 잠금·처리
worker 구조를 별도 검토해야 한다. 대기 요청은 Puma thread를 차지하므로 cold Variant가 많은 경우 지연이 생긴다.
새 요청의 권한 철회가 이미 표시/저장된 파일의 회수를 의미하지는 않는다.

기본 Active Storage Blob/representation/Disk/direct-upload 라우트는 비활성화한다.
아바타는 기존 128/512px를 별도 인증 경로로 제공하며 signed Blob 입력은 아바타 변경 API에서 받지 않는다.
공개 기본 아바타 asset은 그대로 사용한다. 과거의 Active Storage 아바타 URL은 더 이상 제공되지 않는다.

## 최소 검증 명령

Ruby/Bundler가 설정된 개발 환경에서 사용자가 실행한다.

```bash
bin/rails db:migrate
bundle exec rspec spec/requests/jjaek_photos_spec.rb spec/services/jjaek_photo_changes_spec.rb
bundle exec rspec spec/system/jjaek_photos_spec.rb
bundle exec rspec spec/requests/jjaeks_basic_flow_spec.rb spec/requests/account/settings_spec.rb spec/helpers/users_helper_spec.rb spec/system/avatar_preview_spec.rb
git diff --check
```

브라우저에서는 사진 1~4장 배치·2000px 축소·개별 제거·수정, 책 선택 취소/복귀·Turbo 왕복·검증 실패의 초안,
모바일 swipe/PC 키보드·확대 번호·아바타를 확인한다. 서로 다른 계정으로 전체 공개/책친구/나만 보기/동아리/
프로필 대화, 관계 해제·membership 종료·숨김·삭제 후 같은 원본/Variant URL의 재요청을 확인한다.
운영 OCI에서 실제 object 생성/삭제·Variant 재사용·헤더·큐 재시도와 VM RSS를 확인한 후 배포 검증을 기록한다.
