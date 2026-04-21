terraform {
  required_version = ">= 1.6.0"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
    helm = {
      source  = "hashicorp/helm"
      version = "~> 2.12"
    }
    kubernetes = {
      source  = "hashicorp/kubernetes"
      version = "~> 2.25"
    }
    tls = {
      source  = "hashicorp/tls"
      version = "~> 4.0"
    }
    time = {
      source  = "hashicorp/time"
      version = "~> 0.10"
    }
  }
}

provider "aws" {
  region = var.region

  default_tags {
    tags = var.tags
  }
}

# -----------------------------------------------------------------------
# Kubernetes and Helm providers use EKS cluster credentials via data source
# Mirrors the GKE pattern: provider reads cluster endpoint + CA + token
# -----------------------------------------------------------------------
data "aws_eks_cluster_auth" "primary" {
  name = aws_eks_cluster.primary.name
}

provider "kubernetes" {
  host                   = aws_eks_cluster.primary.endpoint
  cluster_ca_certificate = base64decode(aws_eks_cluster.primary.certificate_authority[0].data)
  token                  = data.aws_eks_cluster_auth.primary.token
}

provider "helm" {
  kubernetes {
    host                   = aws_eks_cluster.primary.endpoint
    cluster_ca_certificate = base64decode(aws_eks_cluster.primary.certificate_authority[0].data)
    token                  = data.aws_eks_cluster_auth.primary.token
  }
}
