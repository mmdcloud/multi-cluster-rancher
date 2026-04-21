variable "region" {
  description = "AWS region for the cluster"
  type        = string
  default     = "us-east-1"
}

variable "cluster_name" {
  description = "Name of the EKS cluster"
  type        = string
  default     = "platform-cluster"
}

variable "kubernetes_version" {
  description = "EKS Kubernetes version"
  type        = string
  default     = "1.31"
}

# Networking
variable "vpc_name" {
  description = "Name of the VPC"
  type        = string
  default     = "platform-vpc"
}

variable "vpc_cidr" {
  description = "CIDR block for the VPC — mirrors subnet_cidr"
  type        = string
  default     = "10.0.0.0/16"
}

variable "azs" {
  description = "Availability zones — EKS equivalent of GKE regional cluster (3 AZs = HA)"
  type        = list(string)
  default     = ["us-east-1a", "us-east-1b", "us-east-1c"]
}

variable "public_subnet_cidrs" {
  description = "CIDRs for public subnets (one per AZ) — used for NAT GW and ALBs"
  type        = list(string)
  default     = ["10.0.0.0/24", "10.0.1.0/24", "10.0.2.0/24"]
}

variable "private_subnet_cidrs" {
  description = "CIDRs for private subnets (one per AZ) — node subnets, mirrors GKE private nodes"
  type        = list(string)
  default     = ["10.0.10.0/23", "10.0.12.0/23", "10.0.14.0/23"]
}

# Mirrors master_authorized_networks_config
variable "master_authorized_cidrs" {
  description = "CIDRs allowed to reach the EKS public API endpoint"
  type        = list(string)
  default     = ["0.0.0.0/0"] # Restrict in production
}

# System node pool — mirrors google_container_node_pool "system"
variable "system_instance_type" {
  description = "EC2 instance type for system node pool — ~= e2-standard-2"
  type        = string
  default     = "t3.medium" # 2 vCPU, 4 GB
}

variable "system_node_count" {
  description = "Number of system nodes per AZ"
  type        = number
  default     = 1
}

# App node pool — mirrors google_container_node_pool "apps"
variable "app_instance_type" {
  description = "EC2 instance type for app node pool — ~= e2-standard-4"
  type        = string
  default     = "t3.xlarge" # 4 vCPU, 16 GB
}

variable "app_node_min" {
  description = "Min nodes for app node pool autoscaler"
  type        = number
  default     = 1
}

variable "app_node_max" {
  description = "Max nodes for app node pool autoscaler"
  type        = number
  default     = 5
}

# Crossplane — same variables as GKE config
variable "crossplane_version" {
  description = "Crossplane Helm chart version"
  type        = string
  default     = "1.15.0"
}

variable "crossplane_namespace" {
  description = "Namespace to install Crossplane into"
  type        = string
  default     = "crossplane-system"
}

variable "install_crossplane_provider_aws" {
  description = "Whether to install the Crossplane AWS provider"
  type        = bool
  default     = true # Flipped: AWS is primary here
}

variable "install_crossplane_provider_gcp" {
  description = "Whether to install the Crossplane GCP provider"
  type        = bool
  default     = false
}

variable "install_crossplane_provider_helm" {
  description = "Whether to install the Crossplane Helm provider"
  type        = bool
  default     = false
}

variable "tags" {
  description = "Tags to apply to all resources — mirrors GKE labels"
  type        = map(string)
  default = {
    ManagedBy   = "terraform"
    Environment = "platform"
  }
}
