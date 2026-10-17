# AWS ECR Cosign Kyverno Demo

This repository supports the Medium article **"Securing the Container Supply Chain: Cosign Image Signing in AWS ECR with Kyverno Enforcement"**.

It provisions the AWS infrastructure for an Amazon EKS based demo, builds and signs a sample container image in Amazon ECR with Cosign, and applies a Kyverno `ImageValidatingPolicy` that rejects unsigned images at admission time.

## What This Repository Contains

- `terraform/` - Terraform configuration for the AWS foundation:
  - VPC and subnets, when `create_vpc = true`
  - Amazon EKS cluster
  - Optional managed node group, Fargate profile, or EKS Auto Mode
  - IAM role and policy that allow the Kyverno admission controller to read images from ECR
  - Optional EBS CSI and CloudWatch Observability add-ons
- `kubernetes/image_validating_policy.yaml` - Kyverno policy that verifies Cosign signatures for images in ECR.
- `kubernetes/deployment.yaml` - Sample Kubernetes deployment that uses the signed image.
- `Dockerfile` - Minimal Python container used for the signing and enforcement demo.
- `disable-all.json` - Cosign signing configuration that disables default transparency log and timestamp authority settings.

## Prerequisites

Install and configure:

- AWS CLI with credentials for the target account
- Terraform
- Docker
- kubectl
- Helm
- Cosign
- jq

The default AWS region is `ap-southeast-1`.

## Important Placeholders

Several Kubernetes examples currently reference this ECR registry:

```text
717240872783.dkr.ecr.ap-southeast-1.amazonaws.com/simple-python-app
```

Before running the demo in your own AWS account, replace that value in:

- `kubernetes/deployment.yaml`
- `kubernetes/image_validating_policy.yaml`

You can keep the repository name as `simple-python-app`, or set a different value with the Terraform variable `ecr_repository_name`.

> Note: this Terraform configuration grants Kyverno access to an ECR repository, but it does not create the ECR repository itself.

## Provision AWS Infrastructure

From the Terraform directory:

```bash
cd terraform
terraform init
terraform plan
terraform apply
```

After the cluster is created, configure `kubectl`:

```bash
aws eks update-kubeconfig \
  --region ap-southeast-1 \
  --name kyverno-eks-cluster
```

## Create or Confirm the ECR Repository

If you are still in the `terraform/` directory, return to the repository root before building the sample image:

```bash
cd ..
```

If the repository does not already exist, create it:

```bash
aws ecr create-repository \
  --repository-name simple-python-app \
  --region ap-southeast-1
```

Set the image variables used in the remaining commands:

```bash
AWS_ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)
AWS_REGION=ap-southeast-1
ECR_REPOSITORY=simple-python-app
ECR_REGISTRY="${AWS_ACCOUNT_ID}.dkr.ecr.${AWS_REGION}.amazonaws.com"
IMAGE_TAG=1.0.0
IMAGE="${ECR_REGISTRY}/${ECR_REPOSITORY}:${IMAGE_TAG}"
```

## Build and Push the Sample Image

```bash
docker build -t "${IMAGE}" .

aws ecr get-login-password --region "${AWS_REGION}" \
  | docker login --username AWS --password-stdin "${ECR_REGISTRY}"

docker push "${IMAGE}"
```

Resolve the immutable image digest:

```bash
DIGEST=$(aws ecr describe-images \
  --repository-name "${ECR_REPOSITORY}" \
  --image-ids imageTag="${IMAGE_TAG}" \
  --region "${AWS_REGION}" \
  --query 'imageDetails[0].imageDigest' \
  --output text)

IMAGE_DIGEST="${ECR_REGISTRY}/${ECR_REPOSITORY}@${DIGEST}"
echo "${IMAGE_DIGEST}"
```

## Sign the Image with Cosign

Generate a local key pair:

```bash
cosign generate-key-pair
```

Sign the image digest:

```bash
cosign sign \
  --key cosign.key \
  --signing-config disable-all.json \
  "${IMAGE_DIGEST}"
```

Verify the signature:

```bash
cosign verify \
  --key cosign.pub \
  --insecure-ignore-tlog \
  "${IMAGE_DIGEST}" | jq .
```

## Install Kyverno

Terraform creates the `kyverno-admission-controller` IAM role. By default (`use_eks_pod_identity_agent = true`), it also creates an EKS Pod Identity association for the `kyverno/kyverno-admission-controller` service account, so no service account annotation is needed:

```bash
helm repo add kyverno https://kyverno.github.io/kyverno/
helm repo update

helm upgrade --install kyverno kyverno/kyverno \
  --version 3.9.0 \
  --namespace kyverno \
  --create-namespace
```

If you set `use_eks_pod_identity_agent = false` (required when `use_fargate_profile = true`, because Pod Identity is not supported on Fargate), use IRSA instead and annotate the service account with the role ARN:

```bash
KYVERNO_ROLE_ARN=$(aws iam get-role \
  --role-name kyverno-admission-controller \
  --query 'Role.Arn' \
  --output text)

helm upgrade --install kyverno kyverno/kyverno \
  --version 3.9.0 \
  --namespace kyverno \
  --create-namespace \
  --set-string "admissionController.rbac.serviceAccount.annotations.eks\.amazonaws\.com/role-arn=${KYVERNO_ROLE_ARN}"
```

Create the Kubernetes Secret that stores the Cosign public key:

```bash
kubectl create secret generic cosign-public-key \
  --namespace kyverno \
  --from-file=cosign.pub=./cosign.pub
```

If Kyverno was installed before its credentials were in place (the Pod Identity association or the IRSA annotation), restart the admission controller so it picks them up:

```bash
kubectl rollout restart deploy kyverno-admission-controller -n kyverno
```

## Apply the Kyverno Policy

Apply the image verification policy:

```bash
kubectl apply -f kubernetes/image_validating_policy.yaml
```

The policy:

- Matches images from the configured ECR repository.
- Loads `cosign.pub` from the `kyverno/cosign-public-key` Secret.
- Uses Kyverno's Amazon credentials provider so the admission controller can authenticate to ECR (via EKS Pod Identity or IRSA).
- Denies workloads when the image does not have a valid Cosign signature.

## Test Enforcement

Apply the sample deployment:

```bash
kubectl apply -f kubernetes/deployment.yaml
```

If the referenced image has a valid signature, admission should succeed. If the image is unsigned, signed with a different key, or outside the expected digest/signature state, Kyverno should reject the workload with:

```text
Image must have a valid Cosign signature
```

You can also inspect the image signature metadata:

```bash
cosign tree "${IMAGE_DIGEST}"
```

## Cleanup

Delete the Kubernetes resources:

```bash
kubectl delete -f kubernetes/deployment.yaml --ignore-not-found
kubectl delete -f kubernetes/image_validating_policy.yaml --ignore-not-found
helm uninstall kyverno -n kyverno
```

Destroy the AWS infrastructure:

```bash
cd terraform
terraform destroy
```
