#!/usr/bin/env bash
set -euo pipefail
: "${AWS_REGION:=ap-northeast-1}"
echo "== AWS Caller Identity =="
aws sts get-caller-identity || { echo "Failed to call STS"; exit 1; }

echo "== Region (override with AWS_REGION) =="
echo "${AWS_REGION}"

echo "== API reachability checks (best-effort) =="
declare -a calls=(
  "eks:list-clusters"
  "ec2:describe-vpcs"
  "iam:list-roles"
  "autoscaling:describe-auto-scaling-groups"
  "securityhub:get-enabled-standards"
  "guardduty:list-detectors"
)
for c in "${calls[@]}"; do
  svc="${c%%:*}"; op="${c##*:}"
  echo "- ${svc} ${op}"
  aws "${svc}" "${op}" --region "${AWS_REGION}" >/dev/null 2>&1 || echo "  (info) ${svc} ${op} failed; ensure permissions exist"
done
echo "Checks completed."
