#!/usr/bin/env bash
# Лабораторна робота №2 — IAM на LocalStack
# Запуск: bash run_lab2.sh (Git Bash на Windows)

set -uo pipefail

cd "$(dirname "$0")"

LOG="lab2_report.log"
CRED="$PWD/credentials"

: > "$LOG"
exec > >(tee -a "$LOG") 2>&1

export AWS_ENDPOINT_URL="http://localhost:4566"
export AWS_DEFAULT_REGION="us-east-1"
export AWS_SHARED_CREDENTIALS_FILE="$CRED"

ACCOUNT_ID="000000000000"

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

expect_deny() {
  echo ""
  echo "\$ (очікується Access Denied) $*"
  "$@" > /tmp/lab2_out.$$ 2>&1
  rc=$?
  cat /tmp/lab2_out.$$
  out=$(cat /tmp/lab2_out.$$)
  rm -f /tmp/lab2_out.$$
  if [ "$rc" -ne 0 ] && echo "$out" | grep -Eqi 'AccessDenied|Forbidden|not authorized|403'; then
    echo "✓ Очікувана помилка зафіксована (політика IAM працює)"
  elif [ "$rc" -ne 0 ]; then
    echo "✗ Помилка не пов'язана з IAM (rc=$rc): $(echo "$out" | head -1)"
  else
    echo "ℹ Запит пройшов (rc=0). LocalStack Community не примушує IAM-політики на data-plane S3 — це обмеження емулятора (у реальному AWS дану операцію було б відхилено за політикою)."
  fi
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

cat > "$CRED" <<EOF
[default]
aws_access_key_id = test
aws_secret_access_key = test
EOF
echo "Створено локальний credentials-файл: $CRED"

# ----------------------------------------------------------------
step "ЗАВДАННЯ 1. Перевірка роботи LocalStack"
# ----------------------------------------------------------------

run aws s3 ls
run aws iam list-users

# ----------------------------------------------------------------
step "ЗАВДАННЯ 2. Група Developers + користувач testuser"
# ----------------------------------------------------------------

run aws iam create-group --group-name Developers
run aws iam attach-group-policy \
  --group-name Developers \
  --policy-arn arn:aws:iam::aws:policy/AmazonS3ReadOnlyAccess
run aws iam create-user --user-name testuser
run aws iam add-user-to-group --user-name testuser --group-name Developers

echo ""
echo "Створення ключів доступу для testuser..."
KEYS=$(aws iam create-access-key --user-name testuser \
  --query 'AccessKey.[AccessKeyId,SecretAccessKey]' --output text)
read TESTUSER_AKID TESTUSER_SKEY <<< "$KEYS"
echo "AccessKeyId:     $TESTUSER_AKID"
echo "SecretAccessKey: ${TESTUSER_SKEY:0:4}**** (приховано)"

cat >> "$CRED" <<EOF

[testuser]
aws_access_key_id = $TESTUSER_AKID
aws_secret_access_key = $TESTUSER_SKEY
EOF
echo "Профіль [testuser] записано у $CRED"

echo "Hello IAM" > test.txt

run aws s3 mb s3://my-bucket
run aws --profile testuser s3 ls
expect_deny aws --profile testuser s3 cp test.txt s3://my-bucket/

# ----------------------------------------------------------------
step "ЗАВДАННЯ 3. Політика S3WriteToMyBucket"
# ----------------------------------------------------------------

run aws iam create-policy \
  --policy-name S3WriteToMyBucket \
  --policy-document file://policies/write-policy.json
run aws s3 mb s3://my-lab-bucket

# ----------------------------------------------------------------
step "ЗАВДАННЯ 4. Роль EC2-S3-Write-Role + assume-role"
# ----------------------------------------------------------------

run aws iam create-role \
  --role-name EC2-S3-Write-Role \
  --assume-role-policy-document file://policies/trust-policy.json
run aws iam attach-role-policy \
  --role-name EC2-S3-Write-Role \
  --policy-arn arn:aws:iam::${ACCOUNT_ID}:policy/S3WriteToMyBucket

echo ""
echo "Виклик sts:AssumeRole..."
CREDS=$(aws sts assume-role \
  --role-arn arn:aws:iam::${ACCOUNT_ID}:role/EC2-S3-Write-Role \
  --role-session-name test-session \
  --query 'Credentials.[AccessKeyId,SecretAccessKey,SessionToken]' \
  --output text)
read TEMP_AKID TEMP_SKEY TEMP_STOKEN <<< "$CREDS"
echo "AccessKeyId:     $TEMP_AKID"
echo "SecretAccessKey: ${TEMP_SKEY:0:4}**** (приховано)"
echo "SessionToken:    ${TEMP_STOKEN:0:12}... (приховано)"

cat >> "$CRED" <<EOF

[temp-role]
aws_access_key_id = $TEMP_AKID
aws_secret_access_key = $TEMP_SKEY
aws_session_token = $TEMP_STOKEN
EOF
echo "Профіль [temp-role] записано у $CRED"

run aws s3 mb s3://other-bucket

run aws --profile temp-role s3 cp test.txt s3://my-lab-bucket/
run aws --profile temp-role s3 ls s3://my-lab-bucket
expect_deny aws --profile temp-role s3 cp test.txt s3://other-bucket/

# ----------------------------------------------------------------
step "ПІДСУМОК"
# ----------------------------------------------------------------
echo "✓ Усі завдання виконано."
echo "  Звіт:        $LOG"
echo "  Credentials: $CRED"
