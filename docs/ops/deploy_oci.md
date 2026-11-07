# OCI 운영 배포: E05 / E12

## 구성과 준비물

Cloudflare (HTTPS) → Nginx (HTTPS) → `127.0.0.1:3000` → `checkjjaek_web:80` → PostgreSQL 16 `checkjjaek_db` 순서다. OCI Ubuntu 24.04 E2.1.Micro의 기존 Docker, Docker Compose, Nginx를 사용한다. Compose 프로젝트 이름은 `checkjjaek`이며 운영 파일은 `~/apps/checkjjaek/.env`, `~/apps/checkjjaek/compose.prod.yml`에 둔다. PostgreSQL의 5432 포트는 호스트에 게시하지 않는다.

저장소의 `compose.prod.yml`과 `.env.example`을 운영 디렉터리로 복사하고, `.env.example`을 `.env`로 복사해 값을 채운다. `.env`는 `chmod 600 .env`로 보호한다. 비밀값, Cloudflare Origin 인증서의 개인키, DB 덤프는 Git에 넣지 않는다. `config/deploy.yml`의 Kamal 예제는 이 배포 경로에서 사용하지 않는다.

서버에 저장소 checkout이 있다면 그 디렉터리에서 최초 한 번 다음을 실행한다. 다른 컴퓨터에서 배포 파일을 준비한다면 같은 두 파일만 서버의 운영 디렉터리로 복사한다.

```bash
mkdir -p ~/apps/checkjjaek ~/backups/checkjjaek
cp compose.prod.yml ~/apps/checkjjaek/compose.prod.yml
cp -n .env.example ~/apps/checkjjaek/.env
chmod 600 ~/apps/checkjjaek/.env
```

`.env` 항목:

| 변수 | 필요 여부와 의미 |
| --- | --- |
| `APP_IMAGE` | 필수. 성공한 main CI에서 게시된 `ghcr.io/shinjaehun/checkjjaek4:sha-<40자리 커밋 SHA>` |
| `APP_PORT` | 선택. Nginx가 접속하는 호스트 loopback 포트, 기본 3000 |
| `CHECKJJAEK4_DATABASE_PASSWORD` | 필수. PostgreSQL `checkjjaek4` 역할과 Rails의 네 DB 공통 암호 |
| `CHECKJJAEK4_DATABASE_HOST` | 선택. Compose 내부 DB 서비스 이름, 기본 `db` |
| `SECRET_KEY_BASE` 또는 `RAILS_MASTER_KEY` | 둘 중 하나 필수. 기존 암호화 credentials를 쓴다면 master key 제공 |
| `RESEND_API_KEY` | 필수. Resend SMTP 인증 키. 웹 컨테이너에만 전달하며 Git에 저장하지 않음 |
| `RAILS_LOG_LEVEL`, `RAILS_MAX_THREADS`, `WEB_CONCURRENCY` | 선택. 기본 `info`, `5`, `1`; OCI E2 Micro에서 확인한 스레드 설정 |
| `OCI_AVATAR_ACCESS_KEY_ID`, `OCI_AVATAR_SECRET_ACCESS_KEY`, `OCI_AVATAR_REGION`, `OCI_AVATAR_BUCKET`, `OCI_AVATAR_ENDPOINT` | 현재 production의 `oci_avatars` 서비스에 모두 필수. 값과 스토리지 운영 절차는 E10에서 관리 |

`RAILS_ENV=production`, 웹 컨테이너의 Thruster 포트 80, `SOLID_QUEUE_IN_PUMA=1`은 Compose에서 고정한다. Puma는 기존 설정대로 컨테이너 안의 3000 포트를 사용한다. 운영 주소/도메인, GHCR 읽기 권한, Cloudflare와 Nginx 인증서도 서버에서 준비한다. GHCR 패키지가 private이면 서버에서 해당 패키지 `read:packages` 권한으로 `docker login ghcr.io`를 먼저 수행한다.

운영 메일은 Resend SMTP(`smtp.resend.com:465`, TLS)를 사용한다. 배포 전에 Resend에서 발급한 키를 서버의 `~/apps/checkjjaek/.env`에 `RESEND_API_KEY=...`로 등록하고 파일 권한 `600`을 유지한다. `account@jjaek.kr` 발신 도메인의 Resend 검증을 확인한다. 새 이미지와 `compose.prod.yml`을 배포한 뒤 아래 기존 Compose 절차로 웹 컨테이너를 재생성한다. 키 값은 명령 인자나 로그에 출력하지 않는다. 관리자 초대 메일과 비밀번호 재설정 메일의 발신자는 `책짹 <account@jjaek.kr>`, 회신 주소는 `support@jjaek.kr`이며 링크는 `https://jjaek.kr`을 사용한다.

## 최초 배포와 DB 준비

다음은 운영 디렉터리에서 실행한다. `APP_IMAGE`는 CI가 통과한 main 커밋의 GHCR 태그로 채운다. 저장소의 `.env.example`에는 비밀값이 없으므로 그대로 실행하지 않는다.

```bash
cd ~/apps/checkjjaek
chmod 600 .env
docker compose -p checkjjaek --env-file .env -f compose.prod.yml config --quiet
docker compose -p checkjjaek --env-file .env -f compose.prod.yml pull web
docker compose -p checkjjaek --env-file .env -f compose.prod.yml up -d db
docker compose -p checkjjaek --env-file .env -f compose.prod.yml run --rm web bin/rails db:prepare
docker compose -p checkjjaek --env-file .env -f compose.prod.yml up -d web
docker compose -p checkjjaek --env-file .env -f compose.prod.yml ps
curl -fsS http://127.0.0.1:3000/up
```

PostgreSQL 초기화는 `POSTGRES_DB=checkjjaek4_production`과 역할 `checkjjaek4`를 **빈 볼륨에서만** 만든다. `db:prepare`가 같은 컨테이너에 `checkjjaek4_production`, `_cache`, `_queue`, `_cable` 네 논리 DB와 각각의 schema를 준비한다. Production seed는 기본 스티커 정의 6개만 생성한다. PostgreSQL 공식 이미지의 `POSTGRES_USER`는 DB 생성 권한을 가진 역할이므로 보조 DB도 생성할 수 있다. 이미 생성된 볼륨에서는 PostgreSQL 초기화가 재실행되지 않으며, `db:prepare`를 다시 실행하면 기존 데이터는 유지하고 필요한 migration만 적용한다. 웹 컨테이너의 기존 entrypoint도 서버 시작 시 `db:prepare`를 실행한다.

다음으로 DB 네 개의 존재와 schema를 확인한다. 각 DB의 `schema_migrations` 조회가 성공해야 한다. 보조 DB의 migration 수는 0일 수 있다.

```bash
cd ~/apps/checkjjaek
docker compose -p checkjjaek --env-file .env -f compose.prod.yml exec db psql -U checkjjaek4 -d checkjjaek4_production -Atc "SELECT datname FROM pg_database WHERE datname LIKE 'checkjjaek4_production%' ORDER BY datname"
for db in checkjjaek4_production checkjjaek4_production_cache checkjjaek4_production_queue checkjjaek4_production_cable; do
  docker compose -p checkjjaek --env-file .env -f compose.prod.yml exec -T db psql -U checkjjaek4 -d "$db" -Atc 'SELECT COUNT(*) FROM schema_migrations'
done
```

## GHCR 게시와 일반 업데이트

기존 `CI`는 pull request와 main push에서 그대로 실행한다. `Publish GHCR image`는 **main push의 CI 전체가 성공한 경우에만** CI에서 검사한 정확한 커밋을 `sha-<commit SHA>` 태그로 게시한다. `latest`를 운영에 사용하지 않는다. GitHub Actions의 패키지 쓰기 권한이 필요하다.

업데이트 전 현재 `.env`의 `APP_IMAGE` 값을 기록하고, 아래 백업을 수행한다. 백업 뒤 웹을 중지한 상태에서 새 SHA 태그로 `.env`의 `APP_IMAGE` 한 줄만 바꾸고 다음을 실행한다. 이미지 태그가 변경되어도 PostgreSQL의 Compose 볼륨은 유지된다.

```bash
cd ~/apps/checkjjaek
docker compose -p checkjjaek --env-file .env -f compose.prod.yml config --quiet
docker compose -p checkjjaek --env-file .env -f compose.prod.yml pull web
docker compose -p checkjjaek --env-file .env -f compose.prod.yml run --rm web bin/rails db:prepare
docker compose -p checkjjaek --env-file .env -f compose.prod.yml up -d web
docker compose -p checkjjaek --env-file .env -f compose.prod.yml ps
curl -fsS http://127.0.0.1:3000/up
```

재시작만 필요한 경우 `docker compose -p checkjjaek --env-file .env -f compose.prod.yml restart web`을 사용한다. 문제가 생기면 DB와 호환되는 이전 `APP_IMAGE`에 한해 `pull web`, `up -d web`으로 복귀한다. 코드만 이전으로 되돌려도 이미 적용된 DB migration은 되돌아가지 않는다. 통합 짹 전환은 아래 예외 절차를 반드시 따른다.

## 통합 짹 migration 배포 예외

통합 이전 이미지로 **이미지만 바꾸는 rollback을 하지 않는다**. 백필·구형 컬럼 제거는 되돌릴 수 없으며,
rename만 되돌려도 구버전 호환이 회복되지 않는다. 배포 직전의 네 DB와 호환 GHCR 이미지를 함께 복구한다.

1. 아래 별도 환경 리허설을 먼저 완료한다. 기존 운영에는 `jjaek_recommendations`가 없어도 정상이다.
   기존 추천 연결 생성(`20261103000000`) → 통합 백필(`20261106000000`) →
   rename(`20261107000000`) → 구형 컬럼 제거(`20261108000000`) 순서로 적용한다.
   기존 migration을 편집하거나 이미 적용한 version을 임의로 기록하지 않는다.
2. 웹·Puma 내장 Solid Queue·별도 console/one-off/예약 작업 등 **모든 쓰기**를 중단한다.
   아래 절차로 배포 직전 네 DB와 기존 이미지 정보를 백업하고 웹을 재개하지 않는다.
3. 전환 전 Jjaek·첨부 책·댓글·좋아요·태그·알림·moderation과 다시짹의 ID·시각·관계·공개 범위,
   기존 book_id와 추천 연결 순서를 대조 자료로 확보한다. 혼합 충돌·5권 초과는 임의 정리하지 말고 중단한다.
4. 새 SHA 이미지로 `.env`의 `APP_IMAGE`만 변경하고 일반 업데이트의 `pull web`,
   `run --rm web bin/rails db:prepare`까지만 수행한다. 웹과 내장 작업은 계속 중단한다.
   백필과 DDL은 잠금을 사용하므로 무중단 전환이 아니다.
5. 재개 전에 관계·ID·시각과 첨부 순서를 대조한다. 최종 테이블은 `jjaek_book_attachments`이며
   `book_id`/`recommendation`/`book_attachments_migrated`는 Jjaek에서 제거된다.
   `legacy_source_kind`와 첨부의 `visible_on_tombstone`이 과거 의미를 보존하는지 확인한다.
   A의 비공개 전환·snapshot, B/C의 원문 식별 정보 제거·독립 토론, 두 사람 전용 접근도 확인한다.
6. 검증 성공 후에만 웹을 재개한다. 실패하면 중단 상태를 유지하고 아래 빈 DB 복원 절차로
   배포 직전 네 DB와 기존 이미지를 함께 복구한다. migration down이나 구버전 이미지 단독 시작은 복구 절차가 아니다.

잠금 시간·WAL/디스크 여유·OCI E2 Micro 1GB의 메모리는 리허설에서 측정한다. 출력 제거는 잠금이나 지연 해결의 근거가 아니다.
쓰기 재개 후 백업을 복원하면 백업 이후 데이터는 유실된다. 실제 복원 검증 없이 무손실 복구를 보장하지 않는다.

## 백업과 복원

### 쓰기 중단과 네 DB 백업

아래 Bash 블록은 운영자가 **운영 디렉터리와 대상 컨테이너를 확인한 뒤** 실행한다.
오류 시 즉시 중단하며 웹을 자동으로 재시작하지 않는다. 운영 환경에서 이 문서를 작성하며 실행한 명령은 없다.

웹을 중단하면 `SOLID_QUEUE_IN_PUMA=1`의 내장 작업도 중단된다. 별도 실행한 작업·console·migration·외부 DB 클라이언트도
모두 종료하고, 백업부터 배포 또는 복구 완료까지 쓰기를 막는다. 네 덤프는 순차 실행되므로 하나의 DB 간 공통 snapshot이 아니다.
모든 쓰기가 멈춘 기간에만 논리적으로 일관된 네 DB 백업이 된다. 예약 작업이 다시 연결하지 않도록 별도로 확인한다.

```bash
set -euo pipefail
umask 077
cd ~/apps/checkjjaek
compose() { docker compose -p checkjjaek --env-file .env -f compose.prod.yml "$@"; }
OPS_DBS=(checkjjaek4_production checkjjaek4_production_cache checkjjaek4_production_queue checkjjaek4_production_cable)
OPS_BACKUP_DIR="$HOME/backups/checkjjaek/$(date -u +%Y%m%dT%H%M%SZ)"
mkdir -p "$OPS_BACKUP_DIR"
docker inspect --format '{{.Config.Image}}' checkjjaek_web > "$OPS_BACKUP_DIR/APP_IMAGE"
docker inspect --format '{{.Image}}' checkjjaek_web > "$OPS_BACKUP_DIR/IMAGE_ID"
OPS_IMAGE=$(cat "$OPS_BACKUP_DIR/APP_IMAGE")
[[ "$OPS_IMAGE" =~ ^ghcr\.io/shinjaehun/checkjjaek4:sha-[0-9a-f]{40}$ ]] || exit 1
compose stop web
OPS_CONNECTIONS=$(compose exec -T db psql -X -U checkjjaek4 -d postgres -v ON_ERROR_STOP=1 -Atc \
  "SELECT count(*) FROM pg_stat_activity WHERE datname IN ('checkjjaek4_production','checkjjaek4_production_cache','checkjjaek4_production_queue','checkjjaek4_production_cable')")
[[ "$OPS_CONNECTIONS" == 0 ]] || { echo '남은 DB 연결이 있습니다. 쓰기 작업을 중단하세요.'; exit 1; }
date -u +%FT%TZ > "$OPS_BACKUP_DIR/STARTED_AT_UTC"
compose exec -T db psql -X -U checkjjaek4 -d postgres -v ON_ERROR_STOP=1 -AtF $'\t' -c \
  "SELECT datname, pg_get_userbyid(datdba), pg_encoding_to_char(encoding), datcollate, datctype, datlocprovider FROM pg_database WHERE datname IN ('checkjjaek4_production','checkjjaek4_production_cache','checkjjaek4_production_queue','checkjjaek4_production_cable') ORDER BY datname" \
  > "$OPS_BACKUP_DIR/databases.tsv"
for OPS_DB in "${OPS_DBS[@]}"; do
  compose exec -T db psql -X -U checkjjaek4 -d "$OPS_DB" -v ON_ERROR_STOP=1 -AtF $'\t' \
    -c 'SELECT extname, extversion FROM pg_extension ORDER BY extname' > "$OPS_BACKUP_DIR/$OPS_DB.extensions.tsv"
  compose exec -T db pg_dump -U checkjjaek4 -Fc -d "$OPS_DB" > "$OPS_BACKUP_DIR/$OPS_DB.dump"
  test -s "$OPS_BACKUP_DIR/$OPS_DB.dump"
  wc -c < "$OPS_BACKUP_DIR/$OPS_DB.dump" > "$OPS_BACKUP_DIR/$OPS_DB.bytes"
  compose exec -T db pg_restore --list < "$OPS_BACKUP_DIR/$OPS_DB.dump" > "$OPS_BACKUP_DIR/$OPS_DB.list"
  compose exec -T db pg_restore --file=/dev/null < "$OPS_BACKUP_DIR/$OPS_DB.dump"
done
date -u +%FT%TZ > "$OPS_BACKUP_DIR/FINISHED_AT_UTC"
(cd "$OPS_BACKUP_DIR" && sha256sum APP_IMAGE IMAGE_ID STARTED_AT_UTC FINISHED_AT_UTC databases.tsv *.dump *.list *.bytes *.extensions.tsv > SHA256SUMS)
(cd "$OPS_BACKUP_DIR" && sha256sum -c SHA256SUMS)
```

`APP_IMAGE`는 `.env`의 희망 값이 아니라 실행하던 컨테이너의 태그다. `IMAGE_ID`와 백업 시작·종료 시각도 보관한다.
완료 파일이 없거나 명령 하나라도 실패하면 성공한 백업으로 취급하지 않는다. 파일 크기는 이상 징후 확인용이며 checksum은
복사 중 변조·손상을 확인한다. `--list`와 SQL 출력 전체 읽기는 아카이브의 해독 가능성을 확인할 뿐 실제 DB 복원·제약 검증을 대신하지 않는다.
덤프와 기록을 서버 밖의 보호된 위치에도 복사하고 checksum을 다시 확인한다. 비밀값을 출력하거나 Git에 보관하지 않는다.

일반 백업만 했다면 백업 확인 후 웹을 재개할 수 있다. 업데이트 직전이라면 중단 상태를 유지한다.
DB 덤프에는 OCI Object Storage의 아바타 파일이 포함되지 않으므로 E10의 별도 보존·복구 절차도 따른다.

### 복원 준비 — 아직 DB를 삭제하지 않는 확인 지점

기존 DB에 `db:prepare`를 실행한 뒤 `pg_restore --clean`으로 덮지 않는다.
[`--clean`은 복원할 객체만 삭제](https://www.postgresql.org/docs/16/app-pgrestore.html)하므로 새 버전의 테이블·외래키가 남을 수 있다.
복원에서는 대상 DB 전체를 삭제한 후 [`pg_restore --create`](https://www.postgresql.org/docs/16/app-pgrestore.html)가
아카이브의 DB 정의로 빈 DB를 만들고 복원하게 한다. DB 이름·encoding·locale·소유권·DB별 설정과 ACL도 확인한다.
복원할 이미지로도 아직 웹을 시작하거나 `db:prepare`를 실행하지 않는다.

아래의 백업 경로를 실제 값으로 바꾼다. 이 예시는 같은 PostgreSQL 16 클러스터의 네 DB와 기존 `checkjjaek4` 역할을 사용한다.
DB 이름이 다른 덤프, 다른 소유자/역할, 추가 tablespace·확장 기능이 있으면 이 절차를 그대로 진행하지 말고 별도 환경에서 먼저 조정·검증한다.

```bash
set -euo pipefail
umask 077
cd ~/apps/checkjjaek
compose() { docker compose -p checkjjaek --env-file .env -f compose.prod.yml "$@"; }
OPS_DBS=(checkjjaek4_production checkjjaek4_production_cache checkjjaek4_production_queue checkjjaek4_production_cable)
OPS_BACKUP_DIR="$HOME/backups/checkjjaek/YYYYMMDDTHHMMSSZ"
test -s "$OPS_BACKUP_DIR/STARTED_AT_UTC"
test -s "$OPS_BACKUP_DIR/FINISHED_AT_UTC"
(cd "$OPS_BACKUP_DIR" && sha256sum -c SHA256SUMS)
export APP_IMAGE="$(cat "$OPS_BACKUP_DIR/APP_IMAGE")"
[[ "$APP_IMAGE" =~ ^ghcr\.io/shinjaehun/checkjjaek4:sha-[0-9a-f]{40}$ ]] || exit 1
compose config --quiet
compose stop web
compose up -d db
compose pull web
OPS_RESTORED_IMAGE_ID=$(docker image inspect --format '{{.Id}}' "$APP_IMAGE")
[[ "$OPS_RESTORED_IMAGE_ID" == "$(cat "$OPS_BACKUP_DIR/IMAGE_ID")" ]] || exit 1
for OPS_DB in "${OPS_DBS[@]}"; do
  test -s "$OPS_BACKUP_DIR/$OPS_DB.dump"
  compose exec -T db pg_restore --list < "$OPS_BACKUP_DIR/$OPS_DB.dump" > "$OPS_BACKUP_DIR/$OPS_DB.restore.list"
  awk -v name="$OPS_DB" '$4 == "DATABASE" && $5 == "-" && $6 == name { found = 1 } END { exit !found }' \
    "$OPS_BACKUP_DIR/$OPS_DB.restore.list"
  compose exec -T db pg_restore --file=/dev/null < "$OPS_BACKUP_DIR/$OPS_DB.dump"
done
cat "$OPS_BACKUP_DIR/APP_IMAGE" "$OPS_BACKUP_DIR/IMAGE_ID" "$OPS_BACKUP_DIR/databases.tsv"
compose exec -T db psql -X -U checkjjaek4 -d postgres -v ON_ERROR_STOP=1 -c \
  "SELECT version(); SELECT rolname, rolsuper, rolcreatedb FROM pg_roles WHERE rolname = 'checkjjaek4'; SELECT name, version FROM pg_available_extension_versions ORDER BY name, version; SELECT datname, usename, application_name, state FROM pg_stat_activity WHERE datname IN ('checkjjaek4_production','checkjjaek4_production_cache','checkjjaek4_production_queue','checkjjaek4_production_cable');"
```

**중단 지점:** 호스트·Compose 프로젝트·DB 컨테이너·네 DB 이름, 백업 시각·완료 여부·전체 checksum,
DB 생성 TOC 항목, 이전 이미지의 실제 pull 성공을 확인한다. `databases.tsv`의 소유자와 TOC의 객체 소유자가
기존 역할과 일치하는지 확인한다. 덤프는 역할 자체를 만들지 않으므로 필요한 역할이 없으면 중단한다.
현재 Compose의 `POSTGRES_USER=checkjjaek4`는 초기화 시 superuser로 생성되지만 이미 존재하는 볼륨의 실제 권한을 확인해야 한다.
`*.extensions.tsv`와 `pg_available_extension_versions`를 대조해 같은 확장 버전·라이브러리가 준비되어 있는지도 확인한다.
소유권/권한 오류를 피하려고 `--no-owner`/`--no-acl`로 우회하지 않는다.

활성 연결이 남으면 쓰기 작업을 찾아 중단한다. `--force`는 사용하지 않는다.
연결·권한·prepared transaction·논리 복제 등의 오류는 자동 정리하거나 무시하지 말고 중단한다.
복원할 덤프 자체도 신뢰할 수 있는 보관본이어야 한다. 현재 실패 상태도 보존해야 한다면 별도 경로에 먼저 백업한다.

### DB 재생성과 복원 — 네 DB의 현재 데이터를 삭제하는 지점

**사전 조건:** 위 준비 블록과 모든 수동 확인을 완료했고, 웹·내장 작업·외부 쓰기 프로세스가 모두 중단되어야 한다.
같은 Bash 세션에서만 이어서 실행한다. 네 DB의 현재 데이터는 아래 명령으로 사라진다.
확인 문자열을 입력하기 전까지 삭제하지 않으며, 백업이 불확실하면 여기서 멈춘다.
`docker compose down -v`나 PostgreSQL 볼륨 삭제는 하지 않는다.

```bash
read -r -p '네 운영 DB를 삭제하고 지정 백업으로 복원합니다. RESTORE-FOUR-DBS 입력: ' OPS_CONFIRM
[[ "$OPS_CONFIRM" == RESTORE-FOUR-DBS ]] || exit 1
for OPS_DB in "${OPS_DBS[@]}"; do
  compose exec -T db dropdb -U checkjjaek4 --maintenance-db=postgres --if-exists "$OPS_DB"
done
for OPS_DB in "${OPS_DBS[@]}"; do
  compose exec -T db pg_restore -U checkjjaek4 --dbname=postgres --create --exit-on-error \
    < "$OPS_BACKUP_DIR/$OPS_DB.dump"
done
```

[`dropdb --if-exists`](https://www.postgresql.org/docs/16/app-dropdb.html)는 이미 없는 DB만 오류 없이 건너뛴다.
부분 삭제·복원 실패 후에도 준비 절차와 사전 확인을 다시 완료하고 네 DB 삭제부터 재시도할 수 있다.
연결·권한 등 다른 오류는 기존 `set -euo pipefail`에 따라 계속 중단하며 `--force`는 사용하지 않는다.
`--create`는 덤프에 기록된 이름으로 DB를 생성하므로 앞선 이름 검사가 필수다. template0 기반 생성 정의와
확장 생성 명령을 사용하고 객체 소유권·ACL을 복원한다. 복원 전에 Rails schema나 확장을 임의로 만들지 않는다.
이 절차의 `--create`는 `--single-transaction`과 함께 사용할 수 없다. 오류 시 즉시 종료하지만 해당 DB는 부분 복원 상태일 수 있고,
네 DB 전체도 원자적으로 복원되지 않는다. 하나라도 실패하면 웹을 시작하지 말고 원인 확인 후 네 DB 재생성부터 다시 수행한다.

### 복원 검증과 서비스 재개

모든 복원이 성공한 뒤 다음을 확인한다. **확인 전에는 `db:prepare`·웹 시작을 하지 않는다.**

- 네 DB의 소유자·encoding·locale·확장 버전·DB별 설정/ACL이 백업과 일치한다.
- 네 DB의 schema와 `schema_migrations`가 백업 시점에 맞으며, 새 이미지가 추가했던 테이블·외래키가 남아 있지 않다.
  통합 이전 백업이라면 새 첨부 테이블이 없어야 한다. 구형 DB를 새 모델로 먼저 조회하지 않는다.
- 기본 데이터 건수뿐 아니라 ID·시각·첨부/인용 관계·댓글·좋아요·알림 등을 배포 직전 대조 자료와 비교한다.
- 백업 시점과 호환되는 이미지로 `bin/rails db:migrate:status`와 읽기 검증을 수행한다. 이 명령은 DB를 준비하는 명령이 아니다.
  예상치 못한 pending migration이 있으면 웹 entrypoint가 실행하기 전에 중단한다.

```bash
# 복원 준비에서 export한 기존 APP_IMAGE를 사용하는 같은 세션이다.
compose run --rm --no-deps web bin/rails db:migrate:status
```

운영자가 `.env`의 `APP_IMAGE` 한 줄도 복원한 태그로 바꾼다. 현재 shell의 export만 바꾸면 다음 로그인에서
새 태그로 다시 시작할 수 있다. 태그와 복원 DB의 호환성을 재확인한 뒤에만 서비스를 재개한다.
웹 entrypoint는 시작 시 `db:prepare`를 실행하므로 새 이미지를 선택한 상태로 시작하면 안 된다.

```bash
compose up -d web
compose ps
curl -fsS http://127.0.0.1:3000/up
```

큐 DB까지 복원하면 백업 당시 대기 작업도 다시 실행될 수 있으므로 외부 메일 등 이미 발생한 부수 효과와 중복 가능성을 확인한다.
네 DB의 순차 백업·비원자적 복원, 백업 이후 데이터 유실과 Object Storage의 별도 보존 한계는 복원 성공과 별개로 남는다.

## 데이터 전환과 복구 리허설

실제 운영 배포 전에 **운영과 분리된 PostgreSQL 16·Compose 환경**에서 사용자가 수행한다.
운영 디렉터리·컨테이너 이름·볼륨·DB host·포트·credentials를 공유하지 않는다. 현재 Compose는 container_name이 고정이므로
프로젝트 이름만 바꾸면 격리가 보장되지 않는다. 고정 이름·볼륨·포트까지 분리한 복사본인지 확인한다.
위 운영 명령의 경로·Compose 함수·고정 대상도 리허설용으로 바꿔야 하며 운영 값을 그대로 복사해 실행하지 않는다.
운영 메일/작업 실행과 Object Storage 쓰기도 차단한다. 이 문서 작업에서는 환경을 구축하거나 리허설을 실행하지 않는다.

1. 기존 운영 네 DB 백업과 호환 이전 이미지를 확보한다. 위 아카이브 검증 후 별도 환경의 빈 DB로 복원한다.
   기존 DB에 추천 연결 테이블이 없는 경우를 포함하고, 빈 DB의 전체 migration 경로도 기존 migration spec으로 확인한다.
2. 전환 전 자료를 남긴다. 알려진 운영 수량은 짹 50개(단일 book_id 30개)·댓글 18개·좋아요 24개지만,
   리허설 입력은 해당 백업의 실제 값이다. 건수만 비교하지 말고 각 row의 ID·본문·시각·작성자·대상자·visibility·group_id,
   인용/삭제 marker, 첨부의 Book ID·position·row ID, 태그·알림·moderation 관계를 비교할 수 있도록 내보낸다.
3. 쓰기 중단 상태에서 새 이미지의 `bin/rails db:migrate:status`로 적용 대상을 확인한 뒤
   `bin/rails db:prepare`를 한 번 실행한다. 위 네 migration의 순서와 성공을 확인한다.
   혼합 충돌·미전환 오류가 있으면 자동 병합하지 말고 중단한다. 실행 시간·잠금·메모리·디스크/WAL도 기록한다.
4. 최종 구조를 확인한다. 기존 단일 book_id는 첨부 한 권, 기존 추천 row는 같은 ID·Book·position·시각이며
   새 테이블로 rename되었다. Jjaek의 세 구형 컬럼은 없어지고 기존 ID·본문·댓글·좋아요·태그·알림·moderation 관계가 남는다.
   이전 book_id와 일치한 첨부만 `visible_on_tombstone=true`이며 과거 `legacy_source_kind`/snapshot 의미가 보존된다.
5. 별도 검증 데이터에서 댓글 보존 tombstone의 기존 책은 표시되고 통합 이후 첨부는 삭제 후 노출되지 않는지 확인한다.
   A는 원문 삭제 후 본인 전용·snapshot 보존, B/C는 원문 식별 정보 제거·독립 본문/댓글/좋아요 보존을 확인한다.
   살아 있는 원문 접근 상실·복구와 프로필 대화의 당사자/제3자 접근을 HTML·Turbo에서 확인한다.
6. 새 이미지로 기본 작성·첨부 0/1/5권·수정/제거·서재 독립성, 검색/발견/책 상세/관리자,
   선택 완료/취소/Back·초안·모바일 페이지 링크/추가 버튼을 확인한다. 기존 권한 테스트를 약화하지 않는다.
7. 별도 환경의 전환된 네 DB를 위 복원 절차로 재생성하고 **전환 전 백업+이전 이미지**로 복귀한다.
   새 테이블·외래키 잔존이 없고 원래 schema_migrations·데이터·권한과 이전 이미지의 시작이 맞는지 확인한다.
   필요한 보조 DB·큐 상태도 확인하며, 다시 새 이미지로 전환할 수 있는지 확인한다.
8. 백업 위치·시각·이미지 SHA·비교 결과·소요 시간·실패 시 중단/복구 절차를 기록한다.
   이 확인 없이는 운영 전환이나 무손실 복구를 보장하지 않는다.

## Nginx, Cloudflare, 실제 IP

Cloudflare SSL/TLS를 **Full (strict)** 로 사용하고, Nginx 443에 유효한 Origin 인증서를 설정한다. OCI 보안 규칙과 호스트 방화벽에서는 443 접근을 Cloudflare IP 범위로 제한하고 3000/5432를 외부에 개방하지 않는다. 80은 필요한 인증서 발급 또는 리다이렉트 목적에만 연다. 알 수 없는 HTTPS SNI는 기본 server에서 거부한다.

Nginx의 `set_real_ip_from`에는 [Cloudflare가 게시하는 IPv4/IPv6 대역](https://www.cloudflare.com/ips/)만 넣고 변경될 때 갱신한다. `real_ip_header CF-Connecting-IP;`는 [Cloudflare의 원본 IP 복원 지침](https://developers.cloudflare.com/support/troubleshooting/restoring-visitor-ips/restoring-original-visitor-ips/)대로 이 신뢰 범위와 함께 사용한다. 다음은 공식 도메인과 인증서 경로를 채워 적용할 핵심 설정이다.

신뢰 대역 파일은 서버에서 다음처럼 만들고, Cloudflare 대역이 바뀌면 같은 명령으로 갱신한다.

```bash
curl -fsS https://www.cloudflare.com/ips-v4 -o /tmp/checkjjaek-cloudflare-v4 && \
curl -fsS https://www.cloudflare.com/ips-v6 -o /tmp/checkjjaek-cloudflare-v6 && \
awk 'NF == 1 { printf "set_real_ip_from %s;\n", $1 }' /tmp/checkjjaek-cloudflare-v4 /tmp/checkjjaek-cloudflare-v6 | sudo tee /etc/nginx/cloudflare-real-ip.conf >/dev/null
```

```nginx
map $http_upgrade $connection_upgrade {
    default upgrade;
    '' close;
}

server {
    listen 443 ssl;
    server_name <공식 도메인>;
    ssl_certificate <Origin 인증서 경로>;
    ssl_certificate_key <Origin 개인키 경로>;

    include /etc/nginx/cloudflare-real-ip.conf; # Cloudflare CIDR의 set_real_ip_from 목록
    real_ip_header CF-Connecting-IP;

    location / {
        proxy_pass http://127.0.0.1:3000;
        proxy_http_version 1.1;
        proxy_set_header Host $host;
        proxy_set_header X-Forwarded-Proto https;
        proxy_set_header X-Forwarded-For $remote_addr;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_set_header Upgrade $http_upgrade;
        proxy_set_header Connection $connection_upgrade;
    }
}
```

`X-Forwarded-For`를 복원된 `$remote_addr` 한 값으로 재설정해 외부 요청이 보낸 값을 이어 붙이지 않는다. Rails의 `request.remote_ip`는 이 값을 이용한다. 적용 전 `sudo nginx -t`로 검사한다. Cloudflare 우회 직접 접속과 임의의 `CF-Connecting-IP` 헤더가 원본 IP로 인정되지 않는지 확인한다.

## 장애와 운영 검증

```bash
cd ~/apps/checkjjaek
docker compose -p checkjjaek --env-file .env -f compose.prod.yml ps
docker compose -p checkjjaek --env-file .env -f compose.prod.yml logs --tail=100 web db
docker compose -p checkjjaek --env-file .env -f compose.prod.yml exec db pg_isready -U checkjjaek4 -d checkjjaek4_production
docker compose -p checkjjaek --env-file .env -f compose.prod.yml run --rm web bin/rails runner 'puts Rails.cache.class.name'
docker compose -p checkjjaek --env-file .env -f compose.prod.yml run --rm web bin/rails runner 'abort unless Rails.cache.write("ops:cache-check", "ok", expires_in: 1.minute)'
docker compose -p checkjjaek --env-file .env -f compose.prod.yml run --rm web bin/rails runner 'abort unless Rails.cache.read("ops:cache-check") == "ok"; Rails.cache.delete("ops:cache-check")'
```

캐시는 Solid Cache, Queue는 Puma의 Solid Queue supervisor, Cable은 `config/cable.yml`의 `solid_cable`/cable DB를 사용한다. 웹 로그에서 Queue 시작 오류와 DB 접속 오류를 확인하고, 운영 화면에서 실제 알림 또는 Turbo 실시간 갱신을 확인한다. Solid Cache는 별도 cache DB를 사용하므로 Rate Limit 카운터도 프로세스 간 공유된다. 위 명령은 같은 키를 두 번의 별도 `rails runner` 실행에서 쓰고 읽어 공유 캐시 접속을 검증한다.

인증 요청 Rate Limit은 `request.remote_ip`에 의존한다. 서로 다른 외부 네트워크의 통제된 요청에 대해 Nginx access log의 복원된 `$remote_addr`와 Rails request log의 IP가 각각 일치하는지 확인한다. 같은 IP에서 테스트 계정으로 로그인 제한을 초과시켜 HTTP 429를 확인하고, 다른 IP의 테스트 요청에는 같은 제한이 전파되지 않는지 확인한다. 운영 사용자의 IP나 이메일 원문을 검증 로그에 따로 남기지 않는다.
