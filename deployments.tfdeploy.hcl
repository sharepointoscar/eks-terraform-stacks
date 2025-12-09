################################################################################
# Multi-Region EKS Deployments
# Deploys the complete stack (VPC + EKS + Addons) to three AWS regions
################################################################################

#-------------------------------------------------------------------------------
# US East (N. Virginia) - us-east-1
#-------------------------------------------------------------------------------

deployment "use1" {
  inputs = {
    region          = "us-east-1"
    cluster_name    = "eks-use1"
    cluster_version = "1.30"
    vpc_cidr        = "10.0.0.0/16"
    azs             = ["us-east-1a", "us-east-1b", "us-east-1c"]
    tags = {
      Environment = "workshop"
      Region      = "us-east-1"
      ManagedBy   = "terraform-stacks"
    }
  }
}

#-------------------------------------------------------------------------------
# US West (Oregon) - us-west-2
#-------------------------------------------------------------------------------

deployment "usw2" {
  inputs = {
    region          = "us-west-2"
    cluster_name    = "eks-usw2"
    cluster_version = "1.30"
    vpc_cidr        = "10.1.0.0/16"
    azs             = ["us-west-2a", "us-west-2b", "us-west-2c"]
    tags = {
      Environment = "workshop"
      Region      = "us-west-2"
      ManagedBy   = "terraform-stacks"
    }
  }
}

#-------------------------------------------------------------------------------
# EU (Frankfurt) - eu-central-1
#-------------------------------------------------------------------------------

deployment "euc1" {
  inputs = {
    region          = "eu-central-1"
    cluster_name    = "eks-euc1"
    cluster_version = "1.30"
    vpc_cidr        = "10.2.0.0/16"
    azs             = ["eu-central-1a", "eu-central-1b", "eu-central-1c"]
    tags = {
      Environment = "workshop"
      Region      = "eu-central-1"
      ManagedBy   = "terraform-stacks"
    }
  }
}
