output "cluster_name" {
  description = "EKS cluster name"
  value       = aws_eks_cluster.primary.name
}

output "cluster_endpoint" {
  description = "EKS cluster API endpoint — mirrors GKE cluster_endpoint"
  value       = aws_eks_cluster.primary.endpoint
  sensitive   = true
}

output "cluster_ca_certificate" {
  description = "Base64-encoded cluster CA certificate — mirrors GKE cluster_ca_certificate"
  value       = aws_eks_cluster.primary.certificate_authority[0].data
  sensitive   = true
}

output "cluster_version" {
  description = "EKS cluster Kubernetes version"
  value       = aws_eks_cluster.primary.version
}

output "node_role_arn" {
  description = "IAM role ARN used by EKS nodes — mirrors GKE node_service_account"
  value       = aws_iam_role.node.arn
}

output "oidc_provider_arn" {
  description = "OIDC provider ARN for IRSA — mirrors GKE workload_identity_pool"
  value       = aws_iam_openid_connect_provider.eks.arn
}

output "oidc_provider_url" {
  description = "OIDC provider URL — use this when building IRSA trust policies"
  value       = aws_iam_openid_connect_provider.eks.url
}

output "cluster_autoscaler_role_arn" {
  description = "IRSA role ARN for Cluster Autoscaler"
  value       = aws_iam_role.cluster_autoscaler.arn
}

output "vpc_id" {
  description = "VPC ID"
  value       = aws_vpc.main.id
}

output "private_subnet_ids" {
  description = "Private subnet IDs where nodes run"
  value       = aws_subnet.private[*].id
}

output "crossplane_namespace" {
  description = "Namespace where Crossplane is installed — same as GKE config"
  value       = kubernetes_namespace.crossplane_system.metadata[0].name
}

output "get_credentials_command" {
  description = "AWS CLI command to configure kubectl — mirrors gcloud get-credentials"
  value       = "aws eks update-kubeconfig --name ${aws_eks_cluster.primary.name} --region ${var.region}"
}
