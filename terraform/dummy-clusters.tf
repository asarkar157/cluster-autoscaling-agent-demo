# --------------------------------------------------------------------------
# Dummy EKS clusters – lightweight "healthy" clusters for the demo backdrop.
# Each runs a single t3.small node with nominal workloads (~35-40% CPU).
# They share the main VPC to avoid extra NAT gateway costs.
# --------------------------------------------------------------------------

# ----------------------------- payments-api --------------------------------

module "eks_payments" {
  source  = "terraform-aws-modules/eks/aws"
  version = "~> 20.0"

  cluster_name    = "payments-api"
  cluster_version = var.cluster_version

  vpc_id     = module.vpc.vpc_id
  subnet_ids = module.vpc.private_subnets

  cluster_endpoint_public_access = true

  cluster_addons = {
    coredns                         = { most_recent = true }
    kube-proxy                      = { most_recent = true }
    vpc-cni                         = { most_recent = true }
    amazon-cloudwatch-observability = { most_recent = true }
  }

  eks_managed_node_groups = {
    default = {
      instance_types = ["t3.small"]
      capacity_type  = "ON_DEMAND"
      min_size       = 1
      max_size       = 1
      desired_size   = 1

      iam_role_additional_policies = {
        CloudWatchAgentServerPolicy = "arn:aws:iam::aws:policy/CloudWatchAgentServerPolicy"
      }

      labels = {
        role = "worker"
      }
    }
  }

  enable_cluster_creator_admin_permissions = true

  access_entries = {
    aiden = {
      principal_arn = var.aiden_iam_arn
      type          = "STANDARD"

      policy_associations = {
        cluster_admin = {
          policy_arn = "arn:aws:eks::aws:cluster-access-policy/AmazonEKSClusterAdminPolicy"
          access_scope = {
            type = "cluster"
          }
        }
      }
    }
  }

  tags = {
    Name = "payments-api"
  }
}

# ----------------------------- inventory-svc -------------------------------

module "eks_inventory" {
  source  = "terraform-aws-modules/eks/aws"
  version = "~> 20.0"

  cluster_name    = "inventory-svc"
  cluster_version = var.cluster_version

  vpc_id     = module.vpc.vpc_id
  subnet_ids = module.vpc.private_subnets

  cluster_endpoint_public_access = true

  cluster_addons = {
    coredns                         = { most_recent = true }
    kube-proxy                      = { most_recent = true }
    vpc-cni                         = { most_recent = true }
    amazon-cloudwatch-observability = { most_recent = true }
  }

  eks_managed_node_groups = {
    default = {
      instance_types = ["t3.small"]
      capacity_type  = "ON_DEMAND"
      min_size       = 1
      max_size       = 1
      desired_size   = 1

      iam_role_additional_policies = {
        CloudWatchAgentServerPolicy = "arn:aws:iam::aws:policy/CloudWatchAgentServerPolicy"
      }

      labels = {
        role = "worker"
      }
    }
  }

  enable_cluster_creator_admin_permissions = true

  access_entries = {
    aiden = {
      principal_arn = var.aiden_iam_arn
      type          = "STANDARD"

      policy_associations = {
        cluster_admin = {
          policy_arn = "arn:aws:eks::aws:cluster-access-policy/AmazonEKSClusterAdminPolicy"
          access_scope = {
            type = "cluster"
          }
        }
      }
    }
  }

  tags = {
    Name = "inventory-svc"
  }
}
