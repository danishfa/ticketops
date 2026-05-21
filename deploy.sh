#!/bin/bash
set -e

REGION="ap-southeast-1"

echo "=============================="
echo "🚀 START DEPLOY (PROD)"
echo "=============================="

echo "=== STEP 1: DEPLOY TRIAGE ==="
cd triage

sam build

sam deploy \
  --template-file template.yaml \
  --stack-name ticketops-prod-triage \
  --region $REGION \
  --capabilities CAPABILITY_IAM \
  --resolve-s3 \
  --confirm-changeset

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

echo "=== STEP 2: DEPLOY DISPATCHER ==="
cd dispatcher

sam build

sam deploy \
  --stack-name ticketops-prod-dispatcher \
  --region $REGION \
  --capabilities CAPABILITY_IAM \
  --parameter-overrides QueueArn=$QUEUE_ARN \
  --resolve-s3 \
  --confirm-changeset

cd ..

echo "=== STEP 3: DEPLOY WEB ==="

BUCKET="ticketops-prod-web-$RANDOM"

aws s3 mb s3://$BUCKET --region $REGION

# Inject API URL ke HTML
sed "s|API_URL_PLACEHOLDER|$API_URL|g" web/index.html > web/index_deployed.html

aws s3 cp web/index_deployed.html s3://$BUCKET/index.html

aws s3 website s3://$BUCKET \
  --index-document index.html

echo "=============================="
echo "✅ DEPLOY COMPLETE"
echo "🌐 Web URL:"
echo "http://$BUCKET.s3-website-$REGION.amazonaws.com"
echo "=============================="