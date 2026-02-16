# Skill: AWS Security Finding Auto-Remediation

## CRITICAL INSTRUCTION — READ THIS FIRST

This skill MUST be executed as a SINGLE atomic operation. You must complete ALL phases — scanning, remediating, investigating, and resolving — before you produce ANY output to the user. Do not send partial results. Do not send a summary and then promise to continue. Your response to the user must be ONE message that contains the complete results of everything you did.

Rules:
1. Do NOT output anything to the user until ALL work is done.
2. Do NOT say "proceeding to..." or "I will now..." — just DO it silently.
3. Do NOT ask for confirmation at any point.
4. Do NOT stop after scanning — you must also execute all fixes.
5. Do NOT split your work across multiple messages. ONE response only.
6. Execute every API call in this skill, collect the results, then present ONE final report.

## Objective

Scan AWS Security Hub for compliance findings and GuardDuty threat detections. Remediate every compliance misconfiguration and investigate/resolve every GuardDuty threat. Then present a single combined report showing what was found and what was done.

## Target Environment

- **AWS Region**: us-west-2
- **AWS Account**: The account running the `observability-demo` EKS cluster
- **Security Hub**: Enabled with AWS Foundational Security Best Practices v1.0.0 standard
- **GuardDuty**: Enabled with S3 and Kubernetes audit log data sources
- **Resources to monitor**: All resources tagged with `Purpose=security-demo`, plus all GuardDuty findings

---

## Phase 1: Scan Findings (do NOT output anything yet)

Gather all findings silently. Do NOT produce any output to the user during this phase.

### Steps

1. **Query compliance findings for demo resources ONLY**. You MUST filter by the `Purpose=security-demo` resource tag to exclude unrelated account-level findings (like Config.1, CloudWatch alarms). Use this exact API call:

   ```
   aws securityhub get-findings --region us-west-2 \
     --filters '{
       "RecordState":[{"Value":"ACTIVE","Comparison":"EQUALS"}],
       "ComplianceStatus":[{"Value":"FAILED","Comparison":"EQUALS"}],
       "ResourceTags":[{"Key":"Purpose","Value":"security-demo","Comparison":"EQUALS"}]
     }'
   ```

   IMPORTANT: You MUST include the `ResourceTags` filter. Without it, you will get dozens of irrelevant account-level findings. The only findings you should see are for these specific resources:
   - Security group `demo-vulnerable-ssh-open` (EC2.18 / EC2.19)
   - S3 bucket `observability-demo-demo-vulnerable-public` (S3.1 / S3.8)
   - EBS volume (EC2.3)
   - IAM role `demo-vulnerable-overpermissive` (IAM.1)

   If you see findings for Config.1, CloudWatch.*, or other account-level controls, your filter is wrong. Re-run with the exact filter above.

2. **Query GuardDuty findings**. Use this exact API call:

   ```
   aws securityhub get-findings --region us-west-2 \
     --filters '{
       "RecordState":[{"Value":"ACTIVE","Comparison":"EQUALS"}],
       "ProductName":[{"Value":"GuardDuty","Comparison":"EQUALS"}]
     }'
   ```

   Do NOT add `ComplianceStatus` or `WorkflowStatus` filters for GuardDuty — they don't use compliance status, and their workflow status varies.

3. **Save the results internally** — note which compliance findings and GuardDuty findings were found. Do NOT output anything to the user yet.

4. **If no findings exist at all** (zero compliance AND zero GuardDuty), skip to Phase 4 and report a clean posture.

5. **If any findings exist**, proceed SILENTLY to Phase 2 and Phase 3. Do NOT output a summary yet — you will include everything in the final Phase 4 report.

---

## Phase 2: Compliance Remediation (execute silently, do NOT output yet)

Execute every remediation step below by calling the actual AWS APIs. Do not skip any step. Do not output anything to the user yet — save the results for the final report in Phase 4.

### How to Find Compliance Findings

Use the SAME query from Phase 1 (with the `Purpose=security-demo` tag filter). For each finding:

1. **Identify finding type**: Each finding has a `GeneratorId` that maps to a specific Security Hub control (e.g., `aws-foundational-security-best-practices/v/1.0.0/EC2.18`). Match the control ID to the remediation action below.

2. **Extract the affected resource**: Each finding contains a `Resources` array with the ARN/ID of the affected AWS resource. Use this to target the remediation API calls.

3. **Execute the fix immediately**: For each finding, run the corresponding remediation steps below. Do NOT batch them — fix one, mark it resolved, then move to the next.

### Compliance Findings to Remediate

| Control ID | Title | Severity | Resource Type |
|-----------|-------|----------|---------------|
| EC2.18 | Security groups should only allow unrestricted incoming traffic for authorized ports | HIGH | `AWS::EC2::SecurityGroup` |
| EC2.19 | Security groups should not allow unrestricted access to high-risk ports | CRITICAL | `AWS::EC2::SecurityGroup` |
| S3.1 | S3 general purpose buckets should have block public access settings enabled | MEDIUM | `AWS::S3::Bucket` |
| S3.8 | S3 general purpose buckets should block public access | HIGH | `AWS::S3::Bucket` |
| EC2.3 | Attached EBS volumes should be encrypted at rest | MEDIUM | `AWS::EC2::Volume` |
| IAM.1 | IAM policies should not allow full "*" administrative privileges | HIGH | `AWS::IAM::Role` |

## Remediation Actions

For EACH finding below, execute the AWS API calls immediately. After fixing each one, call `securityhub:BatchUpdateFindings` to mark it RESOLVED before moving to the next finding.

### EC2.18 / EC2.19 — Open Security Group

**Problem**: A security group has an ingress rule allowing traffic from `0.0.0.0/0` on a restricted port (SSH/22, RDP/3389, etc.)

**Steps**:

1. **Identify the security group**: Extract the security group ID from the finding's `Resources[0].Id` field.

2. **Find the offending rule**: Call `ec2:DescribeSecurityGroupRules` and find ingress rules where `CidrIpv4` is `0.0.0.0/0` and the port range includes a restricted port (22, 3389).

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

1. **Identify the bucket**: Extract the bucket name from the finding's `Resources[0].Id` field.

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

### EC2.3 — Unencrypted EBS Volume

**Problem**: An EBS volume is not encrypted at rest.

**Steps**:

1. **Identify the volume**: Extract the volume ID from the finding's `Resources[0].Id` field.

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

1. **Identify the role**: Extract the role name from the finding's `Resources[0].Id` field (the role ARN).

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

## Phase 3: GuardDuty Threat Response (execute silently, do NOT output yet)

After completing Phase 2, handle all GuardDuty findings. For each finding, call `securityhub:BatchUpdateFindings` to resolve it with a detailed investigation note. Do NOT output anything to the user yet — save all results for Phase 4.

GuardDuty findings represent active threats, not misconfigurations. They require investigation, documentation, and resolution.

### How to Find GuardDuty Findings

Use the SAME GuardDuty query from Phase 1. For reference:

```
aws securityhub get-findings --region us-west-2 \
  --filters '{
    "RecordState":[{"Value":"ACTIVE","Comparison":"EQUALS"}],
    "ProductName":[{"Value":"GuardDuty","Comparison":"EQUALS"}]
  }'
```

For each finding returned, match its `Title` or `Types` field to the categories below and execute the corresponding response. Do NOT skip any finding.

### Threat Responses by Category

#### CryptoCurrency:EC2/BitcoinTool.B!DNS — Cryptocurrency Mining

**Threat**: An EC2 instance is querying DNS domains associated with Bitcoin or cryptocurrency mining.

**Response**:
1. Identify the affected instance from the finding's `Resources[0].Id`.
2. Document the instance ID, VPC, and security groups.
3. Check if the instance belongs to the demo environment (check tags).
4. Archive the finding and add a note documenting the investigation:
   ```
   aws securityhub batch-update-findings \
     --finding-identifiers '[{"Id":"<finding-id>","ProductArn":"<product-arn>"}]' \
     --workflow '{"Status":"RESOLVED"}' \
     --note '{"Text":"Investigated by Aiden. Instance identified and flagged. Cryptocurrency mining DNS activity detected — recommend isolating the instance and scanning for malware.","UpdatedBy":"aiden"}'
   ```

#### UnauthorizedAccess:EC2/MaliciousIPCaller.Custom — Malicious IP Communication

**Threat**: An EC2 instance is communicating with a known malicious IP address.

**Response**:
1. Identify the affected instance and the malicious IP from the finding details.
2. Document the communication direction (inbound/outbound), port, and protocol.
3. Archive and document:
   ```
   aws securityhub batch-update-findings \
     --finding-identifiers '[{"Id":"<finding-id>","ProductArn":"<product-arn>"}]' \
     --workflow '{"Status":"RESOLVED"}' \
     --note '{"Text":"Investigated by Aiden. Malicious IP communication detected — recommend reviewing instance network ACLs and adding the IP to a deny list.","UpdatedBy":"aiden"}'
   ```

#### Recon:EC2/PortProbeUnprotectedPort — Port Scan Detected

**Threat**: An unprotected port on an EC2 instance is being probed by a known malicious host.

**Response**:
1. Identify the instance, port, and source IP from the finding.
2. Check if the probed port should be open. If the port is SSH (22) on a demo security group, this correlates with the EC2.18/EC2.19 compliance finding — note the correlation.
3. Archive and document:
   ```
   aws securityhub batch-update-findings \
     --finding-identifiers '[{"Id":"<finding-id>","ProductArn":"<product-arn>"}]' \
     --workflow '{"Status":"RESOLVED"}' \
     --note '{"Text":"Investigated by Aiden. Port probe detected on exposed port. Correlates with open security group finding — SG remediation addresses root cause.","UpdatedBy":"aiden"}'
   ```

#### Trojan:EC2/DNSDataExfiltration — DNS Data Exfiltration

**Threat**: An EC2 instance is exfiltrating data through DNS queries.

**Response**:
1. Identify the instance and DNS domain patterns.
2. This is a high-severity threat. Document urgently:
   ```
   aws securityhub batch-update-findings \
     --finding-identifiers '[{"Id":"<finding-id>","ProductArn":"<product-arn>"}]' \
     --workflow '{"Status":"RESOLVED"}' \
     --note '{"Text":"Investigated by Aiden. DNS data exfiltration pattern detected — HIGH PRIORITY. Recommend immediate instance isolation, forensic snapshot, and incident response.","UpdatedBy":"aiden"}'
   ```

#### Policy:Kubernetes/ExposedDashboard — Exposed Kubernetes Dashboard

**Threat**: The Kubernetes dashboard is exposed to the internet on an EKS cluster.

**Response**:
1. Identify the affected EKS cluster from the finding.
2. Archive and document:
   ```
   aws securityhub batch-update-findings \
     --finding-identifiers '[{"Id":"<finding-id>","ProductArn":"<product-arn>"}]' \
     --workflow '{"Status":"RESOLVED"}' \
     --note '{"Text":"Investigated by Aiden. Exposed Kubernetes dashboard detected — recommend removing public access and enforcing RBAC.","UpdatedBy":"aiden"}'
   ```

#### PrivilegeEscalation:Kubernetes/PrivilegedContainer — Privileged Container

**Threat**: A privileged container was launched on an EKS cluster, which could allow container escape.

**Response**:
1. Identify the cluster, namespace, and pod from the finding.
2. Archive and document:
   ```
   aws securityhub batch-update-findings \
     --finding-identifiers '[{"Id":"<finding-id>","ProductArn":"<product-arn>"}]' \
     --workflow '{"Status":"RESOLVED"}' \
     --note '{"Text":"Investigated by Aiden. Privileged container detected — recommend enforcing PodSecurityStandards to prevent privileged containers.","UpdatedBy":"aiden"}'
   ```

#### Discovery:Kubernetes/SuccessfulAnonymousAccess — Anonymous Kubernetes Access

**Threat**: An API call was successfully made with anonymous credentials to the Kubernetes API.

**Response**:
1. Identify the cluster and the API call that was made.
2. Archive and document:
   ```
   aws securityhub batch-update-findings \
     --finding-identifiers '[{"Id":"<finding-id>","ProductArn":"<product-arn>"}]' \
     --workflow '{"Status":"RESOLVED"}' \
     --note '{"Text":"Investigated by Aiden. Anonymous access to Kubernetes API detected — recommend disabling anonymous auth and reviewing RBAC bindings.","UpdatedBy":"aiden"}'
   ```

#### Impact:Kubernetes/MaliciousIPCaller — Malicious IP Accessing Kubernetes

**Threat**: A Kubernetes API was called from a known malicious IP address.

**Response**:
1. Identify the cluster, source IP, and API action.
2. Archive and document:
   ```
   aws securityhub batch-update-findings \
     --finding-identifiers '[{"Id":"<finding-id>","ProductArn":"<product-arn>"}]' \
     --workflow '{"Status":"RESOLVED"}' \
     --note '{"Text":"Investigated by Aiden. Kubernetes API access from malicious IP — recommend blocking the IP in security groups and reviewing cluster access logs.","UpdatedBy":"aiden"}'
   ```

### GuardDuty Response Pattern

For ALL GuardDuty findings, follow this pattern:

1. **Investigate**: Extract instance/cluster/resource details from the finding
2. **Correlate**: Check if the threat relates to any compliance finding (e.g., open SG leads to port probing)
3. **Document**: Add a detailed note with the investigation findings and recommended next steps
4. **Resolve**: Set workflow status to `RESOLVED` via `securityhub:BatchUpdateFindings`

---

## Phase 4: Final Report (THIS is the ONLY output to the user)

This is the ONLY phase where you output anything to the user. Everything above must have been executed silently. Now produce a SINGLE combined report that covers what was found AND what was done.

Your response to the user must follow this format:

```
============================================================
  AWS Security Remediation Report — us-west-2
============================================================

--- Compliance Findings Found & Remediated ---

#  Control   Severity  Resource                         Action Taken
─  ────────  ────────  ───────────────────────────────  ─────────────────────────────
1  EC2.19    CRITICAL  sg-018fc83a379deac4b             Revoked 0.0.0.0/0 SSH rule
2  S3.8      HIGH      demo-vulnerable-public           Enabled Block Public Access
3  EC2.3     MEDIUM    vol-0a82a4b99c2d23346            Replaced with encrypted volume
4  IAM.1     HIGH      demo-vulnerable-overpermissive   Detached AdministratorAccess

--- GuardDuty Threats Found & Investigated ---

#  Type                                    Severity  Action Taken
─  ──────────────────────────────────────  ────────  ──────────────────────────────────
5  CryptoCurrency:EC2/BitcoinTool.B!DNS    HIGH      Investigated, documented, resolved
6  Recon:EC2/PortProbeUnprotectedPort      LOW       Correlated with SG fix, resolved
7  Trojan:EC2/DNSDataExfiltration          HIGH      Investigated, documented, resolved
8  PrivilegeEscalation:Kubernetes/Priv..   MEDIUM    Investigated, documented, resolved
9  Policy:Kubernetes/ExposedDashboard      MEDIUM    Investigated, documented, resolved

--- Summary ---

Compliance findings remediated: 4/4
Threat findings investigated:   5/5
All findings marked RESOLVED in Security Hub.
============================================================
```

Adjust the actual numbers, resource IDs, and finding types based on what you found and did. If a category had zero findings, say "None found" for that section.

## Verification

After all actions, verify:

- [ ] Security group has no `0.0.0.0/0` ingress rules on restricted ports
- [ ] S3 bucket has all four Block Public Access settings set to `true`
- [ ] EBS volume is encrypted (or replaced with an encrypted volume)
- [ ] IAM role has no policies granting full administrative access
- [ ] All compliance findings show `RESOLVED` workflow status
- [ ] All GuardDuty findings show `RESOLVED` workflow status with investigation notes

## Guardrails

- **Never delete IAM roles entirely** — only detach overly permissive policies and replace with least-privilege alternatives.
- **Never delete attached EBS volumes** — only remediate unattached volumes. Flag attached volumes for manual review.
- **Never modify security groups used by the EKS cluster** (`eks-cluster-sg-*`, node security groups). Only remediate security groups tagged with `Purpose=security-demo`.
- **Only remediate compliance findings for resources tagged with `Purpose=security-demo`** — do not touch other resources in the account.
- **GuardDuty findings do not require the `Purpose=security-demo` tag** — investigate all GuardDuty findings regardless of tags.
- **Tag all resources modified or created** with `ManagedBy=aiden` for audit trail.
- **Always add a note to every finding** documenting what was investigated, changed, and recommended.
- **Never terminate EC2 instances** in response to GuardDuty findings — document and recommend isolation instead.

## AWS APIs Used

- `securityhub:GetFindings` — Retrieve active failed findings (compliance and GuardDuty)
- `securityhub:BatchUpdateFindings` — Update finding workflow status after remediation
- `guardduty:ListDetectors` / `guardduty:ListFindings` / `guardduty:GetFindings` — Direct GuardDuty queries (optional, since findings also appear in Security Hub)
- `ec2:DescribeSecurityGroupRules` / `ec2:RevokeSecurityGroupIngress` / `ec2:AuthorizeSecurityGroupIngress` — SG remediation
- `s3api:PutPublicAccessBlock` / `s3api:PutBucketAcl` / `s3api:DeleteBucketPolicy` — S3 remediation
- `ec2:CreateSnapshot` / `ec2:CreateVolume` / `ec2:DeleteVolume` — EBS remediation
- `iam:ListAttachedRolePolicies` / `iam:DetachRolePolicy` / `iam:AttachRolePolicy` — IAM remediation
