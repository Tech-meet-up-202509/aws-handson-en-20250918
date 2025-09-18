# AWS EKS Hands-on Workshop (50 minutes) 

> Adapted from the original AKS hands-on repository [k8s-meetup-novice/aks-handson-20250708](https://github.com/k8s-meetup-novice/aks-handson-20250708), rewritten for **AWS (EKS/VPC)** and timeboxed to **~50 minutes**.  
> This edition uses **IAM user access keys** (no SSO). Nodes run in **Private Subnets** with **NAT Gateway enabled**.

---
## Key Concepts

Before we start the hands-on, here are some quick explanations of the main technologies we use:

### Kubernetes
Kubernetes is an open-source system for **orchestrating containers**.  
It helps you run, scale, and manage containerized applications automatically.  
In this workshop, we use **Amazon EKS (Elastic Kubernetes Service)**, which is a managed Kubernetes service on AWS.

### Infrastructure as Code (IaC)
Infrastructure as Code means **defining and managing infrastructure (servers, networks, etc.) in code** rather than manual configuration.  
This makes environments reproducible, version-controlled, and easy to share among team members.

### Terraform
Terraform is one of the most popular IaC tools.  
It lets you describe cloud resources (like VPCs, subnets, and clusters) in configuration files and then **provision them automatically**.  
In this workshop, Terraform creates our **VPC, NAT Gateway, and EKS cluster**.

👉 These concepts are connected like this:  
We use **Terraform (IaC)** to build the cloud infrastructure, and on top of that, we use **Kubernetes (via EKS)** to run our application.

--- 

## Cloud Service Models: IaaS / PaaS / SaaS

When using the cloud, there are three common service models.  
Here’s a simple way to understand them:

- **IaaS (Infrastructure as a Service)**  
  - Provides virtualized infrastructure such as servers, storage, and networking.  
  - Example: **Amazon EC2, VPC**  
  - Users are responsible for installing and managing the OS, middleware, and applications.  

- **PaaS (Platform as a Service)**  
  - Provides a managed platform where you can deploy applications without worrying about the underlying infrastructure.  
  - Example: **AWS Elastic Beanstalk, AWS Lambda**  
  - The provider manages the OS and runtime, while the user focuses on the application code and data.  

- **SaaS (Software as a Service)**  
  - Ready-to-use applications delivered over the internet.  
  - Example: **Gmail, Salesforce**  
  - The provider manages everything; users simply consume the service.  

## Shared Responsibility Model

In cloud computing, security and operations are a **shared responsibility** between the cloud provider (AWS) and the customer (you).  
The division of responsibility changes depending on the service model.  

| Responsibility Area        | IaaS (Customer vs AWS)              | PaaS (Customer vs AWS)              | SaaS (Customer vs AWS)         |
|-----------------------------|--------------------------------------|-------------------------------------|--------------------------------|
| **Applications**            | Customer                            | Customer                            | AWS                            |
| **Data**                    | Customer                            | Customer                            | Customer (limited)             |
| **Runtime / Middleware**    | Customer                            | AWS                                 | AWS                            |
| **Operating System**        | Customer                            | AWS                                 | AWS                            |
| **Virtualization**          | AWS                                 | AWS                                 | AWS                            |
| **Hardware / Facilities**   | AWS                                 | AWS                                 | AWS                            |

👉 The rule of thumb:  
- In **IaaS**, you manage most of the stack (OS, middleware, apps, data).  
- In **PaaS**, AWS manages the platform, you manage the apps and data.  
- In **SaaS**, AWS manages almost everything, you mainly use the service and secure your data.  

---

## 0. Prerequisites (5 min)

- AWS Account (team sandbox) and **an IAM user** with permissions for **VPC, EKS, IAM, EC2, ELB/ALB, Security Hub, GuardDuty**  
  - For simplicity in a sandbox: `AdministratorAccess`
- Tools: **AWS CLI v2**, **Terraform v1.6+**, **kubectl v1.30+**
- **GitHub Codespaces** / Dev Container (this repo auto-sets region & unique name prefix)

> [!NOTE]
> *IAM permissions* 
> In this hands-on, we assign **AdministratorAccess** to simplify setup.  
> In a production scenario, the minimal required permissions would span:  
> - **VPC / EC2** (VPC, Subnet, NAT Gateway, Route, IGW)  
> - **EKS** (Cluster, Nodegroup management)  
> - **IAM** (Role creation and PassRole for EKS/NodeGroup)  
> - **ELB / NLB** (LoadBalancer + TargetGroup)  
> - **Auto Scaling** (for NodeGroups)  
> - **Security Hub & GuardDuty** (enable, list, get findings)  
>
> 👉 See AWS docs for detailed policy actions. 

## Generating AWS Access Keys

To use the AWS CLI, each participant needs an **Access Key ID** and a **Secret Access Key**.  
In this workshop, the instructor will create IAM users in advance and provide each participant with their own access keys.

### How to create access keys (for instructor)
1. Go to the **AWS Management Console** → **IAM** → **Users**.  
2. Select the user you want to generate keys for.  
3. Navigate to the **Security credentials** tab.  
4. Under **Access keys**, click **Create access key**.  
5. Choose the use case (e.g., CLI access), then confirm.  
6. Download the `.csv` file containing the Access Key ID and Secret Access Key.  

⚠️ Important: The Secret Access Key is only shown once. Keep it safe and share it securely with participants.

### How participants configure the key
Once you receive your key, configure it in the Codespaces terminal:

```bash
aws configure
# Default region: ap-northeast-1
# Default output: json
```

Verify:
```bash
aws sts get-caller-identity
```

### 0-2) Auto name prefix (no typing needed)
In Codespaces, this repo **auto-sets**:
- `AWS_REGION=ap-northeast-1`
- `TF_VAR_name_prefix=eks-hands-on-<your-github-name>` (derived from `git config user.name` and normalized)

> Implemented via Dev Container. After Codespaces startup, **open a new terminal** so env vars from `~/.bashrc` are loaded.

---

## 1. What Terraform provisions in this workshop

A **lightweight Terraform configuration** to keep provisioning time and cost low, while realistic enough for demos:

- **VPC**
  - 1 VPC (`10.4.0.0/16`)
  - 2 public subnets + 2 private subnets
  - **NAT Gateway: enabled (single)** so that **Private** nodes can pull images & reach the internet
  - **Kubernetes-required subnet tags** set for ELB/NLB provisioning:
    - Public: `kubernetes.io/role/elb = 1`, `kubernetes.io/cluster/${var.name_prefix}-eks = shared`
    - Private: `kubernetes.io/role/internal-elb = 1`, `kubernetes.io/cluster/${var.name_prefix}-eks = shared`

- **EKS Cluster**
  - Name: `${var.name_prefix}-eks`
  - Version: Kubernetes **1.30**
  - Public endpoint enabled (`0.0.0.0/0`) for simplicity (restrict in production)
  - Cluster creator is granted admin permissions

- **Managed Node Group**
  - **Private subnets** (egress via NAT Gateway)
  - Size: desired=1 (min=1, max=2)
  - Instance: `t3.small`, 20 GB disk

- **Outputs**
  - `eks_cluster_name` for easier `kubectl` setup

This setup lets you:
- Deploy workloads (nginx)
- Expose via **LoadBalancer Service** → **NLB in Public Subnets** → Internet
- Demonstrate **Security Hub** and **GuardDuty** quickly

---

## 2. Create EKS with Terraform (15 min)

```bash
cd tffiles
make quick        # terraform init && terraform apply -auto-approve
```

> While applying, review the Shared Responsibility Model and today’s plan.

Outputs include:
```bash
terraform output -raw eks_cluster_name
```

---

## 3. Deploy nginx on EKS & Access it (10 min)
```bash
# Configure kubectl
aws eks update-kubeconfig --name $(terraform output -raw eks_cluster_name) --region $AWS_REGION

# Sanity
kubectl get nodes

# Deploy nginx Pod
kubectl run nginx --image=nginx -n default

# Expose via LoadBalancer (NLB) in Public Subnets
kubectl apply -f ../scripts/service.yaml

# Wait until EXTERNAL-IP is assigned
kubectl get svc nginx -w
```

**Access the nginx web server:**  
- Copy the `EXTERNAL-IP` shown above and open it in your browser:  
  - `http://<EXTERNAL-IP>/`  
- Or from terminal:
```bash
curl -i http://<EXTERNAL-IP>/
```

> Expected: HTTP/1.1 200 OK with nginx default welcome page.

---

## 4. Security Hub — CLI Demo (10 min)
```bash
# Idempotent enable
if aws securityhub describe-hub >/dev/null 2>&1; then
  echo "Security Hub already enabled."
else
  aws securityhub enable-security-hub
fi

# (Optional) CIS AWS Foundations Benchmark v1.2.0 (errors often mean 'already enabled')
STD_ARN="arn:aws:securityhub:ap-northeast-1::standards/cis-aws-foundations-benchmark/v/1.2.0"
aws securityhub batch-enable-standards --standards-subscription-requests StandardsArn=${STD_ARN} || true

aws securityhub get-enabled-standards
aws securityhub get-findings --max-results 10 | jq '.Findings | length'
```

---

## 5. GuardDuty — CLI Demo (10 min)
```bash
# Idempotent detector create
DET_ID=$(aws guardduty list-detectors --query 'DetectorIds[0]' --output text)
if [ "$DET_ID" = "None" ] || [ -z "$DET_ID" ]; then
  DET_ID=$(aws guardduty create-detector --enable --query DetectorId --output text)
fi
echo "Detector: ${DET_ID}"

# Generate sample findings (for demo)
aws guardduty create-sample-findings --detector-id ${DET_ID}

# List findings (subset) and show count
FINDING_IDS=$(aws guardduty list-findings --detector-id ${DET_ID} --query 'FindingIds[0:5]' --output json)
aws guardduty get-findings --detector-id ${DET_ID} --finding-ids $(echo ${FINDING_IDS} | jq -r '.[]') | jq '.Findings | length'

# Aggregation check in Security Hub
aws securityhub get-findings   --filters '{"ProductName":[{"Value":"GuardDuty","Comparison":"EQUALS"}]}'   --max-results 10 | jq '.Findings | length'
```

---

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

> [!NOTE]
> while the cleanup is running, do not close your browser or shut down Codespaces.
> Wait until the process is completely finished.

> 👉 **Key takeaway:** Instead of memorizing all the commands, you can reuse scripts like `cleanup.sh`.  
> But it’s important to understand what each command does — deleting Kubernetes objects, tearing down infrastructure, and cleaning up security services.

---

> [!NOTE]
> - EKS endpoint is **public** with `0.0.0.0/0` for simplicity; restrict in production.  
> - **NAT Gateway enabled** for Private nodes' egress (time + GB charges apply; for a 30-minute hands-on per person it's typically a few to tens of JPY).  
> - Node group is **tiny** (`t3.small`, desired=1) to reduce cost.  
> - This repo is designed for **hands-on education**: fast, minimal, but realistic.




