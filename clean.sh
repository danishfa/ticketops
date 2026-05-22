#!/bin/bash
set -e

REGION="ap-southeast-1"

echo "=============================="
echo "💣 CLEANING ALL TICKETOPS STACK"
echo "=============================="

# =========================
# DELETE STACKS
# =========================
echo "=== DELETE STACK TRIAGE ==="
aws cloudformation delete-stack \
  --stack-name ticketops-prod-triage \
  --region $REGION || true

echo "=== DELETE STACK DISPATCHER ==="
aws cloudformation delete-stack \
  --stack-name ticketops-prod-dispatcher \
  --region $REGION || true

# =========================
# WAIT DELETE COMPLETE
# =========================
echo "=== WAIT FOR STACK DELETE ==="

while true; do
  STACKS=$(aws cloudformation list-stacks \
    --region $REGION \
    --query "StackSummaries[?StackName=='ticketops-prod-triage' || StackName=='ticketops-prod-dispatcher'][?StackStatus!='DELETE_COMPLETE']" \
    --output text)

  if [ -z "$STACKS" ]; then
    break
  fi

  echo "⏳ Waiting stacks to be deleted..."
  sleep 5
done

echo "✅ Stack deletion finished"

# =========================
# CLEAN IAM ROLE (ANTI ROLLBACK_FAILED)
# =========================
echo "=== CLEAN IAM ROLES (IF ANY) ==="

ROLES=$(aws iam list-roles --query "Roles[?contains(RoleName,'ticketops-prod-triage') || contains(RoleName,'ticketops-prod-dispatcher')].RoleName" --output text)

for r in $ROLES; do
  echo "Cleaning role: $r"

  POLICIES=$(aws iam list-attached-role-policies \
    --role-name $r \
    --query "AttachedPolicies[].PolicyArn" \
    --output text)

  for p in $POLICIES; do
    echo " Detach policy: $p"
    aws iam detach-role-policy --role-name $r --policy-arn $p || true
  done

  INLINE=$(aws iam list-role-policies --role-name $r --query "PolicyNames[]" --output text)

  for ip in $INLINE; do
    echo " Delete inline policy: $ip"
    aws iam delete-role-policy --role-name $r --policy-name $ip || true
  done

  aws iam delete-role --role-name $r || true
done

echo "✅ IAM roles cleaned"

# =========================
# DELETE WEB BUCKETS
# =========================
echo "=== DELETE WEB BUCKETS ==="

BUCKETS=$(aws s3 ls | awk '{print $3}' | grep ticketops-prod-web || true)

for b in $BUCKETS; do
  echo "Deleting bucket: $b"
  aws s3 rb s3://$b --force || true
done

echo "✅ Buckets cleaned"

# =========================
# CLEAN LOCAL BUILD
# =========================
echo "=== CLEAN LOCAL CACHE ==="

rm -rf .aws-sam

echo "=============================="
echo "✅ CLEAN COMPLETE (FULL RESET)"
echo "=============================="