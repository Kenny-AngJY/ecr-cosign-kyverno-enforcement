resource "helm_release" "kyverno" {
  count = var.deploy_kyverno_via_helm_provider ? 1 : 0
  name  = "kyverno"

  repository       = "https://kyverno.github.io/kyverno/"
  chart            = "kyverno"
  namespace        = "kyverno"
  create_namespace = true
  version          = var.kyverno_chart_version # chart version

  # With EKS Pod Identity the association in iam.tf supplies credentials,
  # otherwise annotate the service account with the IRSA role.
  set = var.use_eks_pod_identity_agent ? [] : [
    {
      name  = "admissionController.rbac.serviceAccount.annotations.eks\\.amazonaws\\.com/role-arn"
      value = aws_iam_role.kyverno.arn
    }
  ]

  # Credentials and compute must exist before the admission controller starts,
  # otherwise it caches no ECR credentials and needs a restart.
  depends_on = [
    module.eks,
    aws_eks_addon.aws_pod_identity,
    aws_eks_pod_identity_association.kyverno,
    aws_iam_role_policy_attachment.kyverno_policy_attachment,
  ]
}
