# Skill: Multi-Account Cloud Asset Inventory

## CRITICAL INSTRUCTION — READ THIS FIRST

This skill MUST be executed as a SINGLE atomic operation. You must complete ALL phases — scanning every account — before you produce ANY output to the user. Do not send partial results. Do not send a summary and then promise to continue. Your response to the user must be ONE message that contains the complete multi-account inventory report.

Rules:
1. Do NOT output anything to the user until ALL scanning is done.
2. Do NOT say "proceeding to..." or "I will now..." — just DO it silently.
3. Do NOT ask for confirmation at any point.
4. Do NOT skip any account or resource type — execute EVERY command listed below.
5. Do NOT split your work across multiple messages. ONE response only.
6. Execute every command, collect the results, then present ONE final report.

## Objective

Scan AWS resources across multiple accounts and produce a consolidated cloud asset inventory report. This skill inventories compute, networking, storage, database, serverless, and IAM resources using prescribed CLI commands to ensure deterministic, repeatable results.

## Target Environment

- **AWS Region**: us-west-2
- **Primary Account**: 180217099948 (profile: `Sandbox-RW` — direct credentials)
- **Secondary Account 1**: 347161580392 (profile: `inventory-347` — auto-assumes `aiden-inventory-role`)
- **Secondary Account 2**: 339712749745 (profile: `inventory-339` — auto-assumes `aiden-inventory-role`)

## How Cross-Account Access Works

The AWS CLI profiles `inventory-347` and `inventory-339` are pre-configured with `role_arn` and `source_profile = Sandbox-RW`. When you append `--profile inventory-347` to any AWS CLI command, the CLI automatically assumes the cross-account role behind the scenes. No manual role assumption, environment variables, or scripts are needed.

---

## Phase 1: Primary Account Scan (do NOT output anything yet)

Scan all resources in account 180217099948 using the `Sandbox-RW` profile. Execute EVERY command below in the EXACT order listed. Save all results internally for the final report.

### Step 1.0: Verify Identity

```
aws sts get-caller-identity --profile Sandbox-RW --region us-west-2
```

Confirm the `Account` field is `180217099948`. If not, STOP — credentials are misconfigured.

### Step 1.1: EC2 Instances

```
aws ec2 describe-instances --profile Sandbox-RW --region us-west-2 \
  --query 'Reservations[].Instances[?State.Name!=`terminated`].{ID:InstanceId,Type:InstanceType,State:State.Name,Name:Tags[?Key==`Name`]|[0].Value,AZ:Placement.AvailabilityZone}' \
  --output json
```

Record each instance: ID, type, state, name tag, and availability zone. Count the total.

### Step 1.2: EKS Clusters

First, list all clusters:

```
aws eks list-clusters --profile Sandbox-RW --region us-west-2 --query 'clusters' --output json
```

Then, for EACH cluster returned, run:

```
aws eks describe-cluster --profile Sandbox-RW --name <CLUSTER_NAME> --region us-west-2 \
  --query 'cluster.{Name:name,Version:version,Status:status}' --output json
```

```
aws eks list-nodegroups --profile Sandbox-RW --cluster-name <CLUSTER_NAME> --region us-west-2 \
  --query 'nodegroups' --output json
```

For EACH node group returned:

```
aws eks describe-nodegroup --profile Sandbox-RW --cluster-name <CLUSTER_NAME> --nodegroup-name <NODEGROUP_NAME> --region us-west-2 \
  --query 'nodegroup.{Name:nodegroupName,InstanceTypes:instanceTypes,DesiredSize:scalingConfig.desiredSize,Status:status}' \
  --output json
```

Record each cluster: name, version, status, total node count (sum of all node group desired sizes).

### Step 1.3: Load Balancers

```
aws elbv2 describe-load-balancers --profile Sandbox-RW --region us-west-2 \
  --query 'LoadBalancers[].{Name:LoadBalancerName,Type:Type,Scheme:Scheme,State:State.Code,DNSName:DNSName}' \
  --output json
```

### Step 1.4: S3 Buckets

```
aws s3api list-buckets --profile Sandbox-RW \
  --query 'Buckets[].{Name:Name,Created:CreationDate}' --output json
```

### Step 1.5: RDS Instances

```
aws rds describe-db-instances --profile Sandbox-RW --region us-west-2 \
  --query 'DBInstances[].{ID:DBInstanceIdentifier,Engine:Engine,Class:DBInstanceClass,Status:DBInstanceStatus,MultiAZ:MultiAZ,Storage:AllocatedStorage}' \
  --output json
```

### Step 1.6: Lambda Functions

```
aws lambda list-functions --profile Sandbox-RW --region us-west-2 \
  --query 'Functions[].{Name:FunctionName,Runtime:Runtime,Memory:MemorySize,LastModified:LastModified}' \
  --output json
```

### Step 1.7: VPCs

```
aws ec2 describe-vpcs --profile Sandbox-RW --region us-west-2 \
  --query 'Vpcs[].{ID:VpcId,CIDR:CidrBlock,Name:Tags[?Key==`Name`]|[0].Value,Default:IsDefault}' \
  --output json
```

### Step 1.8: EBS Volumes

```
aws ec2 describe-volumes --profile Sandbox-RW --region us-west-2 \
  --query 'Volumes[].{ID:VolumeId,Size:Size,Type:VolumeType,Encrypted:Encrypted,State:State,AZ:AvailabilityZone}' \
  --output json
```

### Step 1.9: IAM Summary

```
aws iam list-roles --profile Sandbox-RW --query 'length(Roles)' --output text
```

```
aws iam list-users --profile Sandbox-RW --query 'length(Users)' --output text
```

Record the total count of IAM roles and IAM users.

---

## Phase 2: Cross-Account Scan — Account 347161580392 (do NOT output anything yet)

Scan all resources in account 347161580392. Use `--profile inventory-347` on EVERY command. The CLI handles role assumption automatically.

### Step 2.0: Verify Identity

```
aws sts get-caller-identity --profile inventory-347 --region us-west-2
```

Confirm the `Account` field is `347161580392`. If this fails with AccessDenied, record the error for this account and skip to Phase 3.

### Steps 2.1 through 2.9

Execute the EXACT SAME commands from Steps 1.1 through 1.9, but replace `--profile Sandbox-RW` with `--profile inventory-347` in every command.

- Step 2.1: EC2 Instances — `aws ec2 describe-instances --profile inventory-347 --region us-west-2 ...` (same query as 1.1)
- Step 2.2: EKS Clusters — `aws eks list-clusters --profile inventory-347 --region us-west-2 ...` (same as 1.2)
- Step 2.3: Load Balancers — `aws elbv2 describe-load-balancers --profile inventory-347 --region us-west-2 ...` (same as 1.3)
- Step 2.4: S3 Buckets — `aws s3api list-buckets --profile inventory-347 ...` (same as 1.4)
- Step 2.5: RDS Instances — `aws rds describe-db-instances --profile inventory-347 --region us-west-2 ...` (same as 1.5)
- Step 2.6: Lambda Functions — `aws lambda list-functions --profile inventory-347 --region us-west-2 ...` (same as 1.6)
- Step 2.7: VPCs — `aws ec2 describe-vpcs --profile inventory-347 --region us-west-2 ...` (same as 1.7)
- Step 2.8: EBS Volumes — `aws ec2 describe-volumes --profile inventory-347 --region us-west-2 ...` (same as 1.8)
- Step 2.9: IAM Summary — `aws iam list-roles --profile inventory-347 ...` and `aws iam list-users --profile inventory-347 ...` (same as 1.9)

---

## Phase 3: Cross-Account Scan — Account 339712749745 (do NOT output anything yet)

Scan all resources in account 339712749745. Use `--profile inventory-339` on EVERY command.

### Step 3.0: Verify Identity

```
aws sts get-caller-identity --profile inventory-339 --region us-west-2
```

Confirm the `Account` field is `339712749745`. If this fails with AccessDenied, record the error for this account and skip to Phase 4.

### Steps 3.1 through 3.9

Execute the EXACT SAME commands from Steps 1.1 through 1.9, but replace `--profile Sandbox-RW` with `--profile inventory-339` in every command.

- Step 3.1: EC2 Instances — `aws ec2 describe-instances --profile inventory-339 --region us-west-2 ...` (same query as 1.1)
- Step 3.2: EKS Clusters — `aws eks list-clusters --profile inventory-339 --region us-west-2 ...` (same as 1.2)
- Step 3.3: Load Balancers — `aws elbv2 describe-load-balancers --profile inventory-339 --region us-west-2 ...` (same as 1.3)
- Step 3.4: S3 Buckets — `aws s3api list-buckets --profile inventory-339 ...` (same as 1.4)
- Step 3.5: RDS Instances — `aws rds describe-db-instances --profile inventory-339 --region us-west-2 ...` (same as 1.5)
- Step 3.6: Lambda Functions — `aws lambda list-functions --profile inventory-339 --region us-west-2 ...` (same as 1.6)
- Step 3.7: VPCs — `aws ec2 describe-vpcs --profile inventory-339 --region us-west-2 ...` (same as 1.7)
- Step 3.8: EBS Volumes — `aws ec2 describe-volumes --profile inventory-339 --region us-west-2 ...` (same as 1.8)
- Step 3.9: IAM Summary — `aws iam list-roles --profile inventory-339 ...` and `aws iam list-users --profile inventory-339 ...` (same as 1.9)

---

## Phase 4: Final Report (THIS is the ONLY output to the user)

This is the ONLY phase where you output anything to the user. Everything above must have been executed silently. Now produce a SINGLE combined report.

Your response to the user MUST follow this exact format. Fill in the actual data from the commands you executed. If a resource type has zero results, show "None" for that section.

```
============================================================
  Cloud Asset Inventory — Multi-Account Report
  Region: us-west-2
  Generated: <current UTC timestamp>
  Accounts scanned: 3
============================================================

Account: 180217099948 (Primary)
──────────────────────────────────────────────────

  Compute
  ───────
  EC2 Instances: <count>
    <ID>  <Type>  <State>  <Name>  <AZ>
    <ID>  <Type>  <State>  <Name>  <AZ>
    ...

  EKS Clusters: <count>
    <Name>  v<Version>  <total nodes> node(s)  <Status>
    ...

  Lambda Functions: <count>
    <Name>  <Runtime>  <Memory>MB  <LastModified>
    ...
    (or "None" if zero)

  Networking
  ──────────
  VPCs: <count>
    <ID>  <CIDR>  <Name>  default=<true/false>
    ...

  Load Balancers: <count>
    <Name>  <Type>  <Scheme>  <State>
    ...
    (or "None" if zero)

  Storage
  ───────
  S3 Buckets: <count>
    <Name>  created <date>
    ...

  EBS Volumes: <count>
    <ID>  <Size>GiB  <Type>  encrypted=<true/false>  <State>
    ...

  Database
  ────────
  RDS Instances: <count>
    <ID>  <Engine>  <Class>  <Status>  multi-az=<true/false>
    ...
    (or "None" if zero)

  Identity
  ────────
  IAM Roles: <count>
  IAM Users: <count>


Account: 347161580392 (Secondary 1)
──────────────────────────────────────────────────

  (same format as above for all categories)
  Compute / Networking / Storage / Database / Identity


Account: 339712749745 (Secondary 2)
──────────────────────────────────────────────────

  (same format as above for all categories)
  Compute / Networking / Storage / Database / Identity


============================================================
  Cross-Account Summary
============================================================
  Accounts scanned:        3
  Total EC2 instances:     <sum across all 3 accounts>
  Total EKS clusters:      <sum>
  Total Lambda functions:   <sum>
  Total VPCs:              <sum>
  Total Load Balancers:    <sum>
  Total S3 buckets:        <sum>
  Total EBS volumes:       <sum>
  Total RDS instances:     <sum>
  Total IAM roles:         <sum>
  Total IAM users:         <sum>
============================================================
```

---

## Error Handling

### Cross-Account Profile Fails

If any command with `--profile inventory-347` or `--profile inventory-339` returns AccessDenied or a profile error:
1. Report the error in the final report under that account's section
2. Show "ACCESS DENIED — unable to access account <ACCOUNT_ID> via profile <PROFILE>" instead of resource data
3. Still produce the full report for the other accounts that succeeded
4. Continue scanning the remaining accounts — do NOT stop on the first failure

### Empty Results

If a resource type returns zero results (empty JSON array), show:
```
  RDS Instances: 0
    None
```

Do NOT skip the category. Always show all 9 resource types for every account.

---

## Guardrails

- **Read-only operations ONLY**: This skill must NEVER create, modify, or delete any AWS resource.
- **Always use the correct profile**: `Sandbox-RW` for 180217099948, `inventory-347` for 347161580392, `inventory-339` for 339712749745.
- **Always show all categories**: Even if a category has zero resources, include it with "None" or "0".
- **Always scan all three accounts**: If a secondary account fails, still report the other accounts.
- **Use the exact output format**: Do not rearrange sections or add extra commentary.
- **Region scope**: Only scan us-west-2.

## Pre-Requisite: AWS CLI Profile Configuration

Before executing this skill, you MUST ensure the following profiles exist in `~/.aws/config`. If they do not exist, create them now by appending to the file.

### Step 1: Create the cross-account profiles

Run these 6 commands to configure the profiles. These are safe to run even if the profiles already exist — they will simply overwrite with the same values.

```
aws configure set profile.inventory-347.role_arn arn:aws:iam::347161580392:role/aiden-inventory-role
```

```
aws configure set profile.inventory-347.source_profile Sandbox-RW
```

```
aws configure set profile.inventory-347.region us-west-2
```

```
aws configure set profile.inventory-339.role_arn arn:aws:iam::339712749745:role/aiden-inventory-role
```

```
aws configure set profile.inventory-339.source_profile Sandbox-RW
```

```
aws configure set profile.inventory-339.region us-west-2
```

You MUST run all 6 commands above before proceeding. Do NOT skip this step.

**Profile details:**

| Profile | Account | Role ARN | Source |
|---------|---------|----------|--------|
| `Sandbox-RW` | 180217099948 | (direct — aiden-demo access keys) | N/A |
| `inventory-347` | 347161580392 | `arn:aws:iam::347161580392:role/aiden-inventory-role` | `Sandbox-RW` |
| `inventory-339` | 339712749745 | `arn:aws:iam::339712749745:role/aiden-inventory-role` | `Sandbox-RW` |

The `Sandbox-RW` profile has the aiden-demo IAM user access keys. The `inventory-*` profiles use `source_profile = Sandbox-RW` so the AWS CLI automatically calls `sts:AssumeRole` to get temporary credentials for each secondary account on every command.

### Step 3: Verify cross-account access works

```
aws sts get-caller-identity --profile inventory-347 --region us-west-2
```

```
aws sts get-caller-identity --profile inventory-339 --region us-west-2
```

Both should return the respective account IDs. If either fails with AccessDenied, the cross-account IAM role may not be deployed in that account.

---

## AWS APIs Used

### Primary Account (via Sandbox-RW profile)
- `sts:GetCallerIdentity` — Verify identity
- `ec2:DescribeInstances` — EC2 inventory
- `eks:ListClusters`, `eks:DescribeCluster`, `eks:ListNodegroups`, `eks:DescribeNodegroup` — EKS inventory
- `elasticloadbalancing:DescribeLoadBalancers` — Load balancer inventory
- `s3:ListAllMyBuckets` — S3 bucket inventory
- `rds:DescribeDBInstances` — RDS inventory
- `lambda:ListFunctions` — Lambda inventory
- `ec2:DescribeVpcs` — VPC inventory
- `ec2:DescribeVolumes` — EBS inventory
- `iam:ListRoles`, `iam:ListUsers` — IAM summary

### Cross-Account (via inventory-347 and inventory-339 profiles)
- `sts:AssumeRole` — Handled automatically by AWS CLI via profile `role_arn`
- All of the above read-only APIs, executed with automatic temporary credentials per profile
