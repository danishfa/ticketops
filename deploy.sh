#!/bin/bash
set -e

REGION="ap-southeast-1"

echo "=============================="
echo "🚀 START DEPLOY (PROD)"
echo "=============================="

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
  --no-confirm-changeset

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

sam deploy \
  --stack-name ticketops-prod-dispatcher \
  --region $REGION \
  --capabilities CAPABILITY_IAM \
  --parameter-overrides QueueArn=$QUEUE_ARN \
  --resolve-s3 \
  --no-confirm-changeset

cd ..

# ==============================
# STEP 3 — WEB
# ==============================
echo "=== STEP 3: DEPLOY WEB ==="

BUCKET="ticketops-prod-web-$RANDOM"

aws s3 mb s3://$BUCKET --region $REGION

# ✅ MATIKAN BLOCK PUBLIC ACCESS
aws s3api put-public-access-block \
  --bucket $BUCKET \
  --public-access-block-configuration \
  BlockPublicAcls=false,IgnorePublicAcls=false,BlockPublicPolicy=false,RestrictPublicBuckets=false

# ✅ SET POLICY PUBLIC
aws s3api put-bucket-policy \
  --bucket $BUCKET \
  --policy "{
    \"Version\":\"2012-10-17\",
    \"Statement\":[{
      \"Effect\":\"Allow\",
      \"Principal\":\"*\",
      \"Action\":\"s3:GetObject\",
      \"Resource\":\"arn:aws:s3:::$BUCKET/*\"
    }]
  }"

# ✅ INJECT API URL
sed "s|API_URL_PLACEHOLDER|$API_URL|g" web/index.html > web/index_deployed.html

# ✅ UPLOAD WEB
aws s3 cp web/index_deployed.html s3://$BUCKET/index.html

# ✅ ENABLE WEBSITE
aws s3 website s3://$BUCKET \
  --index-document index.html

echo "=============================="
echo "✅ DEPLOY COMPLETE"
echo "🌐 Web URL:"
echo "http://$BUCKET.s3-website-$REGION.amazonaws.com"
echo "=============================="
