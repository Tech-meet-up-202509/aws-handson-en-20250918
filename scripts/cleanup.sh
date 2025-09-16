#!/usr/bin/env bash
set -euo pipefail

echo "== Cleaning up Kubernetes resources =="
kubectl delete svc nginx --ignore-not-found
kubectl delete pod nginx --ignore-not-found

echo "== Destroying Terraform resources =="
cd tffiles
terraform destroy -auto-approve || true
cd ..

echo "== Cleaning up GuardDuty =="
DET_ID=$(aws guardduty list-detectors --query 'DetectorIds[0]' --output text 2>/dev/null || echo "None")
if [ "$DET_ID" != "None" ] && [ -n "$DET_ID" ]; then
  aws guardduty delete-detector --detector-id ${DET_ID} || true
fi

echo "== Cleaning up Security Hub =="
if aws securityhub describe-hub >/dev/null 2>&1; then
  aws securityhub disable-security-hub || true
fi

echo "== Cleanup finished =="
