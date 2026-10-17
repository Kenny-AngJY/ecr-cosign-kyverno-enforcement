variable "region" {
  type    = string
  default = "ap-southeast-1"
}

variable "create_vpc" {
  description = "Choose whether to create a new VPC."
  type        = bool
  default     = true
}

variable "vpc_id" {
  description = "If create_vpc is false, define your own vpc_id."
  type        = string
  default     = ""

  validation {
    condition     = var.create_vpc || var.vpc_id != ""
    error_message = "vpc_id must be set when create_vpc is false."
  }
}

variable "list_of_subnet_ids" {
  description = "If create_vpc is false, define your own subnet_ids."
  type        = list(string)
  default     = []

  validation {
    condition     = var.create_vpc || length(var.list_of_subnet_ids) > 0
    error_message = "list_of_subnet_ids must be set when create_vpc is false."
  }
}

variable "use_eks_pod_identity_agent" {
  description = "Use EKS pod identity instead of IAM Roles for Service Account (IRSA)."
  type        = bool
  default     = true

  validation {
    condition     = !(var.use_eks_pod_identity_agent && var.use_fargate_profile)
    error_message = "EKS Pod Identity is not supported on Fargate. Set use_eks_pod_identity_agent = false when use_fargate_profile = true."
  }
}

variable "create_eks_worker_nodes_in_private_subnet" {
  type    = bool
  default = true
}

variable "use_fargate_profile" {
  description = <<EOF
  Defaults to false to use node group. 
  If true, creates fargates profiles instead. 
  Will force "create_eks_worker_nodes_in_private_subnet" to 
  be true if "use_fargate_profile" is true.
  EOF
  type        = bool
  default     = false
}

variable "create_aws_ebs_csi_driver_add_on" {
  description = "Create the aws_ebs_csi_driver add-on for EKS."
  type        = bool
  default     = false
}

variable "create_amazon_cloudwatch_observability_add_on" {
  description = "Create the amazon_cloudwatch_observability add-on for EKS."
  type        = bool
  default     = false
}

variable "enable_auto_mode" {
  description = "Enable auto mode for EKS."
  type        = bool
  default     = false
}

variable "ecr_repository_name" {
  type    = string
  default = "simple-python-app"
}


variable "deploy_kyverno_via_helm_provider" {
  description = "Install the Kyverno Helm chart with Terraform instead of running helm manually."
  type        = bool
  default     = false
}

variable "kyverno_chart_version" {
  type    = string
  default = "3.9.0"
}
