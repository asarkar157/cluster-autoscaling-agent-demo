# Observability & Security Remediation Demo with Aiden

A demo environment that shows Aiden by StackGen automatically:
1. **Detecting and remediating EKS node pool overutilization** -- scaling node groups up/down
2. **Detecting and remediating security misconfigurations** -- fixing findings from AWS Security Hub

## Architecture

```
                           +---------------------+
                           |  Aiden by StackGen   |
                           |  (scans AWS account) |
                           +----------+----------+
                                      |
                      detects issues, auto-remediates
                                      |
              +-----------------------+-----------------------+
              |                                               |
   +----------v----------+                       +------------v-----------+
   |   EKS Cluster Demo  |                       |  Security Demo         |
   |                      |                       |                        |
   |  small-pool          |                       |  Open SG (SSH 0/0)     |
   |  t3.medium x2        |                       |  Public S3 bucket      |
   |                      |                       |  Unencrypted EBS       |
   |  large-pool          |                       |  Admin IAM role        |
   |  t3.xlarge x3        |                       |                        |
   |  (created by Aiden)  |                       |  GuardDuty + Security  |
   +----------------------+                       |  Hub monitoring        |
                                                  +------------------------+
```

---

## Part 1: EKS Node Pool Auto-Scaling

### Demo Flow

1. **Setup** -- Terraform provisions a VPC, EKS cluster, and a small node group (`t3.medium` x2)
2. **Deploy workloads** -- nginx demo app (3 replicas) and a stress-ng pod (1 replica)
3. **Inject load** -- Presenter scales stress-ng to 6+ replicas, overwhelming the small nodes
4. **Aiden detects overutilization** -- Scans the AWS account, sees nodes at 85-95% CPU with Pending pods
5. **Aiden scales up** -- Creates a new `large-pool` node group (`t3.xlarge` x3) attached to the cluster
6. **Remove load** -- Presenter scales stress-ng back down to 1 replica
7. **Aiden detects low utilization** -- Sees nodes at 10-20% CPU
8. **Aiden scales down** -- Reattaches the smaller node pool and deactivates the larger one

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
./scripts/setup.sh
```

This will:
- Create a VPC with public and private subnets
- Create an EKS cluster with a `small-pool` node group (2x `t3.medium`)
- Install metrics-server
- Deploy the demo app (nginx x3) and stress generator (stress-ng x1)

Setup takes approximately 15-20 minutes.

### 4. Monitor utilization (in a separate terminal)

```bash
./scripts/check-utilization.sh
```

### 5. Inject load to overutilize nodes

```bash
./scripts/load-up.sh
```

This scales stress-ng to 6 replicas. With the resource requests, this pushes the 2x `t3.medium` nodes
past their allocatable capacity, causing pods to go Pending and node CPU to spike above 90%.

### 6. Wait for Aiden

Aiden by StackGen will scan the AWS account, detect the overutilization, and create a new `large-pool`
node group with `t3.xlarge` instances. Watch the monitoring terminal to see new nodes join the cluster
and Pending pods get scheduled.

### 7. Reduce load

```bash
./scripts/load-down.sh
```

This scales stress-ng back to 1 replica, dropping utilization across all nodes.

### 8. Wait for Aiden (scale down)

Aiden detects the low utilization and deactivates the larger node group, reattaching the smaller pool.

### 9. Tear down

```bash
./scripts/teardown.sh
```

This destroys all Kubernetes resources and the Terraform-managed infrastructure.

## Resource Budget

| Component | CPU Request | Memory Request | Replicas | Total CPU | Total Memory |
|-----------|-------------|----------------|----------|-----------|--------------|
| demo-app (nginx) | 200m | 256Mi | 3 | 600m | 768Mi |
| stress-ng (idle) | 500m | 512Mi | 1 | 500m | 512Mi |
| **Baseline total** | | | | **1100m** | **1280Mi** |
| stress-ng (loaded) | 500m | 512Mi | 6 | 3000m | 3072Mi |
| **Loaded total** | | | | **3600m** | **3840Mi** |

**Node capacity** (2x `t3.medium`):
- Total: 4 vCPU, 8 GiB
- Allocatable (after system overhead): ~3.5 vCPU, ~7 GiB
- Baseline utilization: ~31% CPU
- Loaded utilization: **~103% CPU** (exceeds allocatable, pods go Pending)

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
3. `./scripts/check-findings.sh` shows active failed findings
4. View findings in the Security Hub console
5. Aiden scans the account, detects findings, and auto-remediates
6. `./scripts/check-findings.sh` shows findings resolved

### Resetting for the Next Demo Run

After Aiden remediates, run:

```bash
./scripts/reset-demo.sh
```

This runs `terraform apply` to revert Aiden's remediations (which appear as Terraform drift)
and automatically triggers AWS Config rule re-evaluation so findings reappear within 1-3 minutes.

### Check Findings

```bash
./scripts/check-findings.sh
```

Shows active failed Security Hub findings for the demo resources. Can also be run in a loop:

```bash
watch -n 30 ./scripts/check-findings.sh
```

### Security Hub Console

View findings at:
`https://us-west-2.console.aws.amazon.com/securityhub/home?region=us-west-2#/findings`

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
│   ├── security.tf                     # GuardDuty + Security Hub
│   ├── vulnerable.tf                   # Intentionally misconfigured resources
│   └── security_outputs.tf             # Security-related outputs
├── kubernetes/
│   ├── namespace.yaml                  # demo namespace
│   ├── metrics-server.yaml             # metrics-server install notes
│   ├── demo-app/
│   │   ├── deployment.yaml             # nginx (3 replicas)
│   │   └── service.yaml                # ClusterIP service
│   └── stress/
│       ├── stress-deployment.yaml      # stress-ng (1 replica, scalable)
│       └── resource-hog.yaml           # Batch job for burst load
├── scripts/
│   ├── setup.sh                        # Full setup automation
│   ├── teardown.sh                     # Full teardown
│   ├── load-up.sh                      # Scale stress pods up
│   ├── load-down.sh                    # Scale stress pods down
│   ├── check-utilization.sh            # Live utilization monitor
│   ├── check-findings.sh              # View Security Hub findings
│   └── reset-demo.sh                  # Reset security demo state
└── monitoring/
    ├── grafana-dashboard.json          # Node utilization dashboard
    └── prometheus-values.yaml          # Prometheus + Grafana Helm values
```

## Key Design Decisions

- **No Cluster Autoscaler or Karpenter**: Intentionally excluded so Aiden is the sole system making scaling decisions
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
- EKS cluster: ~$0.10/hr
- 2x t3.medium: ~$0.08/hr
- NAT Gateway: ~$0.045/hr
- GuardDuty: ~$0.04/hr (~$1/day)
- Security Hub: negligible (~$0.001/finding/month)
- **Total (small pool only): ~$0.27/hr**
- With large pool (3x t3.xlarge): add ~$0.50/hr
