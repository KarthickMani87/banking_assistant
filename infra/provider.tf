terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }
  required_version = ">= 1.6"
}

#######################
# Bootstrap provider (uses direct IAM user creds)
#######################
provider "aws" {
  alias   = "provisioner"
  region  = var.aws_region
  profile = "provisioner"   # <- force use of provisioner profile
}

#######################
# Main provider (uses TerraformProvisionerRole)
#######################
provider "aws" {
  region  = var.aws_region
  profile = "provisioner"  # this profile already assumes TerraformProvisionerRole
}

#######################
# Caller identity (debug)
#######################
data "aws_caller_identity" "current" {}
