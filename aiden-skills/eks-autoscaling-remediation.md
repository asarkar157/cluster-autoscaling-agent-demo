# Skill: EKS Node Pool Auto-Scaling Remediation

## CRITICAL INSTRUCTION — READ THIS FIRST

You MUST execute real AWS API calls to make changes. Do NOT just describe what you would do. Do NOT just list clusters and stop. You must SCAN, then EXECUTE remediations, then REPORT — all in ONE response.

If a cluster is overutilized, you MUST call `aws eks create-nodegroup` to add capacity.
If a cluster is underutilized with a `large-pool`, you MUST call `aws eks delete-nodegroup` to remove it.

FAILURE MODE TO AVOID: Listing cluster utilization and saying "action required" or "I recommend..." without actually calling the AWS APIs. This is NOT acceptable. You must EXECUTE the fix, not suggest it.

Rules:
1. Do NOT output anything to the user until ALL work is done (scanning AND remediation).
2. Do NOT say "proceeding to..." or "next step..." or "I will now..." — just DO it silently.
3. Do NOT ask for confirmation at any point.
4. Do NOT stop after scanning — if remediation is needed, you MUST EXECUTE it before outputting anything.
5. Do NOT split your work across multiple messages. ONE response only.
6. Execute every API call needed, collect the results, then present ONE final report.
7. NEVER output a scan summary without having executed all required remediations first.

## Objective

Scan ALL EKS clusters in the region, then automatically right-size any cluster that is overutilized (by creating larger node groups) or underutilized (by removing excess node groups). Present ONE combined report at the end.

## Target Environment

- **AWS Region**: us-west-2
- **Remediation Clusters**: `observability-demo` AND `payments-api` (both are eligible for remediation actions)
- **Monitoring Scope**: ALL clusters in the region (including `inventory-svc` and any others)
- **Initial Node Group**: Name starts with `small-pool` (see discovery note below)
- **Scale-Up Target**: `large-pool` — 3x `t3.xlarge` (4 vCPU, 16 GiB each)
- **VPC Subnets**: Private subnets in the cluster's VPC

### Cluster-to-Namespace Mapping

When checking pod status, use the correct namespace for each cluster:
- `observability-demo` — check the `demo` namespace
- `payments-api` — check the `payments` namespace

---

## Step 1: Scan All Clusters

Run these commands silently. Do NOT output results yet.

```bash
aws eks list-clusters --region us-west-2 --query 'clusters' --output json
```

For EACH cluster returned, run:

```bash
aws eks list-nodegroups --cluster-name <CLUSTER> --region us-west-2
aws eks describe-nodegroup --cluster-name <CLUSTER> --nodegroup-name <EACH_NODEGROUP> --region us-west-2
```

Query CloudWatch for CPU and memory using this exact command (no external files needed):

```bash
aws cloudwatch get-metric-statistics \
  --namespace ContainerInsights \
  --metric-name node_cpu_utilization \
  --dimensions Name=ClusterName,Value=<CLUSTER> \
  --start-time $(date -u -d '10 minutes ago' +%Y-%m-%dT%H:%M:%SZ 2>/dev/null || date -u -v-10M +%Y-%m-%dT%H:%M:%SZ) \
  --end-time $(date -u +%Y-%m-%dT%H:%M:%SZ) \
  --period 300 \
  --statistics Average \
  --region us-west-2
```

```bash
aws cloudwatch get-metric-statistics \
  --namespace ContainerInsights \
  --metric-name node_memory_utilization \
  --dimensions Name=ClusterName,Value=<CLUSTER> \
  --start-time $(date -u -d '10 minutes ago' +%Y-%m-%dT%H:%M:%SZ 2>/dev/null || date -u -v-10M +%Y-%m-%dT%H:%M:%SZ) \
  --end-time $(date -u +%Y-%m-%dT%H:%M:%SZ) \
  --period 300 \
  --statistics Average \
  --region us-west-2
```

Replace `<CLUSTER>` with the actual cluster name. These commands query CloudWatch directly — do NOT use external JSON files, query templates, or file-based configurations. Build the API call inline.

### Node Group Name Discovery

Node group names have Terraform-generated suffixes (e.g. `small-pool-20260216030314771300000013`). ALWAYS call `list-nodegroups` first and match by prefix (`small-pool` or `large-pool`). Never use bare names like `small-pool` in API calls.

### Classification

For each cluster, classify:
- **OVERUTILIZED**: CPU > 80% OR memory > 75% OR pods in Pending state
- **UNDERUTILIZED**: CPU < 30% AND no Pending pods AND more than one node group exists
- **HEALTHY**: Everything else

---

## Step 2: Execute Remediations

**YOU MUST EXECUTE THIS STEP. DO NOT SKIP IT. DO NOT JUST REPORT FINDINGS.**

Only `observability-demo` and `payments-api` are eligible for remediation. For other clusters, note status but take no action.

### If observability-demo is OVERUTILIZED — Execute Scale Up

First, get the IAM role and subnets from the existing small-pool node group:

```bash
aws eks describe-nodegroup \
  --cluster-name observability-demo \
  --nodegroup-name <full-small-pool-name-from-list> \
  --region us-west-2 \
  --query 'nodegroup.{role:nodeRole,subnets:subnets}' --output json
```

Then CREATE the new node group — execute this command NOW:

```bash
aws eks create-nodegroup \
  --cluster-name observability-demo \
  --nodegroup-name large-pool \
  --scaling-config minSize=3,maxSize=5,desiredSize=3 \
  --instance-types t3.xlarge \
  --subnets <SUBNET_1> <SUBNET_2> <SUBNET_3> \
  --node-role <NODE_ROLE_ARN_FROM_ABOVE> \
  --capacity-type ON_DEMAND \
  --labels pool=large,role=worker \
  --tags NodePool=large-pool,Project=observability-demo,ManagedBy=aiden \
  --region us-west-2
```

Wait for the node group to become ACTIVE by polling:
```bash
aws eks describe-nodegroup --cluster-name observability-demo --nodegroup-name large-pool --region us-west-2 --query 'nodegroup.status'
```

### If payments-api is UNDERUTILIZED — Execute Scale Down

**NOTE**: `payments-api` is provisioned with BOTH `small-pool` AND `large-pool` by Terraform. The `large-pool` name will have a Terraform suffix (e.g. `large-pool-2026...`). When you see `payments-api` has 2+ node groups and low CPU, it IS underutilized — DELETE the large-pool.

First, find the full large-pool name:
```bash
aws eks list-nodegroups --cluster-name payments-api --region us-west-2
```
Find the entry starting with `large-pool`.

Then DELETE it — execute this command NOW:

```bash
aws eks delete-nodegroup \
  --cluster-name payments-api \
  --nodegroup-name <full-large-pool-name> \
  --region us-west-2
```

EKS automatically drains pods before terminating nodes. You do NOT need to manually cordon or drain.

Wait for deletion by polling until the large-pool is gone:
```bash
aws eks list-nodegroups --cluster-name payments-api --region us-west-2
```

### If observability-demo is UNDERUTILIZED with a large-pool

Find and delete it the same way:
```bash
aws eks delete-nodegroup \
  --cluster-name observability-demo \
  --nodegroup-name <full-large-pool-name> \
  --region us-west-2
```

### If payments-api is OVERUTILIZED

Create a large-pool the same way as the observability-demo scale-up, but with `--cluster-name payments-api`.

---

## Step 3: Final Report

This is the ONLY output to the user. Everything above must have been executed silently.

After any remediation action, verify:
- All nodes report `Ready` status
- All pods in the cluster's workload namespace are `Running` (zero `Pending`) — `demo` for observability-demo, `payments` for payments-api
- Node CPU utilization is at a healthy level

Your response MUST follow this format:

```
============================================================
  EKS Cluster Fleet — us-west-2 — Scan & Remediation Report
============================================================

Cluster            Nodes  Node Groups        Instance Types        CPU %   Memory %  Status
─────────────────  ─────  ─────────────────  ────────────────────  ──────  ────────  ──────────────
observability-demo 2      small-pool         t3.medium             92%     61%       OVERUTILIZED
payments-api       8      small-pool+large   t3.medium+t3.xlarge   18%     12%       UNDERUTILIZED
inventory-svc      1      default            t3.small              35%     27%       HEALTHY

Clusters scanned: 3
Clusters requiring action: 2 (observability-demo, payments-api)

============================================================
  ACTION TAKEN: Scale Up — observability-demo
  Reason: Node CPU utilization at 92% (threshold: 80%)
  Created node group: large-pool (3x t3.xlarge)
  Node group status: ACTIVE
============================================================
  ACTION TAKEN: Scale Down — payments-api
  Reason: Node CPU utilization at 18% with 2 active node groups
  Deleted node group: large-pool (2x t3.xlarge)
  Remaining: small-pool (2x t3.medium)
============================================================

--- Post-Remediation Fleet Status ---

Cluster            Nodes  Node Groups   Instance Types        CPU %   Status
─────────────────  ─────  ───────────   ────────────────────  ──────  ──────────────
observability-demo 5      small+large   t3.medium+t3.xlarge   45%     REMEDIATED ✓ (scaled up)
payments-api       2      small-pool    t3.medium             32%     REMEDIATED ✓ (scaled down)
inventory-svc      1      default       t3.small              35%     HEALTHY

============================================================
```

If no remediation was needed, omit the "ACTION TAKEN" and "Post-Remediation" sections and just show the fleet scan with "All clusters healthy — no action required."

## Action Summary

| Condition | Action | API Call |
|-----------|--------|----------|
| Overutilization detected, no `large-pool` exists | Create `large-pool` node group | `eks:CreateNodegroup` |
| Underutilization detected, `large-pool` exists | **Delete `large-pool` node group** | `eks:DeleteNodegroup` |
| Underutilization detected, no `large-pool` exists | No action needed | — |
| Overutilization detected, `large-pool` already exists | No action needed (already scaled) | — |

## Guardrails

- **Always take action**: When underutilization is detected and a `large-pool` node group exists, you MUST delete it. Do not just report the finding.
- **Always take action**: When overutilization is detected and no `large-pool` exists, you MUST create one. Do not just report the finding.
- **Never delete the `small-pool-*` node group** — it is the baseline and managed by Terraform. Identify it by the `small-pool` prefix from `ListNodegroups`.
- **Never scale the `small-pool-*`** desired count below its minimum (2 nodes).
- **Only create ONE additional node group** at a time — do not create multiple large pools.
- **Do not scale down if any pods are Pending** — this means the smaller pool cannot absorb the workload.
- **Tag all resources created** with `ManagedBy=aiden` so they can be identified and cleaned up.
- **Use ON_DEMAND capacity only** — do not use Spot instances for this demo.
- **EKS handles draining automatically** — when you call `DeleteNodegroup`, EKS drains pods from the nodes before terminating them. You do not need to manually cordon or drain.

## AWS APIs Used

- `eks:ListClusters` — **Call this FIRST** to discover all clusters in the region for the fleet summary
- `eks:ListNodegroups` — Discover actual node group names (they have auto-generated suffixes)
- `eks:DescribeCluster` — Get cluster details, subnet IDs, and security group configuration
- `eks:DescribeNodegroup` — Inspect a node group (always use the full name from ListNodegroups)
- `eks:CreateNodegroup` — Create the large-pool node group
- `eks:DeleteNodegroup` — Remove the large-pool node group (always use the full name from ListNodegroups)
- `cloudwatch:GetMetricData` — Query Container Insights for CPU/memory metrics
- `ec2:DescribeInstances` — Verify node instance status
