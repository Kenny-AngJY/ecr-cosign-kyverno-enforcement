terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 6.58"
    }
    helm = {
      source  = "hashicorp/helm"
      version = "~> 3.2"
    }
  }

  required_version = "~> 1.15"

  # backend "s3" {
  #   bucket  = "xxx"
  #   key     = "xxx.tfstate"
  #   region  = "ap-southeast-1"
  #   encrypt = true
  #   use_lockfile = true
  # }
}

provider "aws" {
  region = var.region
  default_tags {
    tags = local.default_tags
  }
}