variable "region" {
  description = "AWS region to deploy into"
  type        = string
  default     = "us-west-2"
}

variable "cluster_name" {
  description = "Name of the EKS cluster"
  type        = string
  default     = "observability-demo"
}

variable "cluster_version" {
  description = "Kubernetes version for the EKS cluster"
  type        = string
  default     = "1.31"
}

variable "small_instance_type" {
  description = "Instance type for the initial small node group"
  type        = string
  default     = "t3.medium"
}

variable "small_desired_size" {
  description = "Desired number of nodes in the small node group"
  type        = number
  default     = 2
}

variable "small_min_size" {
  description = "Minimum number of nodes in the small node group"
  type        = number
  default     = 2
}

variable "small_max_size" {
  description = "Maximum number of nodes in the small node group"
  type        = number
  default     = 3
}

variable "large_instance_type" {
  description = "Instance type for the larger node group (created by Aiden)"
  type        = string
  default     = "t3.xlarge"
}

variable "large_node_count" {
  description = "Desired number of nodes for the larger node group (reference for Aiden)"
  type        = number
  default     = 3
}

variable "aiden_iam_arn" {
  description = "IAM ARN of the Aiden user/role to grant EKS cluster admin access"
  type        = string
  default     = "arn:aws:iam::180217099948:user/aiden-demo"
}

variable "vpc_cidr" {
  description = "CIDR block for the VPC"
  type        = string
  default     = "10.0.0.0/16"
}

variable "tags" {
  description = "Common tags applied to all resources"
  type        = map(string)
  default = {
    Project     = "observability-demo"
    Environment = "demo"
    ManagedBy   = "terraform"
  }
}
