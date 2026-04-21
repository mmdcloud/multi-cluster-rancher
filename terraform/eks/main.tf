# ------------------------------------------------------------------------
# Networking — mirrors GKE VPC + subnet + secondary ranges + Cloud NAT
# ------------------------------------------------------------------------
resource "aws_vpc" "main" {
  cidr_block           = var.vpc_cidr
  enable_dns_hostnames = true
  enable_dns_support   = true

  tags = merge(var.tags, {
    Name                                            = var.vpc_name
    "kubernetes.io/cluster/${var.cluster_name}"     = "shared"
  })
}

# Public subnets — one per AZ (for NAT Gateways and ALBs)
resource "aws_subnet" "public" {
  count             = length(var.azs)
  vpc_id            = aws_vpc.main.id
  cidr_block        = var.public_subnet_cidrs[count.index]
  availability_zone = var.azs[count.index]

  map_public_ip_on_launch = true

  tags = merge(var.tags, {
    Name                                            = "${var.cluster_name}-public-${var.azs[count.index]}"
    "kubernetes.io/cluster/${var.cluster_name}"     = "shared"
    "kubernetes.io/role/elb"                        = "1" # Required for AWS LB Controller
  })
}

# Private subnets — nodes go here, mirrors GKE private nodes
resource "aws_subnet" "private" {
  count             = length(var.azs)
  vpc_id            = aws_vpc.main.id
  cidr_block        = var.private_subnet_cidrs[count.index]
  availability_zone = var.azs[count.index]

  tags = merge(var.tags, {
    Name                                            = "${var.cluster_name}-private-${var.azs[count.index]}"
    "kubernetes.io/cluster/${var.cluster_name}"     = "owned"
    "kubernetes.io/role/internal-elb"               = "1"
  })
}

# Internet Gateway — public egress
resource "aws_internet_gateway" "igw" {
  vpc_id = aws_vpc.main.id
  tags   = merge(var.tags, { Name = "${var.cluster_name}-igw" })
}

# Elastic IPs for NAT Gateways — one per AZ for HA (mirrors Cloud NAT AUTO_ONLY)
resource "aws_eip" "nat" {
  count  = length(var.azs)
  domain = "vpc"
  tags   = merge(var.tags, { Name = "${var.cluster_name}-nat-eip-${var.azs[count.index]}" })
}

# NAT Gateways — one per AZ for HA, same purpose as google_compute_router_nat
resource "aws_nat_gateway" "nat" {
  count         = length(var.azs)
  allocation_id = aws_eip.nat[count.index].id
  subnet_id     = aws_subnet.public[count.index].id

  tags = merge(var.tags, { Name = "${var.cluster_name}-nat-${var.azs[count.index]}" })

  depends_on = [aws_internet_gateway.igw]
}

# Public route table
resource "aws_route_table" "public" {
  vpc_id = aws_vpc.main.id

  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.igw.id
  }

  tags = merge(var.tags, { Name = "${var.cluster_name}-public-rt" })
}

resource "aws_route_table_association" "public" {
  count          = length(var.azs)
  subnet_id      = aws_subnet.public[count.index].id
  route_table_id = aws_route_table.public.id
}

# Private route tables — one per AZ pointing to respective NAT GW
resource "aws_route_table" "private" {
  count  = length(var.azs)
  vpc_id = aws_vpc.main.id

  route {
    cidr_block     = "0.0.0.0/0"
    nat_gateway_id = aws_nat_gateway.nat[count.index].id
  }

  tags = merge(var.tags, { Name = "${var.cluster_name}-private-rt-${var.azs[count.index]}" })
}

resource "aws_route_table_association" "private" {
  count          = length(var.azs)
  subnet_id      = aws_subnet.private[count.index].id
  route_table_id = aws_route_table.private[count.index].id
}

# ------------------------------------------------------------------------
# IAM — mirrors GKE node SA with minimal permissions
# EKS equivalent: cluster role + node instance profile + IRSA
# ------------------------------------------------------------------------

# EKS Cluster IAM Role
resource "aws_iam_role" "cluster" {
  name = "${var.cluster_name}-cluster-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Principal = { Service = "eks.amazonaws.com" }
      Action    = "sts:AssumeRole"
    }]
  })

  tags = var.tags
}

resource "aws_iam_role_policy_attachment" "cluster_policy" {
  role       = aws_iam_role.cluster.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonEKSClusterPolicy"
}

# Node IAM Role — minimal, mirrors GKE node SA permissions
resource "aws_iam_role" "node" {
  name = "${var.cluster_name}-node-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Principal = { Service = "ec2.amazonaws.com" }
      Action    = "sts:AssumeRole"
    }]
  })

  tags = var.tags
}

# Minimal node policies — equivalent to GKE node SA roles
resource "aws_iam_role_policy_attachment" "node_worker_policy" {
  role       = aws_iam_role.node.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonEKSWorkerNodePolicy"
}

resource "aws_iam_role_policy_attachment" "node_cni_policy" {
  role       = aws_iam_role.node.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonEKS_CNI_Policy"
}

# ECR read-only — mirrors roles/artifactregistry.reader
resource "aws_iam_role_policy_attachment" "node_ecr_policy" {
  role       = aws_iam_role.node.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonEC2ContainerRegistryReadOnly"
}

# SSM for ECS Exec equivalent (kubectl exec / node access without bastion)
resource "aws_iam_role_policy_attachment" "node_ssm_policy" {
  role       = aws_iam_role.node.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore"
}

# ------------------------------------------------------------------------
# EKS Cluster — mirrors google_container_cluster.primary
# ------------------------------------------------------------------------
resource "aws_eks_cluster" "primary" {
  name     = var.cluster_name
  role_arn = aws_iam_role.cluster.arn
  version  = var.kubernetes_version

  vpc_config {
    subnet_ids              = aws_subnet.private[*].id
    endpoint_private_access = true
    endpoint_public_access  = true # Mirrors enable_private_endpoint = false
    public_access_cidrs     = var.master_authorized_cidrs # Mirrors master_authorized_networks_config
  }

  # Mirrors logging_config enable_components
  enabled_cluster_log_types = ["api", "audit", "authenticator", "controllerManager", "scheduler"]

  # IRSA (IAM Roles for Service Accounts) — mirrors Workload Identity
  # The OIDC provider is created below and enables pod-level IAM, same as
  # workload_identity_config { workload_pool = ... }
  access_config {
    authentication_mode                         = "API_AND_CONFIG_MAP"
    bootstrap_cluster_creator_admin_permissions = true
  }

  tags = var.tags

  depends_on = [
    aws_iam_role_policy_attachment.cluster_policy,
  ]
}

# OIDC Provider — required for IRSA (Workload Identity equivalent)
data "tls_certificate" "eks" {
  url = aws_eks_cluster.primary.identity[0].oidc[0].issuer
}

resource "aws_iam_openid_connect_provider" "eks" {
  client_id_list  = ["sts.amazonaws.com"]
  thumbprint_list = [data.tls_certificate.eks.certificates[0].sha1_fingerprint]
  url             = aws_eks_cluster.primary.identity[0].oidc[0].issuer

  tags = var.tags
}

# ------------------------------------------------------------------------
# EKS Add-ons — mirrors addons_config block
# ------------------------------------------------------------------------
resource "aws_eks_addon" "vpc_cni" {
  cluster_name  = aws_eks_cluster.primary.name
  addon_name    = "vpc-cni"
  # Mirrors ip_allocation_policy (VPC-native / Alias IP networking)
  tags          = var.tags
}

resource "aws_eks_addon" "coredns" {
  cluster_name = aws_eks_cluster.primary.name
  addon_name   = "coredns"
  tags         = var.tags

  depends_on = [aws_eks_node_group.system]
}

resource "aws_eks_addon" "kube_proxy" {
  cluster_name = aws_eks_cluster.primary.name
  addon_name   = "kube-proxy"
  tags         = var.tags
}

# EBS CSI Driver — mirrors gcs_fuse_csi_driver_config, needed for PVCs
resource "aws_eks_addon" "ebs_csi" {
  cluster_name             = aws_eks_cluster.primary.name
  addon_name               = "aws-ebs-csi-driver"
  service_account_role_arn = aws_iam_role.ebs_csi.arn
  tags                     = var.tags

  depends_on = [aws_iam_openid_connect_provider.eks]
}

# IRSA role for EBS CSI driver
resource "aws_iam_role" "ebs_csi" {
  name = "${var.cluster_name}-ebs-csi-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect = "Allow"
      Principal = {
        Federated = aws_iam_openid_connect_provider.eks.arn
      }
      Action = "sts:AssumeRoleWithWebIdentity"
      Condition = {
        StringEquals = {
          "${replace(aws_iam_openid_connect_provider.eks.url, "https://", "")}:sub" = "system:serviceaccount:kube-system:ebs-csi-controller-sa"
          "${replace(aws_iam_openid_connect_provider.eks.url, "https://", "")}:aud" = "sts.amazonaws.com"
        }
      }
    }]
  })

  tags = var.tags
}

resource "aws_iam_role_policy_attachment" "ebs_csi_policy" {
  role       = aws_iam_role.ebs_csi.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AmazonEBSCSIDriverPolicy"
}

# ------------------------------------------------------------------------
# System Node Group — mirrors google_container_node_pool "system"
# kube-system, crossplane, monitoring — tainted NO_SCHEDULE
# ------------------------------------------------------------------------
resource "aws_eks_node_group" "system" {
  cluster_name    = aws_eks_cluster.primary.name
  node_group_name = "system-pool"
  node_role_arn   = aws_iam_role.node.arn
  subnet_ids      = aws_subnet.private[*].id

  instance_types = [var.system_instance_type]
  capacity_type  = "ON_DEMAND"

  scaling_config {
    desired_size = var.system_node_count * length(var.azs) # One per AZ, mirrors node_count per zone
    min_size     = var.system_node_count * length(var.azs)
    max_size     = var.system_node_count * length(var.azs) + 1
  }

  update_config {
    max_unavailable = 0 # Mirrors max_unavailable = 0
  }

  disk_size = 50 # Mirrors disk_size_gb = 50

  # Mirrors taint { key = "node-role", value = "system", effect = "NO_SCHEDULE" }
  taint {
    key    = "node-role"
    value  = "system"
    effect = "NO_SCHEDULE"
  }

  labels = merge(var.tags, {
    "node-pool" = "system"
  })

  tags = merge(var.tags, {
    Name = "${var.cluster_name}-system-pool"
  })

  depends_on = [
    aws_iam_role_policy_attachment.node_worker_policy,
    aws_iam_role_policy_attachment.node_cni_policy,
    aws_iam_role_policy_attachment.node_ecr_policy,
  ]
}

# ------------------------------------------------------------------------
# App Node Group — mirrors google_container_node_pool "apps"
# Autoscaled, application workloads
# ------------------------------------------------------------------------
resource "aws_eks_node_group" "apps" {
  cluster_name    = aws_eks_cluster.primary.name
  node_group_name = "app-pool"
  node_role_arn   = aws_iam_role.node.arn
  subnet_ids      = aws_subnet.private[*].id

  instance_types = [var.app_instance_type]
  capacity_type  = "ON_DEMAND"

  scaling_config {
    desired_size = var.app_node_min
    min_size     = var.app_node_min
    max_size     = var.app_node_max
  }

  update_config {
    max_unavailable = 0 # Mirrors zero-downtime rolling upgrades
  }

  disk_size = 100 # Mirrors disk_size_gb = 100

  labels = merge(var.tags, {
    "node-pool" = "apps"
  })

  tags = merge(var.tags, {
    Name                                                      = "${var.cluster_name}-app-pool"
    "k8s.io/cluster-autoscaler/${var.cluster_name}"           = "owned" # Required by Cluster Autoscaler
    "k8s.io/cluster-autoscaler/enabled"                       = "true"
  })

  depends_on = [
    aws_iam_role_policy_attachment.node_worker_policy,
    aws_iam_role_policy_attachment.node_cni_policy,
    aws_iam_role_policy_attachment.node_ecr_policy,
  ]
}

# ------------------------------------------------------------------------
# Cluster Autoscaler IRSA — mirrors GKE's built-in autoscaling
# GKE autoscaling is automatic; on EKS you deploy the CA pod with IRSA
# ------------------------------------------------------------------------
resource "aws_iam_role" "cluster_autoscaler" {
  name = "${var.cluster_name}-cluster-autoscaler"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect = "Allow"
      Principal = {
        Federated = aws_iam_openid_connect_provider.eks.arn
      }
      Action = "sts:AssumeRoleWithWebIdentity"
      Condition = {
        StringEquals = {
          "${replace(aws_iam_openid_connect_provider.eks.url, "https://", "")}:sub" = "system:serviceaccount:kube-system:cluster-autoscaler"
          "${replace(aws_iam_openid_connect_provider.eks.url, "https://", "")}:aud" = "sts.amazonaws.com"
        }
      }
    }]
  })

  tags = var.tags
}

resource "aws_iam_role_policy" "cluster_autoscaler" {
  name = "${var.cluster_name}-cluster-autoscaler-policy"
  role = aws_iam_role.cluster_autoscaler.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "autoscaling:DescribeAutoScalingGroups",
          "autoscaling:DescribeAutoScalingInstances",
          "autoscaling:DescribeLaunchConfigurations",
          "autoscaling:DescribeScalingActivities",
          "autoscaling:DescribeTags",
          "ec2:DescribeImages",
          "ec2:DescribeInstanceTypes",
          "ec2:DescribeLaunchTemplateVersions",
          "ec2:GetInstanceTypesFromInstanceRequirements",
          "eks:DescribeNodegroup"
        ]
        Resource = "*"
      },
      {
        Effect = "Allow"
        Action = [
          "autoscaling:SetDesiredCapacity",
          "autoscaling:TerminateInstanceInAutoScalingGroup"
        ]
        Resource = "*"
      }
    ]
  })
}

# ------------------------------------------------------------------------
# Crossplane Namespace — mirrors kubernetes_namespace.crossplane_system
# ------------------------------------------------------------------------
resource "kubernetes_namespace" "crossplane_system" {
  metadata {
    name = var.crossplane_namespace
    labels = merge(var.tags, {
      "app.kubernetes.io/managed-by" = "terraform"
    })
  }

  depends_on = [aws_eks_cluster.primary, aws_eks_node_group.system]
}
