#!/bin/bash
set -e

3 website s3://$BUCKET \REGION="ap-southeast-1"
  --index-document index.html

echo "======================================"
echo "✅ PROD DEPLOY COMPLETE"
echo "🌐 Web: http://$BUCKET.s3-website-$REGION.amazonaws.com"
echo "======================================"

echo "=== DEPLOY TRIAGE (PROD) ==="
cd triage

sam build

sam deploy \
  --stack-name ticketops-prod-triage \
  --region $REGION \
  --capabilities CAPABILITY_IAM \
  --resolve-s3 \
  --confirm-changeset

echo "=== GET OUTPUT ==="

QUEUE_ARN=$(aws cloudformation describe-stacks \
  --stack-name ticketops-prod-triage \
  --query "Stacks[0].Outputs[?OutputKey=='QueueArn'].OutputValue" \
  --output text)

API_URL=$(aws cloudformation describe-stacks \
  --stack-name ticketops-prod-triage \
  --query "Stacks[0].Outputs[?OutputKey=='ApiEndpoint'].OutputValue" \
  --output text)

cd ..

echo "=== DEPLOY DISPATCHER (PROD) ==="
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

echo "=== DEPLOY WEB (PROD) ==="

BUCKET="ticketops-prod-web-$RANDOM"

aws s3 mb s3://$BUCKET --region $REGION

sed "s|API_URL_PLACEHOLDER|$API_URL|g" web/index.html > web/index_deployed.html

aws s3 cp web/index_deployed.html s3://$BUCKET/index.html

