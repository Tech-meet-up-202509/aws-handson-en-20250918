# AWS EKS Hands-on Workshop (50 minutes) — IAM User Edition (NAT + Private Nodes)

## 6. Wrap-up & Clean up (5 min)

To remove all resources at the end of the hands-on, run the cleanup script:

```bash
./scripts/cleanup.sh
```

This script performs the following steps:

### 6-1) Kubernetes resource cleanup
```bash
kubectl delete svc nginx --ignore-not-found
kubectl delete pod nginx --ignore-not-found
```
Removes the Service and Pod created during the workshop.

### 6-2) Terraform destroy
```bash
cd tffiles
terraform destroy -auto-approve || true
cd ..
```
Destroys the EKS cluster, VPC, and related infrastructure provisioned by Terraform.

### 6-3) GuardDuty cleanup
```bash
DET_ID=$(aws guardduty list-detectors --query 'DetectorIds[0]' --output text 2>/dev/null || echo "None")
if [ "$DET_ID" != "None" ] && [ -n "$DET_ID" ]; then
  aws guardduty delete-detector --detector-id ${DET_ID} || true
fi
```
Checks if a GuardDuty detector exists and deletes it.

### 6-4) Security Hub cleanup
```bash
if aws securityhub describe-hub >/dev/null 2>&1; then
  aws securityhub disable-security-hub || true
fi
```
Disables Security Hub if it was enabled during the session.

---

> 👉 **Key takeaway:** Instead of memorizing all the commands, you can reuse scripts like `cleanup.sh`.  
> But it’s important to understand what each command does — deleting Kubernetes objects, tearing down infrastructure, and cleaning up security services.
