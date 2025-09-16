terraform {
  required_version = ">= 1.6.0"
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.50"
    }
  }
}

provider "aws" {
  region = var.region
}

data "aws_availability_zones" "available" {}

module "vpc" {
  source  = "terraform-aws-modules/vpc/aws"
  version = "5.5.2"

  name = var.name_prefix
  cidr = "10.4.0.0/16"

  azs             = slice(data.aws_availability_zones.available.names, 0, 2)
  private_subnets = ["10.4.1.0/24", "10.4.2.0/24"]
  public_subnets  = ["10.4.11.0/24", "10.4.12.0/24"]

  # NAT enabled for private nodes' egress
  enable_nat_gateway = true
  single_nat_gateway = true

  # Required tags for EKS LoadBalancer provisioning
  public_subnet_tags = {
    "kubernetes.io/role/elb" = "1"
    "kubernetes.io/cluster/${var.name_prefix}-eks" = "shared"
  }

  private_subnet_tags = {
    "kubernetes.io/role/internal-elb" = "1"
    "kubernetes.io/cluster/${var.name_prefix}-eks" = "shared"
  }

  tags = { Project = var.name_prefix }
}

module "eks" {
  source  = "terraform-aws-modules/eks/aws"
  version = "20.24.1"

  cluster_name    = "${var.name_prefix}-eks"
  cluster_version = "1.30"

  cluster_endpoint_public_access       = true
  cluster_endpoint_public_access_cidrs = var.cluster_public_access_cidrs

  vpc_id     = module.vpc.vpc_id
  # Place nodes into PRIVATE subnets; they use NAT for egress
  subnet_ids = module.vpc.private_subnets

  enable_cluster_creator_admin_permissions = true

  eks_managed_node_groups = {
    default = {
      instance_types = ["t3.small"]
      desired_size   = 1
      min_size       = 1
      max_size       = 2
      disk_size      = 20
      ami_type       = "AL2_x86_64"
      subnet_ids     = module.vpc.private_subnets
    }
  }

  tags = { Project = var.name_prefix }
}

output "eks_cluster_name" {
  value = module.eks.cluster_name
}
