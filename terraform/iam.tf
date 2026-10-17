/* -----------------------------------------------------------------------------------
VPC CNI
----------------------------------------------------------------------------------- */
resource "aws_iam_role" "eks_vpc_cni_role" {
  count       = var.enable_auto_mode ? 0 : 1
  name        = "vpc-cni-irsa"
  description = "IAM role for VPC-CNI add-on"

  assume_role_policy = var.use_eks_pod_identity_agent ? jsonencode({
    "Version" : "2012-10-17",
    "Statement" : [
      {
        "Sid" : "AllowEksAuthToAssumeRoleForPodIdentity",
        "Effect" : "Allow",
        "Principal" : {
          "Service" : "pods.eks.amazonaws.com"
        },
        "Action" : [
          "sts:AssumeRole",
          "sts:TagSession"
        ],
        "Condition" : {
          "StringEquals" : {
            "aws:SourceAccount" : data.aws_caller_identity.current.account_id
          },
          "ArnEquals" : {
            "aws:SourceArn" : module.eks.cluster_arn
          }
        }
      }
    ]
    }) : jsonencode({
    "Version" : "2012-10-17"
    "Statement" : [
      {
        "Effect" : "Allow",
        "Principal" : {
          "Federated" : module.eks.oidc_provider_arn
        },
        "Action" : "sts:AssumeRoleWithWebIdentity",
        "Condition" : {
          "StringLike" : {
            "${module.eks.oidc_provider}:sub" : "system:serviceaccount:kube-system:aws-node",
            "${module.eks.oidc_provider}:aud" : "sts.amazonaws.com"
          }
        }
      }
    ]
  })

  tags = local.default_tags
}

resource "aws_iam_role_policy_attachment" "eks_vpc_cni_policy_attachment" {
  count      = var.enable_auto_mode ? 0 : 1
  role       = aws_iam_role.eks_vpc_cni_role[0].name
  policy_arn = "arn:aws:iam::aws:policy/AmazonEKS_CNI_Policy"
}

resource "aws_eks_pod_identity_association" "vpc_cni" {
  count           = var.use_eks_pod_identity_agent && !var.enable_auto_mode ? 1 : 0
  cluster_name    = module.eks.cluster_name
  namespace       = "kube-system"
  service_account = "aws-node"
  role_arn        = aws_iam_role.eks_vpc_cni_role[0].arn
}

/* -----------------------------------------------------------------------------------
EKS Amazon EBS CSI add-on
----------------------------------------------------------------------------------- */
resource "aws_iam_role" "amazon_EBS_CSI_iam_role" {
  count       = var.create_aws_ebs_csi_driver_add_on && !var.enable_auto_mode ? 1 : 0
  name        = "amazon-ebs-csi-irsa"
  description = "IAM role for Amazon EBS CSI driver add-on"

  assume_role_policy = jsonencode({
    "Version" : "2012-10-17"
    "Statement" : [
      {
        "Effect" : "Allow",
        "Principal" : {
          "Federated" : module.eks.oidc_provider_arn
        },
        "Action" : "sts:AssumeRoleWithWebIdentity",
        "Condition" : {
          "StringLike" : {
            "${module.eks.oidc_provider}:sub" : "system:serviceaccount:kube-system:ebs-csi-controller-sa",
            "${module.eks.oidc_provider}:aud" : "sts.amazonaws.com"
          }
        }
      }
    ]
  })

}

resource "aws_iam_role_policy_attachment" "amazon_EBS_CSI_iam_role" {
  count      = var.create_aws_ebs_csi_driver_add_on && !var.enable_auto_mode ? 1 : 0
  role       = aws_iam_role.amazon_EBS_CSI_iam_role[0].name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AmazonEBSCSIDriverPolicy"
}

/* -----------------------------------------------------------------------------------
AWS CloudWatch Observability add-on
----------------------------------------------------------------------------------- */
### https://docs.aws.amazon.com/AmazonCloudWatch/latest/monitoring/deploy-container-insights-EKS.html
### https://docs.aws.amazon.com/AmazonCloudWatch/latest/monitoring/Container-Insights-prerequisites.html
# resource "aws_iam_role_policy_attachment" "aws_cloudwatch-observability-add-on-worker-node" {
#   role       = module.eks.eks_managed_node_groups["node_group_1"]["iam_role_name"]
#   policy_arn = "arn:aws:iam::aws:policy/CloudWatchAgentServerPolicy"
# }

/*
Instead of attaching IAM policy to the IAM role of the worker node,
annotate an IAM role to the fluent bit's serviceaccount.
*/
resource "aws_iam_role" "CloudWatchAgent" {
  count       = var.create_amazon_cloudwatch_observability_add_on ? 1 : 0
  name        = "CloudWatchAgent_EKS"
  description = "One for each AWS account"

  assume_role_policy = jsonencode({
    "Version" : "2012-10-17"
    "Statement" : [
      {
        "Effect" : "Allow",
        "Principal" : {
          "Federated" : module.eks.oidc_provider_arn
        },
        "Action" : "sts:AssumeRoleWithWebIdentity",
        "Condition" : {
          "StringLike" : { # If you want to allow all service accounts within a namespace to use the role, use "StringLike" instead of "StringEquals"
            "${module.eks.oidc_provider}:sub" : "system:serviceaccount:amazon-cloudwatch:*",
            "${module.eks.oidc_provider}:aud" : "sts.amazonaws.com"
          }
        }
      }
    ]
  })

  tags = local.default_tags
}

resource "aws_iam_role_policy_attachment" "aws_cloudwatch-observability-add-on-IRSA" {
  count      = var.create_amazon_cloudwatch_observability_add_on ? 1 : 0
  role       = aws_iam_role.CloudWatchAgent[0].name
  policy_arn = "arn:aws:iam::aws:policy/CloudWatchAgentServerPolicy"
}

/* -----------------------------------------------------------------------------------
IAM role for Kyverno admission controller
----------------------------------------------------------------------------------- */
resource "aws_iam_role" "kyverno" {
  name        = "kyverno-admission-controller"
  description = "IAM role for Kyverno admission controller"

  assume_role_policy = var.use_eks_pod_identity_agent ? jsonencode({
    "Version" : "2012-10-17",
    "Statement" : [
      {
        "Sid" : "AllowEksAuthToAssumeRoleForPodIdentity",
        "Effect" : "Allow",
        "Principal" : {
          "Service" : "pods.eks.amazonaws.com"
        },
        "Action" : [
          "sts:AssumeRole",
          "sts:TagSession"
        ],
        "Condition" : {
          "StringEquals" : {
            "aws:SourceAccount" : data.aws_caller_identity.current.account_id
          },
          "ArnEquals" : {
            "aws:SourceArn" : module.eks.cluster_arn
          }
        }
      }
    ]
    }) : jsonencode({
    "Version" : "2012-10-17"
    "Statement" : [
      {
        "Effect" : "Allow",
        "Principal" : {
          "Federated" : module.eks.oidc_provider_arn
        },
        "Action" : "sts:AssumeRoleWithWebIdentity",
        "Condition" : {
          "StringLike" : {
            "${module.eks.oidc_provider}:sub" : "system:serviceaccount:kyverno:kyverno-admission-controller",
            "${module.eks.oidc_provider}:aud" : "sts.amazonaws.com"
          }
        }
      }
    ]
  })

  tags = local.default_tags
}

resource "aws_iam_policy" "kyverno" {
  name        = "kyverno-admission-controller-policy"
  path        = "/"
  description = "Policy for Kyverno admission controller"

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "ECRAuth"
        Effect = "Allow"
        Action = [
          "ecr:GetAuthorizationToken"
        ]
        Resource = "*"
      },
      {
        Sid    = "ReadECR"
        Effect = "Allow"
        Action = [
          "ecr:BatchCheckLayerAvailability",
          "ecr:BatchGetImage",
          "ecr:GetDownloadUrlForLayer"
        ]
        Resource = "arn:aws:ecr:${data.aws_region.current.region}:${data.aws_caller_identity.current.account_id}:repository/${var.ecr_repository_name}"
      }
    ]
  })
}

resource "aws_iam_role_policy_attachment" "kyverno_policy_attachment" {
  role       = aws_iam_role.kyverno.name
  policy_arn = aws_iam_policy.kyverno.arn
}

resource "aws_eks_pod_identity_association" "kyverno" {
  count           = var.use_eks_pod_identity_agent ? 1 : 0
  cluster_name    = module.eks.cluster_name
  namespace       = "kyverno"
  service_account = "kyverno-admission-controller"
  role_arn        = aws_iam_role.kyverno.arn
}