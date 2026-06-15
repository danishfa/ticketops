#!/bin/bash
set -e

REGION="ap-southeast-1"

echo "===================================================="
echo "🚀 TICKET-OPS AUTOMATED DEPLOYMENT SYSTEM (PROD) 🚀"
echo "===================================================="
echo ""
echo "Silakan masukkan kredensial Telegram Pelanggan di bawah ini."
echo "Data ini digunakan untuk menghubungkan sistem AWS dengan Bot Anda."
echo ""

# 1. Meminta Input Kredensial secara Interaktif
read -p "🔹 Masukkan Telegram Bot Token Anda: " TELEGRAM_TOKEN
read -p "🔹 Masukkan Telegram Chat ID (Grup Teknisi): " CHAT_ID

if [ -z "$TELEGRAM_TOKEN" ] || [ -z "$CHAT_ID" ]; then
    echo "❌ Error: Bot Token dan Chat ID tidak boleh kosong!"
    exit 1
fi

echo ""
echo "✅ Data divalidasi. Memulai deployment ke AWS..."
echo "----------------------------------------------------"

# ==============================
# STEP 1 — TRIAGE
# ==============================
echo "=== STEP 1: DEPLOY TRIAGE ==="
cd triage

sam build

sam deploy \
  --stack-name ticketops-prod-triage \
  --region $REGION \
  --capabilities CAPABILITY_IAM \
  --resolve-s3 \
  --no-confirm-changeset \
  --on-failure DELETE

echo "=== GET OUTPUT TRIAGE ==="

QUEUE_ARN=$(aws cloudformation describe-stacks \
  --stack-name ticketops-prod-triage \
  --query "Stacks[0].Outputs[?OutputKey=='QueueArn'].OutputValue" \
  --output text)

API_URL=$(aws cloudformation describe-stacks \
  --stack-name ticketops-prod-triage \
  --query "Stacks[0].Outputs[?OutputKey=='ApiEndpoint'].OutputValue" \
  --output text)

cd ..

echo "Queue ARN: $QUEUE_ARN"
echo "API URL: $API_URL"

# ==============================
# STEP 2 — DISPATCHER
# ==============================
echo "=== STEP 2: DEPLOY DISPATCHER ==="
cd dispatcher

sam build

# Mengirimkan Token dan Chat ID pelanggan langsung ke Environment Lambda via Parameter-Overrides
sam deploy \
  --stack-name ticketops-prod-dispatcher \
  --region $REGION \
  --capabilities CAPABILITY_IAM \
  --parameter-overrides QueueArn="$QUEUE_ARN" TelegramToken="$TELEGRAM_TOKEN" ChatId="$CHAT_ID" \
  --resolve-s3 \
  --no-confirm-changeset \
  --on-failure DELETE

cd ..

# ==============================
# STEP 3 — WEB
# ==============================
echo "=== STEP 3: DEPLOY WEB ==="

BUCKET="ticketops-prod-web-$RANDOM"

aws s3 mb s3://$BUCKET --region $REGION

# MATIKAN BLOCK PUBLIC ACCESS
aws s3api put-public-access-block \
  --bucket $BUCKET \
  --public-access-block-configuration \
  BlockPublicAcls=false,IgnorePublicAcls=false,BlockPublicPolicy=false,RestrictPublicBuckets=false

# SET POLICY PUBLIC
aws s3api put-bucket-policy \
  --bucket $BUCKET \
  --policy "{
    \"Version\":\"2012-10-17\",
    \"Statement\":[{
      \"Effect\":\"Allow\",
      \"Principal\":\"*\",
      \"Action\":\"s3:GetObject\",
      \"Resource\":\"arn:aws:s3:::\$BUCKET/*\"
    }]
  }"

# INJECT API URL KE HTML
sed "s|API_URL_PLACEHOLDER|$API_URL|g" web/index.html > web/index_deployed.html

# UPLOAD KE S3
aws s3 cp web/index_deployed.html s3://$BUCKET/index.html

# CONFIG S3 AS WEBSITE
aws s3 website s3://$BUCKET/ --index-document index.html --region $REGION

WEB_URL="http://$BUCKET.s3-website-$REGION.amazonaws.com"

# ====================================================
# STEP 4 — AUTOMATED TELEGRAM WEBHOOK CONFIGURATION
# ====================================================
echo "----------------------------------------------------"
echo "🔄 Mengonfigurasi Webhook Telegram secara otomatis..."

# Menggunakan curl untuk mendaftarkan URL API Gateway baru ke bot pelanggan
WEBHOOK_RES=$(curl -s -X POST "https://api.telegram.org/bot${TELEGRAM_TOKEN}/setWebhook" \
  -H "Content-Type: application/json" \
  -d "{\"url\": \"${API_URL}/ticket\"}")

echo "✉️ Respon Server Telegram: $WEBHOOK_RES"
echo "----------------------------------------------------"

echo "===================================================="
echo "🎉 DEPLOYMENT SUKSES DAN SISTEM SIAP DIGUNAKAN!"
echo "🌐 URL Webform Anda: $WEB_URL"
echo "===================================================="