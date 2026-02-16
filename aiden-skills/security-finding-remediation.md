# Skill: AWS Security Finding Auto-Remediation

## Objective

Monitor AWS Security Hub for failed compliance findings in the target account and automatically remediate security misconfigurations across EC2 security groups, S3 buckets, EBS volumes, and IAM roles.

## Target Environment

- **AWS Region**: us-west-2
- **AWS Account**: The account running the `observability-demo` EKS cluster
- **Security Hub**: Enabled with AWS Foundational Security Best Practices v1.0.0 standard
- **GuardDuty**: Enabled with S3 and Kubernetes audit log data sources
- **Resources to monitor**: All resources tagged with `Purpose=security-demo`

## Detection

### How to Find Findings

Query AWS Security Hub for active, failed compliance findings:

1. **List active findings**: Call the Security Hub `GetFindings` API with these filters:
   - `RecordState` = `ACTIVE`
   - `ComplianceStatus` = `FAILED`
   - `WorkflowStatus` = `NEW` or `NOTIFIED`

2. **Identify finding type**: Each finding has a `GeneratorId` that maps to a specific Security Hub control (e.g., `aws-foundational-security-best-practices/v/1.0.0/EC2.18`). Use this to determine the remediation action.

3. **Extract the affected resource**: Each finding contains a `Resources` array with the ARN/ID of the affected AWS resource.

### Findings to Remediate

| Control ID | Title | Severity | Resource Type |
|-----------|-------|----------|---------------|
| EC2.18 | Security groups should only allow unrestricted incoming traffic for authorized ports | HIGH | `AWS::EC2::SecurityGroup` |
| EC2.19 | Security groups should not allow unrestricted access to high-risk ports | CRITICAL | `AWS::EC2::SecurityGroup` |
| S3.1 | S3 general purpose buckets should have block public access settings enabled | MEDIUM | `AWS::S3::Bucket` |
| S3.8 | S3 general purpose buckets should block public access | HIGH | `AWS::S3::Bucket` |
| EC2.3 | Attached EBS volumes should be encrypted at rest | MEDIUM | `AWS::EC2::Volume` |
| IAM.1 | IAM policies should not allow full "*" administrative privileges | HIGH | `AWS::IAM::Role` |

## Remediation Actions

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

## Post-Remediation

After remediating each finding:

1. **Update the Security Hub finding workflow**: Set the workflow status to `RESOLVED`:
   ```
   aws securityhub batch-update-findings \
     --finding-identifiers '[{"Id":"<finding-id>","ProductArn":"<product-arn>"}]' \
     --workflow '{"Status":"RESOLVED"}' \
     --note '{"Text":"Remediated automatically by Aiden","UpdatedBy":"aiden"}'
   ```

2. **Wait for compliance re-evaluation**: The next AWS Config evaluation cycle will verify the resource is now compliant and update the finding status.

## Verification

After all remediations, verify:

- [ ] Security group has no `0.0.0.0/0` ingress rules on restricted ports
- [ ] S3 bucket has all four Block Public Access settings set to `true`
- [ ] EBS volume is encrypted (or replaced with an encrypted volume)
- [ ] IAM role has no policies granting full administrative access
- [ ] All remediated Security Hub findings show `RESOLVED` workflow status

## Guardrails

- **Never delete IAM roles entirely** — only detach overly permissive policies and replace with least-privilege alternatives.
- **Never delete attached EBS volumes** — only remediate unattached volumes. Flag attached volumes for manual review.
- **Never modify security groups used by the EKS cluster** (`eks-cluster-sg-*`, node security groups). Only remediate security groups tagged with `Purpose=security-demo`.
- **Only remediate resources tagged with `Purpose=security-demo`** — do not touch other resources in the account.
- **Tag all resources modified or created** with `ManagedBy=aiden` for audit trail.
- **Always add a note to the Security Hub finding** documenting what was changed and when.

## AWS APIs Used

- `securityhub:GetFindings` — Retrieve active failed findings
- `securityhub:BatchUpdateFindings` — Update finding workflow status after remediation
- `ec2:DescribeSecurityGroupRules` / `ec2:RevokeSecurityGroupIngress` / `ec2:AuthorizeSecurityGroupIngress` — SG remediation
- `s3api:PutPublicAccessBlock` / `s3api:PutBucketAcl` / `s3api:DeleteBucketPolicy` — S3 remediation
- `ec2:CreateSnapshot` / `ec2:CreateVolume` / `ec2:DeleteVolume` — EBS remediation
- `iam:ListAttachedRolePolicies` / `iam:DetachRolePolicy` / `iam:AttachRolePolicy` — IAM remediation
