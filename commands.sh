#!/usr/bin/env bash
# Bài 4: Custom Network & Named Volume bằng Docker CLI
# Yêu cầu: đã build image backend hw-backend:v1 (bài 2) trên máy này.
set -euo pipefail

NETWORK=app-net
VOLUME=db-data
DB_NAME_CT=db-server
APP_CT=app-container
BACKEND_IMAGE=hw-backend:v1
HOST_PORT=8081          # đổi nếu cổng này đang bị chiếm

DB_USER=appuser
DB_PASS=apppass
DB_DB=appdb

wait_for_db() {
  echo ">> Đợi PostgreSQL sẵn sàng..."
  for i in $(seq 1 30); do
    if docker exec "$DB_NAME_CT" pg_isready -U "$DB_USER" -d "$DB_DB" >/dev/null 2>&1; then
      echo "   DB đã sẵn sàng."
      return 0
    fi
    sleep 1
  done
  echo "DB không khởi động được!" >&2
  docker logs "$DB_NAME_CT" >&2
  exit 1
}

run_db() {
  docker run -d --name "$DB_NAME_CT" \
    --network "$NETWORK" \
    -v "$VOLUME":/var/lib/postgresql/data \
    -e POSTGRES_USER="$DB_USER" \
    -e POSTGRES_PASSWORD="$DB_PASS" \
    -e POSTGRES_DB="$DB_DB" \
    postgres:15-alpine
}

echo "===== 0. Dọn môi trường cũ (nếu có) ====="
docker rm -f "$APP_CT" "$DB_NAME_CT" >/dev/null 2>&1 || true
docker volume rm "$VOLUME" >/dev/null 2>&1 || true
docker network rm "$NETWORK" >/dev/null 2>&1 || true

echo "===== 1. Tạo Custom Bridge Network: $NETWORK ====="
docker network create --driver bridge "$NETWORK"

echo "===== 2. Tạo Named Volume: $VOLUME ====="
docker volume create "$VOLUME"

echo "===== 3. Chạy Database Container: $DB_NAME_CT ====="
run_db
wait_for_db

echo "===== 4. Chạy Backend Container: $APP_CT ====="
docker run -d --name "$APP_CT" \
  --network "$NETWORK" \
  -p "$HOST_PORT":3000 \
  -e DB_HOST="$DB_NAME_CT" \
  -e DB_PORT=5432 \
  -e DB_USER="$DB_USER" \
  -e DB_PASSWORD="$DB_PASS" \
  -e DB_NAME="$DB_DB" \
  "$BACKEND_IMAGE"

echo "===== 5. Kiểm tra network, volume, DNS ====="
docker network ls | grep "$NETWORK"
docker volume ls | grep "$VOLUME"
docker network inspect "$NETWORK"
docker exec "$APP_CT" ping -c 2 "$DB_NAME_CT"

echo "===== 6. Test Data Persistence ====="
echo ">> 6.1 Thêm dữ liệu"
docker exec "$DB_NAME_CT" psql -U "$DB_USER" -d "$DB_DB" -c \
  "CREATE TABLE IF NOT EXISTS students(id SERIAL PRIMARY KEY, name TEXT);
   INSERT INTO students(name) VALUES ('Nguyen Van A'), ('Tran Thi B');"
docker exec "$DB_NAME_CT" psql -U "$DB_USER" -d "$DB_DB" -c "SELECT * FROM students;"

echo ">> 6.2 Xóa cứng container DB"
docker rm -f "$DB_NAME_CT"
docker ps -a --filter "name=$DB_NAME_CT"

echo ">> 6.3 Tạo lại container DB mới, gắn cùng volume $VOLUME"
run_db
wait_for_db

echo ">> 6.4 Xác minh dữ liệu còn nguyên"
docker exec "$DB_NAME_CT" psql -U "$DB_USER" -d "$DB_DB" -c "SELECT * FROM students;"

echo "===== HOÀN TẤT ====="
