# -------------------------------------------------------
# Copy this to terraform.tfvars and fill in your values
# -------------------------------------------------------

region       = "us-east-1"
cluster_name = "platform-cluster"

# Kubernetes version — check aws eks describe-addon-versions for latest
kubernetes_version = "1.31"

# Networking
vpc_name = "platform-vpc"
vpc_cidr = "10.0.0.0/16"
azs      = ["us-east-1a", "us-east-1b", "us-east-1c"]

public_subnet_cidrs  = ["10.0.0.0/24", "10.0.1.0/24", "10.0.2.0/24"]
private_subnet_cidrs = ["10.0.10.0/23", "10.0.12.0/23", "10.0.14.0/23"]

# Restrict this in production — mirrors master_authorized_networks_config
master_authorized_cidrs = ["0.0.0.0/0"]

# Node pools
system_instance_type = "t3.medium"  # ~= e2-standard-2
system_node_count    = 1            # per AZ, so 3 total with default azs

app_instance_type = "t3.xlarge"    # ~= e2-standard-4
app_node_min      = 1
app_node_max      = 5

# Crossplane
crossplane_version   = "1.15.0"
crossplane_namespace = "crossplane-system"

install_crossplane_provider_aws  = true   # Primary on EKS
install_crossplane_provider_gcp  = false  # Set true for multi-cloud
install_crossplane_provider_helm = false  # Set true for platform abstractions

tags = {
  ManagedBy   = "terraform"
  Environment = "platform"
  Team        = "platform-engineering"
}
