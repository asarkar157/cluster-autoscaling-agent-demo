# =============================================================================
# Intentionally misconfigured resources for the security remediation demo.
# Each resource triggers a specific Security Hub finding that Aiden remediates.
# After remediation, `terraform apply` restores the vulnerable state (drift revert).
# =============================================================================

# -----------------------------------------------------------------------------
# a) Open Security Group -- SSH + RDP open to 0.0.0.0/0
#    Security Hub findings: EC2.18 (SSH), EC2.19 (RDP)
# -----------------------------------------------------------------------------
resource "aws_security_group" "vulnerable_ssh" {
  name        = "demo-vulnerable-ssh-open"
  description = "DEMO: SSH and RDP open to world - for Aiden remediation"
  vpc_id      = module.vpc.vpc_id

  ingress {
    description = "SSH from anywhere (intentionally vulnerable)"
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  ingress {
    description = "RDP from anywhere (intentionally vulnerable)"
    from_port   = 3389
    to_port     = 3389
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name    = "demo-vulnerable-ssh-open"
    Purpose = "security-demo"
  }
}

# -----------------------------------------------------------------------------
# b) Public S3 Bucket -- Block Public Access disabled
#    Security Hub finding: S3.1 / S3.8
# -----------------------------------------------------------------------------
resource "aws_s3_bucket" "vulnerable_public" {
  bucket        = "${var.cluster_name}-demo-vulnerable-public"
  force_destroy = true

  tags = {
    Name    = "${var.cluster_name}-demo-vulnerable-public"
    Purpose = "security-demo"
  }
}

resource "aws_s3_bucket_public_access_block" "vulnerable_public" {
  bucket = aws_s3_bucket.vulnerable_public.id

  block_public_acls       = false
  block_public_policy     = false
  ignore_public_acls      = false
  restrict_public_buckets = false
}

# -----------------------------------------------------------------------------
# c) Unencrypted EBS Volume
#    Security Hub finding: EC2.3
# -----------------------------------------------------------------------------
resource "aws_ebs_volume" "vulnerable_unencrypted" {
  availability_zone = data.aws_availability_zones.available.names[0]
  size              = 1
  type              = "gp3"
  encrypted         = false

  tags = {
    Name    = "demo-vulnerable-unencrypted"
    Purpose = "security-demo"
  }
}

# -----------------------------------------------------------------------------
# d) Overly Permissive IAM Role -- AdministratorAccess on an EC2 service role
#    Security Hub finding: IAM.1
# -----------------------------------------------------------------------------
resource "aws_iam_role" "vulnerable_admin" {
  name = "demo-vulnerable-overpermissive"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Action    = "sts:AssumeRole"
      Effect    = "Allow"
      Principal = { Service = "ec2.amazonaws.com" }
    }]
  })

  tags = {
    Name    = "demo-vulnerable-overpermissive"
    Purpose = "security-demo"
  }
}

resource "aws_iam_role_policy_attachment" "vulnerable_admin" {
  role       = aws_iam_role.vulnerable_admin.name
  policy_arn = "arn:aws:iam::aws:policy/AdministratorAccess"
}

# -----------------------------------------------------------------------------
# e) EC2 Instance 1 -- Open SSH SG + no IMDSv2
#    Security Hub finding: EC2.8
# -----------------------------------------------------------------------------
data "aws_ami" "amazon_linux_2" {
  most_recent = true
  owners      = ["amazon"]

  filter {
    name   = "name"
    values = ["amzn2-ami-hvm-*-x86_64-gp2"]
  }

  filter {
    name   = "virtualization-type"
    values = ["hvm"]
  }
}

resource "aws_instance" "vulnerable_ssh_instance" {
  ami                    = data.aws_ami.amazon_linux_2.id
  instance_type          = "t2.micro"
  subnet_id              = module.vpc.private_subnets[0]
  vpc_security_group_ids = [aws_security_group.vulnerable_ssh.id]

  metadata_options {
    http_tokens   = "optional"
    http_endpoint = "enabled"
  }

  tags = {
    Name    = "demo-vulnerable-ssh-instance"
    Purpose = "security-demo"
  }
}

# -----------------------------------------------------------------------------
# f) EC2 Instance 2 -- Public IP + overpermissive IAM role + no IMDSv2
#    Security Hub finding: EC2.8
# -----------------------------------------------------------------------------
resource "aws_iam_instance_profile" "vulnerable_admin" {
  name = "demo-vulnerable-overpermissive-profile"
  role = aws_iam_role.vulnerable_admin.name
}

resource "aws_instance" "vulnerable_public_instance" {
  ami                         = data.aws_ami.amazon_linux_2.id
  instance_type               = "t2.micro"
  subnet_id                   = module.vpc.public_subnets[0]
  vpc_security_group_ids      = [aws_security_group.vulnerable_ssh.id]
  iam_instance_profile        = aws_iam_instance_profile.vulnerable_admin.name
  associate_public_ip_address = true

  metadata_options {
    http_tokens   = "optional"
    http_endpoint = "enabled"
  }

  tags = {
    Name    = "demo-vulnerable-public-instance"
    Purpose = "security-demo"
  }
}

# -----------------------------------------------------------------------------
# g) S3 Bucket 2 -- No versioning + no encryption
#    Security Hub findings: S3.4, S3.11
# -----------------------------------------------------------------------------
resource "aws_s3_bucket" "vulnerable_no_encrypt" {
  bucket        = "${var.cluster_name}-demo-vulnerable-noencrypt"
  force_destroy = true

  tags = {
    Name    = "${var.cluster_name}-demo-vulnerable-noencrypt"
    Purpose = "security-demo"
  }
}

# -----------------------------------------------------------------------------
# Auto Config Re-evaluation
# Runs at the end of every `terraform apply` to trigger immediate re-scan
# of Security Hub Config rules, so findings reappear within 1-3 minutes
# after a demo reset.
# -----------------------------------------------------------------------------
resource "terraform_data" "trigger_config_evaluation" {
  triggers_replace = timestamp()

  provisioner "local-exec" {
    command = <<-EOT
      sleep 5
      RULES=$(aws configservice describe-config-rules \
        --query "ConfigRules[?starts_with(ConfigRuleName,'securityhub-')].ConfigRuleName" \
        --output text --region ${var.region} 2>/dev/null)
      if [ -n "$RULES" ]; then
        aws configservice start-config-rules-evaluation \
          --config-rule-names $RULES --region ${var.region}
        echo "Triggered re-evaluation of Security Hub Config rules"
      else
        echo "No Security Hub Config rules found yet (first run - they will appear after Security Hub initializes)"
      fi
    EOT
  }

  depends_on = [
    aws_security_group.vulnerable_ssh,
    aws_s3_bucket_public_access_block.vulnerable_public,
    aws_ebs_volume.vulnerable_unencrypted,
    aws_iam_role_policy_attachment.vulnerable_admin,
    aws_instance.vulnerable_ssh_instance,
    aws_instance.vulnerable_public_instance,
    aws_s3_bucket.vulnerable_no_encrypt,
    aws_securityhub_standards_subscription.aws_foundational,
  ]
}
