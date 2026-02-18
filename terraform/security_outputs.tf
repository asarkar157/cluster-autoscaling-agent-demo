output "guardduty_detector_id" {
  description = "ID of the GuardDuty detector"
  value       = aws_guardduty_detector.main.id
}

output "securityhub_arn" {
  description = "ARN of the Security Hub account"
  value       = aws_securityhub_account.main.id
}

output "vulnerable_sg_id" {
  description = "ID of the intentionally misconfigured security group (SSH open to 0.0.0.0/0)"
  value       = aws_security_group.vulnerable_ssh.id
}

output "vulnerable_bucket" {
  description = "Name of the intentionally public S3 bucket"
  value       = aws_s3_bucket.vulnerable_public.id
}

output "vulnerable_ebs_id" {
  description = "ID of the intentionally unencrypted EBS volume"
  value       = aws_ebs_volume.vulnerable_unencrypted.id
}

output "vulnerable_iam_role" {
  description = "Name of the intentionally overpermissive IAM role"
  value       = aws_iam_role.vulnerable_admin.name
}

output "vulnerable_instance_1_id" {
  description = "ID of EC2 instance with open SSH SG and no IMDSv2"
  value       = aws_instance.vulnerable_ssh_instance.id
}

output "vulnerable_instance_2_id" {
  description = "ID of EC2 instance with public IP, admin role, and no IMDSv2"
  value       = aws_instance.vulnerable_public_instance.id
}

output "vulnerable_instance_2_public_ip" {
  description = "Public IP of the vulnerable public EC2 instance"
  value       = aws_instance.vulnerable_public_instance.public_ip
}

output "vulnerable_bucket_noencrypt" {
  description = "Name of the S3 bucket with no versioning and no encryption"
  value       = aws_s3_bucket.vulnerable_no_encrypt.id
}
