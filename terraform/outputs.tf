output "cluster_name" {
  description = "Name of the EKS cluster"
  value       = module.eks.cluster_name
}

output "cluster_endpoint" {
  description = "Endpoint for the EKS cluster API server"
  value       = module.eks.cluster_endpoint
}

output "cluster_version" {
  description = "Kubernetes version of the EKS cluster"
  value       = module.eks.cluster_version
}

output "cluster_certificate_authority_data" {
  description = "Base64-encoded certificate data for the cluster"
  value       = module.eks.cluster_certificate_authority_data
  sensitive   = true
}

output "cluster_oidc_issuer_url" {
  description = "OIDC provider URL for the EKS cluster"
  value       = module.eks.cluster_oidc_issuer_url
}

output "node_group_small_pool_id" {
  description = "ID of the small-pool managed node group"
  value       = module.eks.eks_managed_node_groups["small-pool"].node_group_id
}

output "node_group_small_pool_arn" {
  description = "ARN of the small-pool managed node group"
  value       = module.eks.eks_managed_node_groups["small-pool"].node_group_arn
}

output "vpc_id" {
  description = "ID of the VPC"
  value       = module.vpc.vpc_id
}

output "private_subnet_ids" {
  description = "IDs of the private subnets"
  value       = module.vpc.private_subnets
}

output "public_subnet_ids" {
  description = "IDs of the public subnets"
  value       = module.vpc.public_subnets
}

output "region" {
  description = "AWS region the cluster is deployed in"
  value       = var.region
}

output "configure_kubectl" {
  description = "Command to configure kubectl for this cluster"
  value       = "aws eks update-kubeconfig --region ${var.region} --name ${module.eks.cluster_name}"
}

# ---------- Dummy clusters ----------

output "dummy_cluster_names" {
  description = "Names of the dummy baseline clusters"
  value       = [module.eks_payments.cluster_name, module.eks_inventory.cluster_name]
}

output "dummy_cluster_endpoints" {
  description = "API server endpoints for the dummy clusters"
  value = {
    (module.eks_payments.cluster_name)  = module.eks_payments.cluster_endpoint
    (module.eks_inventory.cluster_name) = module.eks_inventory.cluster_endpoint
  }
}
