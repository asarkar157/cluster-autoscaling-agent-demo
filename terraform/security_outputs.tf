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
