output "eks_managed_node_groups_autoscaling_group_names" {
  value = module.eks.eks_managed_node_groups_autoscaling_group_names
}

output "cluster_primary_security_group_id" {
  value = module.eks.cluster_primary_security_group_id
}

output "cluster_security_group_id" {
  value = module.eks.cluster_security_group_id
}

output "node_security_group_id" {
  description = "ID of the node shared security group"
  value       = module.eks.node_security_group_id
}

output "eks_worker_node_subnet" {
  description = "Inform users of the subnet where the EKS worker nodes are deployed."
  value       = (var.use_fargate_profile || var.create_eks_worker_nodes_in_private_subnet) ? "Private" : "Public"
}

# output "eks_managed_node_groups" {
#   description = "Map of attribute maps for all EKS managed node groups created."
#   value       = module.eks.eks_managed_node_groups
# }
