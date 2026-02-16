module "eks" {
  source  = "terraform-aws-modules/eks/aws"
  version = "~> 20.0"

  cluster_name    = var.cluster_name
  cluster_version = var.cluster_version

  vpc_id     = module.vpc.vpc_id
  subnet_ids = module.vpc.private_subnets

  cluster_endpoint_public_access = true

  # EKS Add-ons
  cluster_addons = {
    coredns = {
      most_recent = true
    }
    kube-proxy = {
      most_recent = true
    }
    vpc-cni = {
      most_recent = true
    }
    eks-pod-identity-agent = {
      most_recent = true
    }
    amazon-cloudwatch-observability = {
      most_recent = true
    }
  }

  # Initial small node group -- intentionally undersized for the demo
  eks_managed_node_groups = {
    small-pool = {
      name = "small-pool"

      instance_types = [var.small_instance_type]
      capacity_type  = "ON_DEMAND"

      min_size     = var.small_min_size
      max_size     = var.small_max_size
      desired_size = var.small_desired_size

      iam_role_additional_policies = {
        CloudWatchAgentServerPolicy = "arn:aws:iam::aws:policy/CloudWatchAgentServerPolicy"
      }

      labels = {
        pool = "small"
        role = "worker"
      }

      tags = {
        NodePool = "small-pool"
      }
    }
  }

  # Allow access from the caller identity
  enable_cluster_creator_admin_permissions = true

  # Grant Aiden (aiden-demo IAM user) full Kubernetes API access
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
    Name = var.cluster_name
  }
}
