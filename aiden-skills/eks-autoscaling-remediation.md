# Skill: EKS Node Pool Auto-Scaling Remediation

## Objective

Scan ALL EKS clusters in the region, report a utilization summary for each, then automatically right-size any cluster that is overutilized (by creating larger node groups) or underutilized (by removing excess node groups).

## Target Environment

- **AWS Region**: us-west-2
- **Remediation Cluster**: `observability-demo` (the only cluster eligible for remediation actions)
- **Monitoring Scope**: ALL clusters in the region (including `payments-api`, `inventory-svc`, and any others)
- **Initial Node Group**: Name starts with `small-pool` (see discovery note below)
- **Scale-Up Target**: `large-pool` — 3x `t3.xlarge` (4 vCPU, 16 GiB each)
- **VPC Subnets**: Private subnets in the cluster's VPC

---

## Phase 1: Region-Wide Cluster Scan

Before taking any remediation action, you MUST scan every EKS cluster in the region and produce a summary. This gives visibility into the full fleet.

### Steps

1. **List all EKS clusters** in us-west-2:
   ```
   aws eks list-clusters --region us-west-2
   ```

2. **For each cluster**, gather utilization data:
   - Call `eks:DescribeCluster` to get cluster status and version.
   - Call `eks:ListNodegroups` to get node group names, then `eks:DescribeNodegroup` on each to get instance types, node count, and status.
   - Query **CloudWatch Container Insights** for the cluster's `node_cpu_utilization` and `node_memory_utilization` metrics (namespace `ContainerInsights`, dimension `ClusterName`). Use a 5-minute average.

3. **Output a summary table** with the following format:

   ```
   ============================================================
     EKS Cluster Fleet — us-west-2 — Utilization Report
   ============================================================

   Cluster            Nodes  Instance Type  CPU %   Memory %  Status
   ─────────────────  ─────  ─────────────  ──────  ────────  ──────────────
   observability-demo 2      t3.medium      92%     61%       OVERUTILIZED
   payments-api       1      t3.small       38%     29%       HEALTHY
   inventory-svc      1      t3.small       35%     27%       HEALTHY

   Clusters scanned: 3
   Clusters requiring action: 1 (observability-demo)
   ============================================================
   ```

   Classification rules:
   - **OVERUTILIZED**: CPU > 80% OR memory > 75% OR pods in Pending state
   - **UNDERUTILIZED**: CPU < 30% AND no Pending pods AND more than one node group exists
   - **HEALTHY**: Everything else (nominal utilization, no action needed)

4. **If no clusters require action**, state that the fleet is healthy and stop. Do not proceed to Phase 2.

5. **If a cluster requires action**, proceed to Phase 2 for that cluster only.

---

## Phase 2: Remediation (observability-demo only)

Only the `observability-demo` cluster is eligible for remediation. If other clusters show issues, report them in the summary but do NOT take action on them.

## IMPORTANT: Node Group Name Discovery

The EKS managed node groups in this cluster have auto-generated suffixes appended to their names by Terraform. For example, a node group configured as `small-pool` will have an actual AWS name like `small-pool-20260216030314771300000013`.

**You MUST always discover the actual node group name before calling DescribeNodegroup.** Never hardcode or assume the node group name. Follow this procedure:

1. Call `eks:ListNodegroups` for the cluster first:
   ```
   aws eks list-nodegroups --cluster-name observability-demo --region us-west-2
   ```
   This returns the full list of actual node group names.

2. Match by prefix: The initial small node group name starts with `small-pool`. Any node group created by Aiden should start with `large-pool`.

3. Use the full name (including the suffix) in all subsequent API calls (`DescribeNodegroup`, `DeleteNodegroup`, etc.).

**Calling DescribeNodegroup with just `small-pool` will return a ResourceNotFoundException error.** Always use the full name returned by ListNodegroups.

## Detection

### Overutilization Indicators

Scan the AWS account and check for ALL of the following signals. If ANY are present, the cluster is overutilized:

1. **Node CPU utilization above 80%**: Query CloudWatch Container Insights metrics for the `observability-demo` cluster. Check the `node_cpu_utilization` metric. If the average across nodes exceeds 80% sustained over 5 minutes, the cluster is overutilized.

2. **Pods in Pending state**: Query the Kubernetes API or CloudWatch for pods in the `demo` namespace with status `Pending`. Pending pods indicate the scheduler cannot find a node with enough resources. Any Pending pods that have been waiting for more than 2 minutes confirm overutilization.

3. **Node memory utilization above 75%**: Check `node_memory_utilization` in Container Insights. If average memory across nodes exceeds 75%, the cluster is under memory pressure.

4. **Allocatable resources exhausted**: Compare total pod resource requests against total node allocatable capacity. If CPU requests exceed 90% of allocatable CPU, the cluster needs more capacity.

### Underutilization Indicators

Check for ALL of the following signals. ALL must be true to confirm underutilization:

1. **Node CPU utilization below 30%**: Average CPU across ALL nodes in the cluster is below 30% sustained over 10 minutes.

2. **No Pending pods**: Zero pods in `Pending` state across all namespaces.

3. **Multiple node groups active**: Call `eks:ListNodegroups` and check if there is more than one node group. If a node group name starting with `large-pool` exists alongside one starting with `small-pool`, the cluster has been scaled up previously.

4. **Workloads can fit on smaller pool**: Call `eks:DescribeNodegroup` on the `small-pool-*` node group (using its full name from ListNodegroups) to get its instance types and desired size. Calculate allocatable capacity and compare against total pod resource requests.

## Remediation Actions

Before executing any remediation step, output a clear action header:

```
============================================================
  ACTION: Scale Up — observability-demo
  Reason: Node CPU utilization at 92% (threshold: 80%)
  Creating node group: large-pool (3x t3.xlarge)
============================================================
```

Or for scale-down:

```
============================================================
  ACTION: Scale Down — observability-demo
  Reason: Node CPU utilization at 24% (threshold: 30%)
  Removing node group: large-pool-<suffix>
============================================================
```

### Scale Up (Overutilization Detected)

Perform the following steps in order:

1. **Create a new managed node group** attached to the `observability-demo` EKS cluster:
   - Name: `large-pool`
   - Instance type: `t3.xlarge` (4 vCPU, 16 GiB RAM)
   - Desired size: 3
   - Minimum size: 3
   - Maximum size: 5
   - Capacity type: ON_DEMAND
   - Subnets: Same private subnets as the existing cluster (available from the EKS cluster configuration)
   - Node labels: `pool=large`, `role=worker`
   - IAM role: Call `eks:DescribeNodegroup` on the `small-pool-*` node group (using its full name from ListNodegroups) to get its `nodeRole` ARN. Use that same IAM role for the new node group.
   - Tags: `NodePool=large-pool`, `Project=observability-demo`, `ManagedBy=aiden`

2. **Wait for nodes to become Ready**: Monitor the new node group until all 3 nodes report `Ready` status in the Kubernetes API (typically 2-3 minutes).

3. **Verify pod scheduling**: Confirm that previously Pending pods are now scheduled and running on the new nodes.

4. **Do NOT delete the small-pool node group**: Leave the existing `small-pool-*` node group in place. The Kubernetes scheduler will distribute workloads across both pools.

### Scale Down (Underutilization Detected)

When underutilization is detected, you MUST remove the extra `large-pool` node group. Do not just report the finding -- take action and delete it. The cluster will remain healthy because the workloads fit on the smaller node group.

Perform the following steps in order:

1. **Discover the large-pool node group name**: Call `eks:ListNodegroups` and find the node group whose name starts with `large-pool`. Use this full name for all subsequent API calls. If no `large-pool` node group exists, no action is needed.

2. **Confirm workloads fit on small-pool**: Call `eks:DescribeNodegroup` on the `small-pool-*` node group to get its instance types and desired size. A `small-pool` with 2x `t3.medium` nodes provides ~3.5 vCPU and ~7 GiB allocatable. If current total pod CPU requests (from CloudWatch or the Kubernetes API) are below 3.0 vCPU, the workloads will fit.

3. **Delete the large-pool node group immediately**: Call the AWS EKS API to delete the node group:
   ```
   aws eks delete-nodegroup \
     --cluster-name observability-demo \
     --nodegroup-name <full-large-pool-name-from-step-1> \
     --region us-west-2
   ```
   EKS will automatically drain the nodes before terminating them. Pods on those nodes will be rescheduled onto the remaining `small-pool-*` nodes by the Kubernetes scheduler. You do NOT need to manually cordon or drain -- EKS handles this during node group deletion.

4. **Wait for deletion to complete**: The node group status will transition through `DELETING`. Poll with `eks:DescribeNodegroup` or `eks:ListNodegroups` until the `large-pool` entry is gone. This typically takes 2-5 minutes.

5. **Verify cluster health**: After deletion completes, confirm:
   - Only the `small-pool-*` node group remains (call `eks:ListNodegroups`)
   - All pods in the `demo` namespace are `Running` (zero `Pending`)
   - Node CPU utilization is at a healthy level

**IMPORTANT**: Do not skip step 3. When you detect underutilization and a `large-pool` node group exists, you must call `eks:DeleteNodegroup` to remove it. Simply reporting the underutilization without taking action is not sufficient.

## Verification & Post-Action Summary

After any remediation action, verify the following and then output an updated summary:

- [ ] All nodes report `Ready` status
- [ ] All pods in the `demo` namespace are `Running` (zero `Pending`)
- [ ] Node CPU utilization is between 20% and 80%
- [ ] CloudWatch Container Insights shows updated node count

Then output the post-remediation fleet status:

```
============================================================
  Post-Remediation — EKS Fleet Status
============================================================

Cluster            Nodes  Instance Type     CPU %   Status
─────────────────  ─────  ───────────────   ──────  ──────────────
observability-demo 5      t3.medium+xlarge  45%     REMEDIATED ✓
payments-api       1      t3.small          38%     HEALTHY
inventory-svc      1      t3.small          35%     HEALTHY

Action taken: Created large-pool (3x t3.xlarge) on observability-demo
============================================================
```

## Action Summary

| Condition | Action | API Call |
|-----------|--------|----------|
| Overutilization detected, no `large-pool` exists | Create `large-pool` node group | `eks:CreateNodegroup` |
| Underutilization detected, `large-pool` exists | **Delete `large-pool` node group** | `eks:DeleteNodegroup` |
| Underutilization detected, no `large-pool` exists | No action needed | — |
| Overutilization detected, `large-pool` already exists | No action needed (already scaled) | — |

## Guardrails

- **Always take action**: When underutilization is detected and a `large-pool` node group exists, you MUST delete it. Do not just report the finding.
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
