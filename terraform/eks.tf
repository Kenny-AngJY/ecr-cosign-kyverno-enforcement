module "eks" {
  source                                 = "terraform-aws-modules/eks/aws"
  version                                = "21.29.0" # Published October 8, 2026
  create                                 = true
  name                                   = local.cluster_name
  kubernetes_version                     = "1.37"
  authentication_mode                    = "API"
  endpoint_private_access                = true # Indicates whether or not the Amazon EKS private API server endpoint is enabled
  endpoint_public_access                 = true # Indicates whether or not the Amazon EKS public API server endpoint is enabled
  endpoint_public_access_cidrs           = ["0.0.0.0/0"]
  cloudwatch_log_group_retention_in_days = 30 # Control plane log group
  create_kms_key                         = true
  enable_irsa                            = true # Determines whether to create an OpenID Connect Provider for EKS to enable IRSA

  encryption_config = {}

  compute_config = {
    enabled    = var.enable_auto_mode
    node_pools = var.enable_auto_mode ? ["general-purpose", "system"] : null
  }

  addons = var.enable_auto_mode ? {} : {
    coredns = {
      addon_version = "v1.14.7-eksbuild.11"
      # CoreDNS defaults to EC2 nodes; without this it stays Pending on a Fargate-only cluster.
      configuration_values = var.use_fargate_profile ? jsonencode({ computeType = "Fargate" }) : null
    }
    # kube-proxy pod (that is deployed as a daemonset) shares the same IPv4 address as the node it's on.
    kube-proxy = {
      before_compute = true
      addon_version  = "v1.37.0-eksbuild.22"
    }
    # Network interface will show all IPs used in the subnet
    # VPC CNI add-on will create the "aws-node" daemonset in the kube-system namespace.
    vpc-cni = {
      before_compute           = true
      addon_version            = "v1.23.2-eksbuild.3" # major-version.minor-version.patch-version-eksbuild.build-number.
      service_account_role_arn = var.use_eks_pod_identity_agent ? null : aws_iam_role.eks_vpc_cni_role[0].arn
      configuration_values = jsonencode(
        {
          enableNetworkPolicy = "true" # To enable using the NetworkPolicy controller
          env = {
            # https://docs.aws.amazon.com/eks/latest/userguide/cni-increase-ip-addresses.html
            # https://github.com/aws/amazon-vpc-cni-k8s/blob/master/README.md
            # kubectl get ds aws-node -n kube-system -o yaml
            WARM_IP_TARGET    = "3" # Specifies the number of free IP addresses that the ipamd daemon should attempt to keep available for pod assignment on the node.
            MINIMUM_IP_TARGET = "3" # Specifies the number of total IP addresses that the ipamd daemon should attempt to allocate for pod assignment on the node.
            # ENABLE_PREFIX_DELEGATION = true # To enable prefix delegation on nitro instances. Setting ENABLE_PREFIX_DELEGATION to true will start allocating a prefix (/28 for IPv4 and /80 for IPv6) instead of a secondary IP in the ENIs subnet.
            # NETWORK_POLICY_ENFORCING_MODE = "strict" # strict | standard
          }
        }
      )
    }
  }

  vpc_id = var.create_vpc ? module.vpc[0].vpc_id : var.vpc_id
  /* -----------------------------------------------------------------------------------
  A list of subnet IDs where the nodes/node groups will be provisioned.
  If control_plane_subnet_ids is not provided, the EKS cluster control plane (ENIs) will be provisioned in these subnets
  ----------------------------------------------------------------------------------- */
  subnet_ids = (var.use_fargate_profile || var.create_eks_worker_nodes_in_private_subnet) ? local.private_subnet_ids : local.public_subnet_ids

  /* -----------------------------------------------------------------------------------
  A list of subnet IDs where the EKS Managed ENIs will be provisioned.
  Used for expanding the pool of subnets used by nodes/node groups without replacing the EKS control plane
  ----------------------------------------------------------------------------------- */
  control_plane_subnet_ids = var.create_eks_worker_nodes_in_private_subnet ? local.private_subnet_ids : local.public_subnet_ids

  # self_managed_node_groups = {
  #   self_managed_NG1 = {
  #     desired_capacity = 2
  #     max_capacity     = 2
  #     min_capacity     = 1
  #     instance_types   = ["t3.medium", "t3.large"]
  #     capacity_type    = "SPOT" # ON_DEMAND | SPOT
  #   }
  # }

  # EKS Managed Node Group(s)
  eks_managed_node_groups = var.use_fargate_profile || var.enable_auto_mode ? {} : {
    eks_managed_NG1 = {
      min_size = 1
      max_size = 2
      /*
      desired_size is ignored after the initial creation
      https://github.com/bryantbiggs/eks-desired-size-hack
      */
      desired_size  = 1
      capacity_type = "SPOT"
    }
  }

  # Fargate Profile(s)
  fargate_profiles = {
    profile_1 = {
      create          = var.use_fargate_profile
      name            = "kube-system"
      create_iam_role = true # pod_execution_role
      # AWS Fargate can only use private subnets with NAT gateway to deploy your pods.
      subnet_ids = local.private_subnet_ids
      selectors = [
        # If you omit labels, it matches ALL pods in the namespace
        {
          namespace = "kube-system"
        }
      ]
      tags = {
        Terraform = "true"
      }
    }
    profile_2 = {
      create          = var.use_fargate_profile
      name            = "dev"
      create_iam_role = true # pod_execution_role
      # AWS Fargate can only use private subnets with NAT gateway to deploy your pods.
      subnet_ids = local.private_subnet_ids
      selectors = [
        # Match pods in this namespace with these labels
        {
          namespace = "dev"
          labels = {
            "app.kubernetes.io/instance" = "dev-services"
          }
        }
      ]
      tags = {
        Terraform = "true"
      }
    }
    # Kyverno and the demo workload need Fargate capacity too, otherwise their pods stay Pending.
    profile_3 = {
      create          = var.use_fargate_profile
      name            = "kyverno-demo"
      create_iam_role = true # pod_execution_role
      subnet_ids      = local.private_subnet_ids
      selectors = [
        {
          namespace = "kyverno"
        },
        {
          namespace = "default"
        }
      ]
      tags = {
        Terraform = "true"
      }
    }
  }

  # Cluster access entry
  # To add the current caller identity as an administrator
  enable_cluster_creator_admin_permissions = true

  ## https://docs.aws.amazon.com/eks/latest/userguide/control-plane-logs.html
  enabled_log_types = [
    "audit",
    "api",
    "authenticator",
    "controllerManager",
    "scheduler"
  ]

  tags                = local.default_tags
  deletion_protection = false
}

/*
Enables support for Amazon EBS volumes using the Container Storage Interface (CSI) specification. 
It allows you to dynamically provision and manage EBS-backed PersistentVolumes in Kubernetes.
*/
resource "aws_eks_addon" "aws_ebs_csi_driver" {
  # EKS Auto Mode has built-in EBS storage, so the add-on and its IAM role are skipped.
  count                       = var.create_aws_ebs_csi_driver_add_on && !var.enable_auto_mode ? 1 : 0
  cluster_name                = module.eks.cluster_name
  addon_name                  = "aws-ebs-csi-driver"
  addon_version               = "v1.63.0-eksbuild.1"
  resolve_conflicts_on_update = "OVERWRITE" # NONE | OVERWRITE | PRESERVE

  service_account_role_arn = aws_iam_role.amazon_EBS_CSI_iam_role[0].arn
}

/*
Add a deployment called "amazon-cloudwatch-observability-controller-manager"
Adds a ds called "cloudwatch-agent" and "fluent-bit"
Adds CRDs, "amazoncloudwatchagents.cloudwatch.aws.amazon.com", "dcgmexporters.cloudwatch.aws.amazon.com", "instrumentations.cloudwatch.aws.amazon.com", "neuronmonitors.cloudwatch.aws.amazon.com", 

The container logs are sent to CloudWatch Logs with the log group name /aws/containerinsights/<cluster-name>/application
*/
resource "aws_eks_addon" "amazon_cloudwatch_observability" {
  count                       = var.create_amazon_cloudwatch_observability_add_on ? 1 : 0
  cluster_name                = module.eks.cluster_name
  addon_name                  = "amazon-cloudwatch-observability"
  addon_version               = "v6.4.0-eksbuild.1"
  resolve_conflicts_on_update = "OVERWRITE" # NONE | OVERWRITE | PRESERVE

  service_account_role_arn = aws_iam_role.CloudWatchAgent[0].arn
  /*
  # https://docs.aws.amazon.com/AmazonCloudWatch/latest/monitoring/ContainerInsights-Prometheus-troubleshooting-EKS.html
  configuration_values = jsonencode({
    "agent" : {
      "name" : "cloudwatch-agent",
      "config" : {
        "agent" : { "region" : "ap-southeast-1" },
        "logs" : {
          "metrics_collected" : {
            "application_signals" : { "hosted_in" : local.cluster_name },
            "kubernetes" : {
              "cluster_name" : local.cluster_name,
              "enhanced_container_insights" : true
            },
            "prometheus" : {
              "emf_processor" : {
                "metric_namespace" : "IstioServiceMesh",
                "metric_declaration" : [
                  {
                    "source_labels" : ["__name__"],
                    "label_matcher" : "istio_requests_total",
                    "dimensions" : [
                      ["ClusterName", "namespace", "pod", "container", "destination_service", "response_code"],
                      ["ClusterName", "namespace", "pod", "container"]
                    ],
                    "metric_selectors" : [
                      "istio_requests_total{reporter=\"source\"}",
                      "istio_requests_total{reporter=\"destination\"}"
                    ]
                  },
                  {
                    "source_labels" : ["__name__"],
                    "label_matcher" : "istio_request_duration_seconds_(sum|count|bucket)",
                    "dimensions" : [
                      ["ClusterName", "namespace", "pod", "container", "destination_service", "response_code"],
                      ["ClusterName", "namespace", "pod", "container"]
                    ],
                    "metric_selectors" : [
                      "istio_request_duration_seconds_sum",
                      "istio_request_duration_seconds_count",
                      "istio_request_duration_seconds_bucket"
                    ]
                  },
                  {
                    "source_labels" : ["__name__"],
                    "label_matcher" : "pilot_(.*)|envoy_(.*)",
                    "dimensions" : [
                      ["ClusterName", "namespace", "pod", "container", "destination_service", "response_code"],
                      ["ClusterName", "namespace", "pod", "container"]
                    ],
                    "metric_selectors" : [
                      "pilot_total_xds_internal_errors",
                      "pilot_xds_pushes",
                      "envoy_cluster_upstream_cx_active",
                      "envoy_http_downstream_rq_total"
                    ]
                  }
                ]
              }
            }
          }
        },
        "traces" : { "traces_collected" : { "application_signals" : {} } }
      },
      "prometheus" : {
        "config" : {
          "global" : { "scrape_interval" : "60s", "scrape_timeout" : "10s" },
          "scrape_configs" : [
            {
              "job_name" : "istio-proxy-sidecars",
              "metrics_path" : "/stats/prometheus",
              "scheme" : "http",
              "kubernetes_sd_configs" : [
                {
                  "role" : "pod"
                }
              ],
              "relabel_configs" : [
                {
                  "action" : "keep",
                  "source_labels" : ["__meta_kubernetes_pod_container_name"],
                  "regex" : "istio-proxy"
                },
                {
                  "action" : "replace",
                  "source_labels" : ["__meta_kubernetes_namespace"],
                  "target_label" : "namespace"
                },
                {
                  "action" : "replace",
                  "source_labels" : ["__meta_kubernetes_pod_name"],
                  "target_label" : "pod"
                },
                {
                  "action" : "replace",
                  "source_labels" : ["__meta_kubernetes_pod_container_name"],
                  "target_label" : "container"
                },
                {
                  "action" : "replace",
                  "replacement" : local.cluster_name,
                  "target_label" : "ClusterName"
                }
              ]
            },
            {
              "job_name" : "istiod",
              "metrics_path" : "/metrics",
              "scheme" : "http",
              "kubernetes_sd_configs" : [
                {
                  "role" : "endpoints"
                }
              ],
              "relabel_configs" : [
                {
                  "action" : "keep",
                  "source_labels" : ["__meta_kubernetes_service_name", "__meta_kubernetes_namespace"],
                  "regex" : "istiod;istio-system"
                },
                {
                  "action" : "replace",
                  "source_labels" : ["__meta_kubernetes_namespace"],
                  "target_label" : "namespace"
                },
                {
                  "action" : "replace",
                  "source_labels" : ["__meta_kubernetes_pod_name"],
                  "target_label" : "pod"
                },
                {
                  "action" : "replace",
                  "replacement" : local.cluster_name,
                  "target_label" : "ClusterName"
                }
              ]
            }
          ]
        }
      }
    },
    "containerLogs" : {
      "enabled" : true, # Fluent Bit configuration to enable container logs
      "fluentBit" : {
        "resources" : {
          "requests" : { "cpu" : "50m", "memory" : "25Mi" },
          "limits" : { "cpu" : "500m", "memory" : "250Mi" }
        }
      }
    }
  })
  */
}

resource "aws_eks_addon" "aws_pod_identity" {
  count                       = var.use_eks_pod_identity_agent && !var.enable_auto_mode ? 1 : 0
  cluster_name                = module.eks.cluster_name
  addon_name                  = "eks-pod-identity-agent"
  addon_version               = "v1.4.0-eksbuild.4"
  resolve_conflicts_on_update = "OVERWRITE" # NONE | OVERWRITE | PRESERVE
}