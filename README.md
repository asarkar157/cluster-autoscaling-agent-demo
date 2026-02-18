# Observability & Security Remediation Demo with Aiden

A demo environment that shows Aiden by StackGen automatically:
1. **Detecting and remediating EKS node pool overutilization** -- scaling node groups up/down (complete)
2. **Detecting and remediating security misconfigurations** -- fixing findings from AWS Security Hub (complete)
3. **Cloud asset inventory management** -- multi-account resource scanning (incomplete, non-functional in Aiden)

> **Note:** Parts 1 and 2 are fully functional end-to-end demos. Part 3 (Cloud Inventory) has the infrastructure and skill definition in place, but the Aiden integration is incomplete and not yet operational.

## Architecture

```
                              +---------------------+
                              |  Aiden by StackGen   |
                              |  (scans AWS account) |
                              +----------+----------+
                                         |
                         detects issues, auto-remediates
                                         |
         +------------------+------------+------------+------------------+
         |                  |                         |                  |
+--------v--------+ +------v---------+   +-----------v------+ +--------v---------+
| observability-  | | payments-api   |   | Security Demo    | | inventory-svc    |
| demo (Scale Up) | | (Scale Down)   |   |                  | | (Backdrop)       |
|                 | |                |   | Open SG (SSH+RDP)| |                  |
| small-pool      | | small-pool     |   | Public S3 bucket | | default          |
| t3.medium x2    | | t3.medium x2   |   | Unencrypted EBS  | | t3.small x1      |
|                 | | large-pool     |   | Admin IAM role   | | ~40% CPU         |
| HIGH load       | | t3.xlarge x2   |   | Vulnerable EC2s  | +------------------+
| Aiden ADDS      | | LOW load       |   |                  |
| large-pool      | | Aiden REMOVES  |   | GuardDuty +      |
+-----------------+ | large-pool     |   | Security Hub     |
                    +----------------+   +------------------+
```

---

## Part 1: EKS Node Pool Auto-Scaling

Two clusters demonstrate both scale-up and scale-down scenarios simultaneously:

| Cluster | Starting State | Load | Aiden Action |
|---------|---------------|------|--------------|
| `observability-demo` | small-pool only (2x t3.medium) | HIGH (~90%+ CPU) | **Adds** large-pool (3x t3.xlarge) |
| `payments-api` | small-pool + large-pool (2x t3.medium + 2x t3.xlarge) | LOW (~15-20% CPU) | **Removes** large-pool |

### Demo Flow

1. **Setup** -- `first-time-setup.sh` provisions the VPC, all 3 EKS clusters, and deploys workloads
2. **Initialize** -- `initialize-demo.sh` injects high load on `observability-demo` and ensures low load on `payments-api`
3. **Aiden detects overutilization on `observability-demo`** -- Sees nodes at 85-95% CPU with Pending pods
4. **Aiden scales up** -- Creates a new `large-pool` node group (`t3.xlarge` x3) on `observability-demo`
5. **Aiden detects underutilization on `payments-api`** -- Sees nodes at 15-20% CPU with an oversized large-pool
6. **Aiden scales down** -- Removes the `large-pool` node group from `payments-api`, leaving only the small-pool

## Prerequisites

- **AWS CLI** v2 configured with appropriate credentials
- **Terraform** >= 1.5.0
- **kubectl** >= 1.28
- **Helm** >= 3.0
- An AWS account with permissions to create VPC, EKS, EC2, and IAM resources

## Quick Start

### 1. Clone and set up

```bash
git clone <repo-url>
cd observability-demo
```

### 2. Configure AWS credentials

```bash
aws configure
# or export AWS_PROFILE=your-profile
```

### 3. Deploy the infrastructure and workloads

```bash
./scripts/demo/first-time-setup.sh
```

This will:
- Create a VPC with public and private subnets
- Create 3 EKS clusters: `observability-demo`, `payments-api`, and `inventory-svc`
- Install metrics-server on `observability-demo` and `payments-api`
- Deploy workloads on all clusters

Setup takes approximately 20-30 minutes.

### 4. Initialize for a demo run

```bash
./scripts/demo/initialize-demo.sh
```

This stages both EKS demo scenarios automatically:
- Injects high load (8x stress-ng) on `observability-demo`
- Ensures low load on `payments-api` (light workload with oversized large-pool)
- Resets security resources to their vulnerable state

### 5. Monitor utilization (in a separate terminal)

```bash
./scripts/diagnostic/check-utilization.sh
```

### 6. Wait for Aiden

Aiden by StackGen will scan all EKS clusters in the region:
- **observability-demo**: Detects overutilization, creates a `large-pool` node group (3x t3.xlarge)
- **payments-api**: Detects underutilization with oversized large-pool, removes it

### 7. Reset for next demo

```bash
./scripts/demo/initialize-demo.sh
```

Re-run to restore the starting state for both clusters.

### 8. Tear down

```bash
./scripts/demo/teardown.sh
```

This destroys all Kubernetes resources and the Terraform-managed infrastructure.

## Resource Budget

### observability-demo (scale-up cluster)

| Component | CPU Request | Memory Request | Replicas | Total CPU | Total Memory |
|-----------|-------------|----------------|----------|-----------|--------------|
| demo-app (nginx) | 200m | 256Mi | 3 | 600m | 768Mi |
| stress-ng (idle) | 500m | 512Mi | 1 | 500m | 512Mi |
| **Baseline total** | | | | **1100m** | **1280Mi** |
| stress-ng (loaded) | 500m | 512Mi | 8 | 4000m | 4096Mi |
| **Loaded total** | | | | **4600m** | **4864Mi** |

Node capacity (small-pool: 2x `t3.medium`): ~3.5 vCPU allocatable. Loaded utilization: **~131% CPU** (pods go Pending).

### payments-api (scale-down cluster)

| Component | CPU Request | Memory Request | Replicas | Total CPU | Total Memory |
|-----------|-------------|----------------|----------|-----------|--------------|
| payments-app (nginx) | 100m | 64Mi | 2 | 200m | 128Mi |
| payments-worker (stress-ng) | 200m | 64Mi | 1 | 200m | 64Mi |
| **Total** | | | | **400m** | **192Mi** |

Node capacity (small-pool: 2x `t3.medium` + large-pool: 2x `t3.xlarge`): ~19.5 vCPU allocatable. Utilization: **~2% CPU** — large-pool is clearly unnecessary.

---

## Part 2: Security Auto-Remediation

### Overview

The same Terraform configuration deploys intentionally misconfigured AWS resources alongside
GuardDuty and Security Hub. Security Hub's Foundational Security Best Practices standard
automatically generates real findings for these resources. Aiden detects and remediates them.

### Vulnerable Resources

| Resource | Misconfiguration | Security Hub Finding |
|----------|-----------------|---------------------|
| Security Group | SSH (port 22) open to 0.0.0.0/0 | EC2.18 |
| S3 Bucket | Block Public Access disabled | S3.1 |
| EBS Volume | Encryption disabled | EC2.3 |
| IAM Role | AdministratorAccess attached to EC2 service role | IAM.1 |

### Security Demo Flow

1. `terraform apply` provisions GuardDuty, Security Hub, and the misconfigured resources
2. Security Hub runs its first standards check (~5-15 min on initial setup)
3. `./scripts/diagnostic/check-findings.sh` shows active failed findings
4. View findings in the Security Hub console
5. Aiden scans the account, detects findings, and auto-remediates
6. `./scripts/diagnostic/check-findings.sh` shows findings resolved

### Resetting for the Next Demo Run

After Aiden remediates, run:

```bash
./scripts/demo/initialize-demo.sh
```

This runs `terraform apply` to revert Aiden's remediations (which appear as Terraform drift)
and automatically triggers AWS Config rule re-evaluation so findings reappear within 1-3 minutes.

### Check Findings

```bash
./scripts/diagnostic/check-findings.sh
```

Shows active failed Security Hub findings for the demo resources. Can also be run in a loop:

```bash
watch -n 30 ./scripts/diagnostic/check-findings.sh
```

### Security Hub Console

View findings at:
`https://us-west-2.console.aws.amazon.com/securityhub/home?region=us-west-2#/findings`

---

## Part 3: Cloud Asset Inventory Management (Incomplete)

> **Status:** The infrastructure (cross-account IAM roles, policies, scripts) and Aiden skill definition are in place, but the Aiden integration is incomplete and non-functional. This section is not demo-ready.

### Overview

Aiden scans multiple AWS accounts and produces a consolidated cloud asset inventory report. This
demonstrates cross-account visibility without requiring manual login to each account — Aiden
assumes a read-only IAM role in each target account via `sts:AssumeRole`.

### Accounts

| Account | Role | Access Method |
|---------|------|---------------|
| 180217099948 (primary) | aiden-demo home account | Direct credentials |
| 347161580392 (secondary 1) | Target inventory account | Cross-account role assumption |
| 339712749745 (secondary 2) | Target inventory account | Cross-account role assumption |

### Resources Inventoried

- **Compute**: EC2 instances, EKS clusters (with node groups), Lambda functions
- **Networking**: VPCs, Application/Network Load Balancers
- **Storage**: S3 buckets, EBS volumes
- **Database**: RDS instances
- **Identity**: IAM roles and users (counts)

### Cross-Account Setup

Before running the inventory skill, deploy the cross-account IAM role in each secondary account:

```bash
# Account 347161580392
aws sso login --profile <account-347-profile>
./scripts/diagnostic/setup-cross-account.sh --profile <account-347-profile>

# Account 339712749745
aws sso login --profile <account-339-profile>
./scripts/diagnostic/setup-cross-account.sh --profile <account-339-profile>
```

This creates an `aiden-inventory-role` in each secondary account with:
- A trust policy allowing `aiden-demo` from 180217099948 to assume it
- Read-only permissions for EC2, EKS, ELB, S3, RDS, Lambda, IAM, and VPC resources

Then update the aiden-demo IAM policy in the primary account:

```bash
aws iam put-user-policy --user-name aiden-demo \
  --policy-name aiden-demo-policy \
  --policy-document file://iam/aiden-demo-policy.json
```

### Inventory Demo Flow

1. Cross-account role is deployed in 347161580392 and 339712749745 (one-time setup per account)
2. Aiden's IAM policy includes `sts:AssumeRole` permission for both roles (one-time setup)
3. Run the Aiden inventory skill — it scans all 3 accounts and produces a report
4. Report shows all resources across all accounts with per-account breakdowns and totals

### CloudFormation Template

The cross-account role template is at `iam/cross-account-inventory-role.yaml`. It accepts parameters:

| Parameter | Default | Description |
|-----------|---------|-------------|
| TrustedAccountId | 180217099948 | Account where aiden-demo lives |
| TrustedUserName | aiden-demo | IAM user that will assume the role |
| RoleName | aiden-inventory-role | Name of the role to create |

---

## Repository Structure

```
observability-demo/
├── README.md                           # This file
├── terraform/
│   ├── main.tf                         # Provider config
│   ├── variables.tf                    # Configurable parameters
│   ├── outputs.tf                      # Cluster info outputs
│   ├── vpc.tf                          # VPC with public + private subnets
│   ├── eks.tf                          # EKS cluster + small node group
│   ├── dummy-clusters.tf              # payments-api (scale-down) + inventory-svc (backdrop)
│   ├── security.tf                     # GuardDuty + Security Hub + AWS Config
│   ├── vulnerable.tf                   # Intentionally misconfigured resources
│   └── security_outputs.tf             # Security-related outputs
├── kubernetes/
│   ├── namespace.yaml                  # demo namespace
│   ├── metrics-server.yaml             # metrics-server install notes
│   ├── demo-app/
│   │   ├── deployment.yaml             # nginx (3 replicas)
│   │   └── service.yaml                # ClusterIP service
│   ├── stress/
│   │   ├── stress-deployment.yaml      # stress-ng (1 replica, scalable)
│   │   └── resource-hog.yaml           # Batch job for burst load
│   ├── payments-workload/
│   │   ├── namespace.yaml              # payments namespace
│   │   └── deployment.yaml             # Light workload for scale-down demo
│   └── dummy-workload/
│       ├── namespace.yaml              # workload namespace
│       └── stress-light.yaml           # Light CPU load for dummy clusters
├── iam/
│   ├── aiden-demo-policy.json          # IAM policy for aiden-demo user
│   └── cross-account-inventory-role.yaml  # CloudFormation for cross-account role
├── aiden-skills/
│   ├── eks-autoscaling-remediation.md  # EKS node pool auto-scaling skill
│   ├── security-finding-remediation.md # Security Hub remediation skill
│   └── cloud-inventory-management.md   # Multi-account inventory skill
├── scripts/
│   ├── demo/
│   │   ├── first-time-setup.sh         # One-time infrastructure provisioning
│   │   ├── teardown.sh                 # Full teardown
│   │   ├── initialize-demo.sh          # Reset vulnerable state before each demo
│   │   ├── send-security-alert.sh      # Trigger Aiden security remediation webhook
│   │   ├── load-up.sh                  # Scale stress pods up
│   │   └── load-down.sh               # Scale stress pods down
│   └── diagnostic/
│       ├── check-findings.sh           # View Security Hub findings
│       ├── check-utilization.sh        # Live utilization monitor
│       ├── generate-guardduty-findings.sh  # Generate sample GuardDuty findings
│       ├── scan-account.sh             # Helper for cloud inventory skill
│       └── setup-cross-account.sh      # Deploy cross-account inventory role
└── monitoring/
    ├── grafana-dashboard.json          # Node utilization dashboard
    └── prometheus-values.yaml          # Prometheus + Grafana Helm values
```

## Key Design Decisions

- **No Cluster Autoscaler or Karpenter**: Intentionally excluded so Aiden is the sole system making scaling decisions
- **Dual-cluster EKS demo**: `observability-demo` shows scale-up, `payments-api` shows scale-down — Aiden handles both in one scan
- **t3.medium for small pool**: Affordable for a demo, small enough to overutilize quickly with modest load
- **stress-ng for load generation**: Simple, controllable, no custom code -- just scale the replicas
- **Hybrid orchestration**: Infrastructure and workloads are automated; load injection is manual for presentation control

## Customization

Edit `terraform/variables.tf` to change:
- AWS region
- Cluster name
- Instance types and node counts
- VPC CIDR

## Troubleshooting

**metrics-server not reporting data**
- Wait 60-90 seconds after installation for metrics to populate
- Run `kubectl get pods -n kube-system | grep metrics` to verify it is running

**Pods stuck in Pending after load-up**
- This is expected behavior -- it means the nodes are full
- Run `kubectl describe pod <pod-name> -n demo` to see scheduling failures

**Terraform destroy fails**
- Manually delete any node groups Aiden created that are not in Terraform state
- Then re-run `terraform destroy`

## Cost Estimate

Running this demo costs approximately:
- 3x EKS clusters: ~$0.30/hr
- observability-demo (2x t3.medium): ~$0.08/hr
- payments-api (2x t3.medium + 2x t3.xlarge): ~$0.75/hr
- inventory-svc (1x t3.small): ~$0.02/hr
- NAT Gateway: ~$0.045/hr
- GuardDuty: ~$0.04/hr (~$1/day)
- Security Hub: negligible (~$0.001/finding/month)
- 2x t2.micro EC2 (vulnerable instances): free tier eligible
- Cross-account IAM role: free (IAM has no charge)
- **Total: ~$1.24/hr**
- After Aiden removes payments-api large-pool: saves ~$0.67/hr
