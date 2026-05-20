#!/bin/bash

set -e

REGION="ap-southeast-1"

echo "=== STEP 1: BUILD TRIAGE ==="
cd triage
sam build

echo "=== STEP 2: DEPLOY TRIAGE ==="
sam deploy \
  --stack-name ticketops-triage \
  --region $REGION \
  --capabilities CAPABILITY_IAM \
  --confirm-changeset \
  --resolve-s3

echo "=== GET OUTPUT TRIAGE ==="
QUEUE_URL=$(aws cloudformation describe-stacks \
  --stack-name ticketops-triage \
  --query "Stacks[0].Outputs[?OutputKey=='QueueUrl'].OutputValue" \
  --output text)

API_URL=$(aws cloudformation describe-stacks \
  --stack-name ticketops-triage \
  --query "Stacks[0].Outputs[?OutputKey=='ApiEndpoint'].OutputValue" \
  --output text)

cd ..

echo "Queue URL: $QUEUE_URL"
echo "API URL: $API_URL"

echo "=== STEP 3: BUILD DISPATCHER ==="
cd dispatcher
sam build

echo "=== STEP 4: DEPLOY DISPATCHER ==="
sam deploy \
  --stack-name ticketops-dispatcher \
  --region $REGION \
  --capabilities CAPABILITY_IAM \
  --parameter-overrides QueueUrl=$QUEUE_URL \
  --confirm-changeset \
  --resolve-s3

cd ..

echo "=== STEP 5: DEPLOY WEB ==="

BUCKET="ticketops-web-$RANDOM"

aws s3 mb s3://$BUCKET --region $REGION

# Replace API URL in web otomatis
sed "s|API_URL_PLACEHOLDER|$API_URL|g" web/index.html > web/index_deployed.html

aws s3 cp web/index_deployed.html s3://$BUCKET/index.html

aws s3 website s3://$BUCKET \
  --index-document index.html

echo "=== DEPLOY COMPLETE ==="
echo "Web URL: http://$BUCKET.s3-website-$REGION.amazonaws.com"