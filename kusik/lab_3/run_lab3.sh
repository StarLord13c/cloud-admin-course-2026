#!/usr/bin/env bash
# Лабораторна робота №3 — Статичний веб-хостинг на S3 + Bucket Policy
# Запуск: bash run_lab3.sh (Git Bash на Windows)

set -uo pipefail

cd "$(dirname "$0")"

LOG="lab3_report.log"
: > "$LOG"
exec > >(tee -a "$LOG") 2>&1

export AWS_ENDPOINT_URL="http://localhost:4566"
export AWS_DEFAULT_REGION="us-east-1"
export AWS_ACCESS_KEY_ID="test"
export AWS_SECRET_ACCESS_KEY="test"

BUCKET="web-hosting-bucket"
SITE_URL="http://${BUCKET}.s3-website.localhost.localstack.cloud:4566/"

step() {
  echo ""
  echo "============================================================"
  echo "  $*"
  echo "============================================================"
}

run() {
  echo ""
  echo "\$ $*"
  "$@"
}

# ----------------------------------------------------------------
step "SETUP: перевірка LocalStack"
# ----------------------------------------------------------------

if ! docker inspect -f '{{.State.Health.Status}}' localstack-main 2>/dev/null | grep -q healthy; then
  echo "Контейнер не запущено — виконую docker compose up -d"
  docker compose up -d
  echo "Очікую healthcheck..."
  for i in $(seq 1 60); do
    s=$(docker inspect -f '{{.State.Health.Status}}' localstack-main 2>/dev/null || echo "none")
    [ "$s" = "healthy" ] && break
    sleep 2
  done
fi
docker compose ps

# ----------------------------------------------------------------
step "КРОК 1. Підготовка локального середовища"
# ----------------------------------------------------------------
echo "index.html присутній: $(ls -la index.html | awk '{print $5, $9}')"
echo "policy.json присутній: $(ls -la policy.json | awk '{print $5, $9}')"

# ----------------------------------------------------------------
step "КРОК 2. Створення бакета та активація Static Website Hosting"
# ----------------------------------------------------------------
run aws s3 mb "s3://${BUCKET}"
run aws s3 website "s3://${BUCKET}/" --index-document index.html

# ----------------------------------------------------------------
step "КРОК 3. Завантаження контенту"
# ----------------------------------------------------------------
run aws s3 cp index.html "s3://${BUCKET}/"
run aws s3 ls "s3://${BUCKET}"

# ----------------------------------------------------------------
step "КРОК 4. Прикріплення bucket policy (публічний доступ)"
# ----------------------------------------------------------------
run aws s3api put-bucket-policy --bucket "${BUCKET}" --policy file://policy.json
run aws s3api get-bucket-policy --bucket "${BUCKET}" --output text --query Policy

# ----------------------------------------------------------------
step "КРОК 5. Перевірка через curl"
# ----------------------------------------------------------------
echo "URL сайту: $SITE_URL"
echo ""
echo "\$ curl -sI $SITE_URL | head -5"
curl -sI "$SITE_URL" | head -5
echo ""
echo "\$ curl -s $SITE_URL"
curl -s "$SITE_URL"

# ----------------------------------------------------------------
step "ПІДСУМОК"
# ----------------------------------------------------------------
echo "✓ Сайт розгорнуто: $SITE_URL"
echo "  Bucket:  $BUCKET"
echo "  Звіт:    $LOG"
echo ""
echo "Відкрий $SITE_URL у браузері для візуальної перевірки."
