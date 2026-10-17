### list (or tuple): a sequence of values
variable "list_of_public_cidr_range" {
  type = list(string)
  # default = ["10.2.0.0/24", "10.2.1.0/24", "10.2.2.0/24"]
  ### Functions may not be called here.
  #   default = cidrsubnets("10.1.0.0/20", 4, 4, 4)
}

variable "list_of_private_cidr_range" {
  type = list(string)
}

variable "list_of_azs" {
  type = list(string)
}

variable "vpc_cidr_block" {
  type = string
}

variable "stack_name" {
  type = string
}

variable "create_nat_gateway" {
  type = bool
}

variable "cluster_name" {
  description = "EKS cluster name, used in the subnet discovery tags."
  type        = string
}
