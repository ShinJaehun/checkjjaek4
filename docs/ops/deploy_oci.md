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

`20261106000000` 적용 후에는 이전 이미지만으로 직접 rollback하지 않는다. 구버전은 일반 짹의
첨부 연결을 거부하고 새 첨부를 읽지 못하며, migration의 down도 불가능하다.

1. 운영 복원본에서 전환과 복구를 먼저 리허설한다. 배포 직전 기존 `APP_IMAGE`를 기록하고,
   아래 백업 절차로 웹과 내장 Solid Queue를 중단한 상태에서 **네 운영 DB 모두** 백업한다.
   백업 파일 무결성을 확인하고 웹을 재개하지 않는다.
2. 중단 상태에서 전환 전 Jjaek·Comment·Like·알림 건수, ID·시각·visibility·인용/삭제 marker,
   기존 book_id와 추천 연결의 Book ID·position을 대조 자료로 확보한다. 혼합 충돌·5권 초과는
   임의 정리하지 말고 배포를 중단한다.
3. 새 `APP_IMAGE`를 선택하고 위 Compose 명령의 `pull web`, `run --rm web bin/rails db:prepare`를
   실행한다. 웹·내장 작업은 계속 중단한다. DDL과 백필은 잠금을 유지하므로 무중단 작업으로 취급하지 않는다.
4. 재개 전에 전후 자료를 대조한다. 기존 ID·본문·시각·관계·공개 범위가 보존되고,
   단일 book_id는 첨부 1권으로, 추천 연결은 기존 순서 그대로 전환되었으며
   `book_attachments_migrated`가 완료되었는지 확인한다. 성공 후에만 `up -d web`으로 재개하고 주요 화면을 확인한다.
5. 실패 시 서비스를 중단한 채 원인을 확인한다. 구버전으로 복귀하려면 배포 직전 백업 시점의
   네 DB와 그 시점에 호환되는 이미지로 **함께 복구**한다. 아래 복원 절차에서 먼저 해당 `APP_IMAGE`를
   선택하고 `pull web`을 수행하며, 새 이미지를 선택한 채 복원하지 않는다. 복원 후 웹을 올리기 전에
   데이터 대조와 호환성을 확인한다.

쓰기 재개 후 백업을 복원하면 백업 이후 변경은 잃는다. 실제 복원 검증 없이 무손실 복구를 보장하지 않는다.
잠금 시간·디스크/WAL 여유·1GB 서버 메모리는 운영 복원본에서 확인한다.

## 백업과 복원

일관된 시점의 덤프를 위해 웹을 잠시 중지한다. Solid Queue도 웹의 Puma 안에서 실행하므로 함께 중지된다. 커스텀 형식 덤프에는 PostgreSQL의 압축이 적용된다. 네 DB를 모두 백업한 뒤 무결성 목록을 만든다.

```bash
cd ~/apps/checkjjaek
BACKUP_DIR="$HOME/backups/checkjjaek/$(date +%Y%m%d-%H%M%S)"
mkdir -p "$BACKUP_DIR"
docker compose -p checkjjaek --env-file .env -f compose.prod.yml stop web
for db in checkjjaek4_production checkjjaek4_production_cache checkjjaek4_production_queue checkjjaek4_production_cable; do
  docker compose -p checkjjaek --env-file .env -f compose.prod.yml exec -T db pg_dump -U checkjjaek4 -Fc -d "$db" > "$BACKUP_DIR/$db.dump" || exit 1
done
sha256sum "$BACKUP_DIR"/*.dump > "$BACKUP_DIR/SHA256SUMS"
```

덤프 실패 시 백업을 성공으로 취급하지 말고 `docker compose -p checkjjaek --env-file .env -f compose.prod.yml logs db`로 원인을 확인한다. 일반 백업만 수행한 경우에는 확인 후 `docker compose -p checkjjaek --env-file .env -f compose.prod.yml up -d web`으로 서비스를 재개한다. 업데이트 직전에는 중지 상태를 유지하고 위의 업데이트 명령으로 재개한다. 사용자 업로드는 현재 OCI Object Storage에 있으므로 DB 덤프에 포함되지 않는다. E10의 Object Storage 백업·복원 절차를 별도로 따른다.

복원은 서비스 중지, 복원 대상 시점의 `APP_IMAGE` 선택, 덤프 파일 확인 후 실행한다. 다음 예시의 `BACKUP_DIR`은 실제 백업 디렉터리로 지정한다. 복원은 현재 네 DB의 테이블을 덤프 내용으로 교체한다.

```bash
cd ~/apps/checkjjaek
BACKUP_DIR="$HOME/backups/checkjjaek/YYYYMMDD-HHMMSS"
cd "$BACKUP_DIR" && sha256sum -c SHA256SUMS || exit 1
cd ~/apps/checkjjaek
docker compose -p checkjjaek --env-file .env -f compose.prod.yml stop web
docker compose -p checkjjaek --env-file .env -f compose.prod.yml up -d db
docker compose -p checkjjaek --env-file .env -f compose.prod.yml run --rm web bin/rails db:prepare
for db in checkjjaek4_production checkjjaek4_production_cache checkjjaek4_production_queue checkjjaek4_production_cable; do
  docker compose -p checkjjaek --env-file .env -f compose.prod.yml exec -T db pg_restore -U checkjjaek4 -d "$db" --clean --if-exists --no-owner --single-transaction < "$BACKUP_DIR/$db.dump" || exit 1
done
```

네 DB 복원이 모두 성공하면 데이터와 선택한 이미지의 호환성을 대조한 뒤
`docker compose -p checkjjaek --env-file .env -f compose.prod.yml up -d web`으로 재개한다.

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
