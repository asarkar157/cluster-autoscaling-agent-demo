#!/usr/bin/env bash
set -euo pipefail

# ---------------------------------------------------------------------------
# scan-account.sh
#
# Scans a single AWS account for cloud resources and outputs structured JSON.
# Handles cross-account role assumption internally when a role ARN is provided.
#
# Usage:
#   ./scripts/diagnostic/scan-account.sh                                          # scan current account
#   ./scripts/diagnostic/scan-account.sh --role-arn arn:aws:iam::XXXX:role/NAME   # assume role first
# ---------------------------------------------------------------------------

REGION="us-west-2"
ROLE_ARN=""

while [[ $# -gt 0 ]]; do
  case $1 in
    --role-arn)
      ROLE_ARN="$2"
      shift 2
      ;;
    --region)
      REGION="$2"
      shift 2
      ;;
    *)
      echo "Unknown option: $1" >&2
      exit 1
      ;;
  esac
done

if [[ -n "$ROLE_ARN" ]]; then
  CREDS=""
  if ! CREDS=$(aws sts assume-role \
    --role-arn "$ROLE_ARN" \
    --role-session-name aiden-inventory-scan \
    --duration-seconds 3600 \
    --region "$REGION" \
    --output json 2>&1); then
    echo "ERROR: Failed to assume role $ROLE_ARN — $CREDS"
    exit 1
  fi

  export AWS_ACCESS_KEY_ID=$(echo "$CREDS" | python3 -c "import sys,json; print(json.load(sys.stdin)['Credentials']['AccessKeyId'])")
  export AWS_SECRET_ACCESS_KEY=$(echo "$CREDS" | python3 -c "import sys,json; print(json.load(sys.stdin)['Credentials']['SecretAccessKey'])")
  export AWS_SESSION_TOKEN=$(echo "$CREDS" | python3 -c "import sys,json; print(json.load(sys.stdin)['Credentials']['SessionToken'])")
fi

ACCOUNT_ID=$(aws sts get-caller-identity --region "$REGION" --query 'Account' --output text)

echo "=== ACCOUNT: $ACCOUNT_ID ==="

echo "--- EC2_INSTANCES ---"
aws ec2 describe-instances --region "$REGION" \
  --query 'Reservations[].Instances[?State.Name!=`terminated`].{ID:InstanceId,Type:InstanceType,State:State.Name,Name:Tags[?Key==`Name`]|[0].Value,AZ:Placement.AvailabilityZone}' \
  --output json 2>/dev/null || echo "[]"

echo "--- EKS_CLUSTERS ---"
CLUSTERS=$(aws eks list-clusters --region "$REGION" --query 'clusters' --output json 2>/dev/null || echo "[]")
echo "$CLUSTERS"

for CLUSTER in $(echo "$CLUSTERS" | python3 -c "import sys,json; [print(c) for c in json.load(sys.stdin)]" 2>/dev/null); do
  echo "--- EKS_CLUSTER_DETAIL: $CLUSTER ---"
  aws eks describe-cluster --name "$CLUSTER" --region "$REGION" \
    --query 'cluster.{Name:name,Version:version,Status:status}' \
    --output json 2>/dev/null || echo "{}"

  echo "--- EKS_NODEGROUPS: $CLUSTER ---"
  NODEGROUPS=$(aws eks list-nodegroups --cluster-name "$CLUSTER" --region "$REGION" \
    --query 'nodegroups' --output json 2>/dev/null || echo "[]")
  echo "$NODEGROUPS"

  for NG in $(echo "$NODEGROUPS" | python3 -c "import sys,json; [print(ng) for ng in json.load(sys.stdin)]" 2>/dev/null); do
    echo "--- EKS_NODEGROUP_DETAIL: $CLUSTER/$NG ---"
    aws eks describe-nodegroup --cluster-name "$CLUSTER" --nodegroup-name "$NG" --region "$REGION" \
      --query 'nodegroup.{Name:nodegroupName,InstanceTypes:instanceTypes,DesiredSize:scalingConfig.desiredSize,Status:status}' \
      --output json 2>/dev/null || echo "{}"
  done
done

echo "--- LOAD_BALANCERS ---"
aws elbv2 describe-load-balancers --region "$REGION" \
  --query 'LoadBalancers[].{Name:LoadBalancerName,Type:Type,Scheme:Scheme,State:State.Code,DNSName:DNSName}' \
  --output json 2>/dev/null || echo "[]"

echo "--- S3_BUCKETS ---"
aws s3api list-buckets \
  --query 'Buckets[].{Name:Name,Created:CreationDate}' \
  --output json 2>/dev/null || echo "[]"

echo "--- RDS_INSTANCES ---"
aws rds describe-db-instances --region "$REGION" \
  --query 'DBInstances[].{ID:DBInstanceIdentifier,Engine:Engine,Class:DBInstanceClass,Status:DBInstanceStatus,MultiAZ:MultiAZ,Storage:AllocatedStorage}' \
  --output json 2>/dev/null || echo "[]"

echo "--- LAMBDA_FUNCTIONS ---"
aws lambda list-functions --region "$REGION" \
  --query 'Functions[].{Name:FunctionName,Runtime:Runtime,Memory:MemorySize,LastModified:LastModified}' \
  --output json 2>/dev/null || echo "[]"

echo "--- VPCS ---"
aws ec2 describe-vpcs --region "$REGION" \
  --query 'Vpcs[].{ID:VpcId,CIDR:CidrBlock,Name:Tags[?Key==`Name`]|[0].Value,Default:IsDefault}' \
  --output json 2>/dev/null || echo "[]"

echo "--- EBS_VOLUMES ---"
aws ec2 describe-volumes --region "$REGION" \
  --query 'Volumes[].{ID:VolumeId,Size:Size,Type:VolumeType,Encrypted:Encrypted,State:State,AZ:AvailabilityZone}' \
  --output json 2>/dev/null || echo "[]"

echo "--- IAM_ROLES_COUNT ---"
aws iam list-roles --query 'length(Roles)' --output text 2>/dev/null || echo "0"

echo "--- IAM_USERS_COUNT ---"
aws iam list-users --query 'length(Users)' --output text 2>/dev/null || echo "0"

echo "=== END ACCOUNT: $ACCOUNT_ID ==="
