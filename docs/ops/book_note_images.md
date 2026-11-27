# 독서 노트 이미지 운영

저장 기반과 API 계약은 [독서 노트 명세](../specs/book_notes.md#이미지-저장-기반)를 따른다.

## 배포 전 준비

1. 운영에서는 짹 사진과 같은 비공개 `checkjjaek-photos` 버킷(`oci_photos`)과 기존 `OCI_PHOTO_BUCKET` 설정을 사용한다. 공개 접근과 PAR을 사용하지 않으며, 객체 쓰기·읽기(존재 확인 포함)·삭제에는 기존 `OCI_STORAGE_*` 인증을 쓴다. [OCI 운영 배포](deploy_oci.md)
2. 운영 반영 시 `20261127000000_create_book_note_images` migration을 적용한다. Nginx와 Cloudflare가 파일당 5MB와 multipart 부가 데이터를 허용하는지 확인한다. 현재 Nginx 예시는 `client_max_body_size 25m`을 사용한다.
3. 테스트 계정으로 앱의 인증 업로드·조회 주소와 교차 계정 `404`를 확인한다. 응답은 앱 경로를 사용하고 OCI 주소나 서명 URL을 제공하지 않아야 한다. Active Storage 기본 Blob·representation·direct-upload 라우트는 비활성 상태를 확인한다.

## 기존 Blob 확인

조회와 삭제는 각 Blob의 `service_name`에 기록된 서비스를 사용한다. 기존 개발의 `local` 파일과 테스트의 `test` 파일은 같은 서비스에서 처리된다. 운영에 독서 노트 이미지를 처음 배포할 때는 옮길 객체가 없다.

이전 코드를 production 모드로 시험한 환경에서는 아래 명령으로 독서 노트 Blob의 서비스별 건수를 확인한다.

```bash
bin/rails runner 'puts BookNoteImage.joins(:blob).group("active_storage_blobs.service_name").count'
```

`oci_book_note_images`에 저장한 이미지가 있으면 전환 전에 기존 버킷에서 해당 객체를 같은 키로 사진 버킷에 복사한다. 복사한 객체를 확인한 뒤 해당 독서 노트 Blob의 `service_name`을 `oci_photos`로 변경한다.

## 정리와 장애 확인

- Solid Queue가 매시 55분에 `CleanupBookNoteImagesJob`을 실행한다. 이 작업은 만료·중단·삭제 대기 이미지의 ID를 `PurgeBookNoteImageJob`으로 넘긴다. 노트·계정 삭제는 주소 접근을 즉시 차단하고 객체는 정리 작업에서 회수한다.
- 삭제 Job의 실패 내역과 `BookNoteImage.purgeable` 건수를 확인한다. 오류가 있으면 버킷 권한, 연결, 저장소 상태를 점검한다. 삭제가 성공할 때까지 `book_note_images`의 소유자별 예약과 `active_storage_blobs`의 키를 보존한다. DB 행을 수동으로 먼저 삭제하면 재시도와 용량 추적이 끊긴다.
- 저장량은 앱에서 추적하는 최적화 객체 기준이다. 삭제된 객체의 이전 버전까지 보존하는 버킷 설정을 사용하면 OCI 사용량과 차이가 날 수 있다. 앱의 만료 조건과 별개로 활성 객체를 일괄 만료시키는 규칙은 피한다.
