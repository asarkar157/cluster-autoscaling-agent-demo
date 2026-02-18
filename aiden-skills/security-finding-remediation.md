# Skill: AWS Security Finding Auto-Remediation

## CRITICAL INSTRUCTION — READ THIS FIRST

This skill MUST be executed as a SINGLE atomic operation. You must parse the webhook payload, execute ALL remediations, and verify them before producing ANY output to the user. Do not send partial results. Do not send a summary and then promise to continue. Your response to the user must be ONE message that contains the complete results of everything you did.

Rules:
1. Do NOT output anything to the user until ALL remediations are done.
2. Do NOT say "proceeding to..." or "I will now..." — just DO it silently.
3. Do NOT ask for confirmation at any point.
4. Do NOT stop after reading the findings — you MUST execute the actual AWS API calls to fix every vulnerability.
5. Do NOT split your work across multiple messages. ONE response only.
6. Do NOT query AWS Security Hub or GuardDuty — the webhook payload IS your findings data. Trust it.
7. Execute every remediation API call, collect the results, then present ONE final report.

## Objective

Receive a security alert payload containing findings about vulnerable AWS resources. Remediate every finding by executing the actual AWS API calls against the real resource IDs in the payload. Then present a single combined report showing what was found and what was done.

## Target Environment

- **AWS Region**: us-west-2
- **AWS Account**: The account running the `observability-demo` EKS cluster
- **Resources**: All resources referenced in the webhook payload — these are real AWS resources with real IDs

---

## Phase 1: Parse Findings from Webhook Payload (do NOT output anything yet)

The webhook payload that triggered this skill contains a `findings` array. This IS your source of truth. Do NOT query AWS Security Hub or GuardDuty — the payload already contains all the findings you need to act on.

### Steps

1. **Parse the `findings` array** from the webhook payload. Each finding has these fields:
   - `id` — unique finding identifier
   - `type` — the control ID (e.g., `EC2.18`, `S3.4`, `IAM.1`)
   - `severity` — CRITICAL, HIGH, MEDIUM, or LOW
   - `title` — human-readable title
   - `description` — detailed description of the vulnerability
   - `resource_type` — AWS resource type (e.g., `AWS::EC2::SecurityGroup`)
   - `resource_id` — the **real AWS resource ID** to remediate (e.g., `sg-0f39...`, `i-090e...`)
   - `remediation` — suggested remediation action

2. **Save the findings internally** — note each finding's type, severity, and resource ID. Do NOT output anything to the user yet.

3. **If the payload has zero findings**, skip to Phase 3 and report a clean posture.

4. **If any findings exist**, proceed SILENTLY to Phase 2. Do NOT output a summary yet — you will include everything in the Phase 3 report.

---

## Phase 2: Execute Remediations (execute silently, do NOT output yet)

For each finding from the webhook payload, execute the corresponding AWS API calls below. Do not skip any finding. Do not output anything to the user yet — save the results for the final report in Phase 3.

### How to Process Each Finding

1. **Match the finding's `type` field** to the remediation action below (e.g., `EC2.18`, `S3.4`, `IAM.1`).

2. **Use the finding's `resource_id` field** as the target for the AWS API call. These are real resource IDs — the API calls will work.

3. **Execute the fix immediately**: For each finding, run the corresponding remediation steps below. Do NOT batch them — fix one, then move to the next.

### Compliance Findings to Remediate

| Control ID | Title | Severity | Resource Type |
|-----------|-------|----------|---------------|
| EC2.8 | EC2 instances should use Instance Metadata Service Version 2 (IMDSv2) | HIGH | `AWS::EC2::Instance` |
| EC2.18 | Security groups should only allow unrestricted incoming traffic for authorized ports | HIGH | `AWS::EC2::SecurityGroup` |
| EC2.19 | Security groups should not allow unrestricted access to high-risk ports | CRITICAL | `AWS::EC2::SecurityGroup` |
| S3.1 | S3 general purpose buckets should have block public access settings enabled | MEDIUM | `AWS::S3::Bucket` |
| S3.4 | S3 buckets should have server-side encryption enabled | MEDIUM | `AWS::S3::Bucket` |
| S3.8 | S3 general purpose buckets should block public access | HIGH | `AWS::S3::Bucket` |
| S3.11 | S3 buckets should have versioning enabled | LOW | `AWS::S3::Bucket` |
| EC2.3 | Attached EBS volumes should be encrypted at rest | MEDIUM | `AWS::EC2::Volume` |
| IAM.1 | IAM policies should not allow full "*" administrative privileges | HIGH | `AWS::IAM::Role` |

## Remediation Actions

For EACH finding below, execute the AWS API calls immediately. Fix one, verify it, then move to the next.

### EC2.8 — IMDSv2 Not Enforced

**Problem**: An EC2 instance has Instance Metadata Service v1 enabled (`http_tokens = optional`), allowing SSRF attacks to steal instance credentials.

**Steps**:

1. **Identify the instance**: Use the `resource_id` from the finding (e.g., `i-090e7735ddb600e97`).

2. **Enforce IMDSv2**:
   ```
   aws ec2 modify-instance-metadata-options \
     --instance-id <instance-id> \
     --http-tokens required \
     --http-endpoint enabled \
     --region us-west-2
   ```

3. **Verify**: Call `ec2:DescribeInstances` and confirm `MetadataOptions.HttpTokens` is `required`.

### EC2.18 / EC2.19 — Open Security Group

**Problem**: A security group has an ingress rule allowing traffic from `0.0.0.0/0` on a restricted port (SSH/22, RDP/3389, etc.)

**Steps**:

1. **Identify the security group**: Use the `resource_id` from the finding (e.g., `sg-0f39f362b89f0dc98`).

2. **Find the offending rule**: Call `ec2:DescribeSecurityGroupRules` and find ingress rules where `CidrIpv4` is `0.0.0.0/0` and the port range includes a restricted port (22 for EC2.18, 3389 for EC2.19).

3. **Revoke the offending ingress rule**:
   ```
   aws ec2 revoke-security-group-ingress \
     --group-id <sg-id> \
     --protocol tcp \
     --port 22 \
     --cidr 0.0.0.0/0
   ```

4. **Add a restricted replacement rule** (optional — only if SSH access is needed):
   ```
   aws ec2 authorize-security-group-ingress \
     --group-id <sg-id> \
     --protocol tcp \
     --port 22 \
     --cidr 10.0.0.0/16
   ```
   Use the VPC CIDR (`10.0.0.0/16`) to limit SSH access to within the VPC only.

5. **Verify**: Confirm no remaining `0.0.0.0/0` rules on restricted ports.

### S3.1 / S3.8 — Public S3 Bucket

**Problem**: An S3 bucket has Block Public Access settings disabled, potentially allowing public access to objects.

**Steps**:

1. **Identify the bucket**: Use the `resource_id` from the finding (e.g., `observability-demo-demo-vulnerable-public`).

2. **Enable Block Public Access**:
   ```
   aws s3api put-public-access-block \
     --bucket <bucket-name> \
     --public-access-block-configuration \
       BlockPublicAcls=true,IgnorePublicAcls=true,BlockPublicPolicy=true,RestrictPublicBuckets=true
   ```

3. **Remove any existing public ACLs** (if present):
   ```
   aws s3api put-bucket-acl --bucket <bucket-name> --acl private
   ```

4. **Remove any public bucket policy** (if present):
   ```
   aws s3api delete-bucket-policy --bucket <bucket-name>
   ```

5. **Verify**: Call `s3api:GetPublicAccessBlock` and confirm all four settings are `true`.

### S3.4 — No Server-Side Encryption

**Problem**: An S3 bucket does not have default server-side encryption configured. Data stored in this bucket is not encrypted at rest.

**Steps**:

1. **Identify the bucket**: Use the `resource_id` from the finding (e.g., `observability-demo-demo-vulnerable-noencrypt`).

2. **Enable default SSE-S3 encryption**:
   ```
   aws s3api put-bucket-encryption \
     --bucket <bucket-name> \
     --server-side-encryption-configuration '{
       "Rules": [{"ApplyServerSideEncryptionByDefault": {"SSEAlgorithm": "AES256"}}]
     }'
   ```

3. **Verify**: Call `s3api:GetBucketEncryption` and confirm `SSEAlgorithm` is `AES256`.

### S3.11 — Versioning Not Enabled

**Problem**: An S3 bucket does not have versioning enabled, preventing recovery of accidentally deleted or overwritten objects.

**Steps**:

1. **Identify the bucket**: Use the `resource_id` from the finding (e.g., `observability-demo-demo-vulnerable-noencrypt`).

2. **Enable versioning**:
   ```
   aws s3api put-bucket-versioning \
     --bucket <bucket-name> \
     --versioning-configuration Status=Enabled
   ```

3. **Verify**: Call `s3api:GetBucketVersioning` and confirm `Status` is `Enabled`.

### EC2.3 — Unencrypted EBS Volume

**Problem**: An EBS volume is not encrypted at rest.

**Steps**:

1. **Identify the volume**: Use the `resource_id` from the finding (e.g., `vol-0a82a4b99c2d23346`).

2. **Check if the volume is attached**: Call `ec2:DescribeVolumes` to check the `Attachments` field.

3. **If the volume is unattached** (as in this demo):
   - Create an encrypted snapshot of the volume:
     ```
     aws ec2 create-snapshot --volume-id <vol-id> --description "Encrypted copy for remediation"
     ```
   - Wait for the snapshot to complete.
   - Create a new encrypted volume from the snapshot:
     ```
     aws ec2 create-volume \
       --snapshot-id <snap-id> \
       --availability-zone <same-az> \
       --encrypted \
       --volume-type gp3 \
       --tag-specifications 'ResourceType=volume,Tags=[{Key=Name,Value=demo-remediated-encrypted},{Key=Purpose,Value=security-demo},{Key=ManagedBy,Value=aiden}]'
     ```
   - Delete the original unencrypted volume:
     ```
     aws ec2 delete-volume --volume-id <vol-id>
     ```

4. **If the volume is attached**: Do NOT detach or delete it. Instead, flag it for manual review and create a note in the Security Hub finding.

5. **Verify**: Confirm the new volume has `Encrypted=true`.

### IAM.1 — Overly Permissive IAM Role

**Problem**: An IAM role has the `AdministratorAccess` managed policy (or an inline policy with `"Action": "*"` and `"Resource": "*"`) attached.

**Steps**:

1. **Identify the role**: Use the `resource_id` from the finding (e.g., `demo-vulnerable-overpermissive`).

2. **List attached policies**: Call `iam:ListAttachedRolePolicies` to find the offending policy.

3. **Detach the overly permissive policy**:
   ```
   aws iam detach-role-policy \
     --role-name <role-name> \
     --policy-arn arn:aws:iam::aws:policy/AdministratorAccess
   ```

4. **Attach a least-privilege replacement policy**: Since this role's trust policy allows `ec2.amazonaws.com`, attach a read-only policy as a safe default:
   ```
   aws iam attach-role-policy \
     --role-name <role-name> \
     --policy-arn arn:aws:iam::aws:policy/AmazonEC2ReadOnlyAccess
   ```

5. **Check for inline policies**: Call `iam:ListRolePolicies`. If any inline policy grants `"Action": "*"`, delete it:
   ```
   aws iam delete-role-policy --role-name <role-name> --policy-name <policy-name>
   ```

6. **Verify**: List attached policies and confirm no policy grants full administrative access.

---

## Phase 3: Final Report (THIS is the ONLY output to the user)

This is the ONLY phase where you output anything to the user. Everything above must have been executed silently. Now produce a SINGLE combined report that covers what was found in the payload AND what remediations you executed.

Your response to the user must follow this format:

```
============================================================
  AWS Security Remediation Report — us-west-2
============================================================

--- Findings Received & Remediated ---

#  Control   Severity  Resource                              Action Taken                           Status
─  ────────  ────────  ────────────────────────────────────  ─────────────────────────────────────  ────────
1  EC2.19    CRITICAL  sg-0f39f362b89f0dc98                  Revoked 0.0.0.0/0 RDP (3389) rule     FIXED
2  EC2.18    HIGH      sg-0f39f362b89f0dc98                  Revoked 0.0.0.0/0 SSH (22) rule       FIXED
3  EC2.8     HIGH      i-090e7735ddb600e97                   Enforced IMDSv2 (http_tokens=required) FIXED
4  EC2.8     HIGH      i-061d35d1d8cd3ad3f                   Enforced IMDSv2 (http_tokens=required) FIXED
5  S3.1      HIGH      observability-demo-demo-vulnerable-public  Enabled Block Public Access       FIXED
6  IAM.1     HIGH      demo-vulnerable-overpermissive        Detached AdministratorAccess           FIXED
7  S3.4      MEDIUM    observability-demo-demo-vulnerable-noencrypt  Enabled SSE-S3 encryption      FIXED
8  EC2.3     MEDIUM    vol-0a82a4b99c2d23346                 Replaced with encrypted volume         FIXED
9  S3.11     LOW       observability-demo-demo-vulnerable-noencrypt  Enabled versioning             FIXED (if present)

--- Summary ---

Total findings received:  8
Remediations executed:    8/8
All vulnerabilities resolved.
============================================================
```

Adjust the actual numbers, resource IDs, and finding types based on what was in the webhook payload and what you actually did. Include the real output of each AWS API call (success/failure). If a remediation failed, report the error.

## Verification

After all actions, verify:

- [ ] Security group has no `0.0.0.0/0` ingress rules on restricted ports (SSH 22, RDP 3389)
- [ ] Both EC2 instances have IMDSv2 enforced (`HttpTokens = required`)
- [ ] S3 bucket `demo-vulnerable-public` has all four Block Public Access settings set to `true`
- [ ] S3 bucket `demo-vulnerable-noencrypt` has default encryption enabled (AES256)
- [ ] S3 bucket `demo-vulnerable-noencrypt` has versioning enabled
- [ ] EBS volume is encrypted (or replaced with an encrypted volume)
- [ ] IAM role has no policies granting full administrative access
- [ ] All findings from the webhook payload have been remediated

## Guardrails

- **Only remediate resources listed in the webhook payload** — do not touch other resources in the account.
- **Never delete IAM roles entirely** — only detach overly permissive policies and replace with least-privilege alternatives.
- **Never delete attached EBS volumes** — only remediate unattached volumes. Flag attached volumes for manual review.
- **Never modify security groups used by the EKS cluster** (`eks-cluster-sg-*`, node security groups). Only remediate security groups from the payload.
- **Tag all resources modified or created** with `ManagedBy=aiden` for audit trail.
- **Never terminate EC2 instances** — only modify metadata options, security groups, and IAM attachments.

## AWS APIs Used (Remediation Only — No Security Hub Queries)

- `ec2:ModifyInstanceMetadataOptions` — Enforce IMDSv2 on EC2 instances
- `ec2:DescribeSecurityGroupRules` / `ec2:RevokeSecurityGroupIngress` / `ec2:AuthorizeSecurityGroupIngress` — SG remediation
- `s3api:PutPublicAccessBlock` / `s3api:PutBucketAcl` / `s3api:DeleteBucketPolicy` — S3 public access remediation
- `s3api:PutBucketEncryption` / `s3api:GetBucketEncryption` — S3 encryption remediation
- `s3api:PutBucketVersioning` / `s3api:GetBucketVersioning` — S3 versioning remediation
- `ec2:CreateSnapshot` / `ec2:CreateVolume` / `ec2:DeleteVolume` — EBS remediation
- `iam:ListAttachedRolePolicies` / `iam:DetachRolePolicy` / `iam:AttachRolePolicy` — IAM remediation
- `ec2:DescribeInstances` / `ec2:DescribeVolumes` — Verification after remediation
