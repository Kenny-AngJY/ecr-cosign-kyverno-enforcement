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
}

variable "list_of_subnet_ids" {
  description = "If create_vpc is false, define your own subnet_ids."
  type        = list(string)
  default     = []
}

variable "use_eks_pod_identity_agent" {
  description = "Use IAM Roles for Service Account (IRSA) by default."
  type        = bool
  default     = false
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
