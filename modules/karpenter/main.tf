################################################################################
# Karpenter Module
# Based on: https://github.com/aws-samples/karpenter-blueprints
# Reference: https://karpenter.sh/docs/getting-started/
################################################################################

data "aws_region" "current" {}
data "aws_caller_identity" "current" {}
data "aws_partition" "current" {}

data "aws_ecrpublic_authorization_token" "token" {
  provider = aws.virginia
}

locals {
  account_id = data.aws_caller_identity.current.account_id
  region     = data.aws_region.current.name
  partition  = data.aws_partition.current.partition
}

################################################################################
# Karpenter IAM Role for Service Account (IRSA)
################################################################################

module "karpenter" {
  source  = "terraform-aws-modules/eks/aws//modules/karpenter"
  version = "~> 20.24"

  cluster_name = var.cluster_name

  # Enable Pod Identity for Karpenter (modern approach)
  enable_pod_identity             = true
  create_pod_identity_association = true

  # IAM role for Karpenter nodes
  node_iam_role_use_name_prefix = false
  node_iam_role_name            = "${var.cluster_name}-karpenter-node"

  # Enable SQS queue for spot termination handling
  enable_spot_termination = var.enable_spot_termination

  tags = var.tags
}

################################################################################
# Karpenter Helm Release
################################################################################

resource "helm_release" "karpenter" {
  name             = "karpenter"
  namespace        = var.karpenter_namespace
  create_namespace = true
  repository       = "oci://public.ecr.aws/karpenter"
  chart            = "karpenter"
  version          = var.karpenter_version
  wait             = false

  values = [
    <<-EOT
    settings:
      clusterName: ${var.cluster_name}
      clusterEndpoint: ${var.cluster_endpoint}
      interruptionQueue: ${module.karpenter.queue_name}
    serviceAccount:
      annotations:
        eks.amazonaws.com/role-arn: ${module.karpenter.iam_role_arn}
    controller:
      resources:
        requests:
          cpu: 1
          memory: 1Gi
        limits:
          cpu: 1
          memory: 1Gi
    nodeSelector:
      karpenter.sh/controller: "true"
    tolerations:
      - key: CriticalAddonsOnly
        operator: Exists
    webhook:
      enabled: false
    EOT
  ]

  depends_on = [module.karpenter]
}

################################################################################
# Default EC2NodeClass
# Defines the compute configuration for Karpenter-provisioned nodes
################################################################################

resource "kubectl_manifest" "karpenter_node_class" {
  yaml_body = <<-YAML
    apiVersion: karpenter.k8s.aws/v1
    kind: EC2NodeClass
    metadata:
      name: default
    spec:
      role: ${module.karpenter.node_iam_role_name}
      amiSelectorTerms:
        - alias: al2023@latest
      subnetSelectorTerms:
        - tags:
            karpenter.sh/discovery: ${var.cluster_name}
      securityGroupSelectorTerms:
        - tags:
            karpenter.sh/discovery: ${var.cluster_name}
      tags:
        Name: "${var.cluster_name}-karpenter-node"
        karpenter.sh/discovery: ${var.cluster_name}
        ${join("\n        ", [for k, v in var.tags : "${k}: \"${v}\""])}
  YAML

  depends_on = [helm_release.karpenter]
}

################################################################################
# Default NodePool
# Defines the scheduling constraints for Karpenter-provisioned nodes
################################################################################

resource "kubectl_manifest" "karpenter_node_pool" {
  yaml_body = <<-YAML
    apiVersion: karpenter.sh/v1
    kind: NodePool
    metadata:
      name: default
    spec:
      template:
        spec:
          nodeClassRef:
            group: karpenter.k8s.aws
            kind: EC2NodeClass
            name: default
          requirements:
            - key: kubernetes.io/arch
              operator: In
              values: ${jsonencode(var.node_architecture)}
            - key: kubernetes.io/os
              operator: In
              values: ["linux"]
            - key: karpenter.sh/capacity-type
              operator: In
              values: ${jsonencode(var.node_capacity_types)}
            - key: node.kubernetes.io/instance-type
              operator: In
              values: ${jsonencode(var.node_instance_types)}
      disruption:
        consolidationPolicy: WhenEmptyOrUnderutilized
        consolidateAfter: 1m
      limits:
        cpu: 1000
        memory: 1000Gi
  YAML

  depends_on = [kubectl_manifest.karpenter_node_class]
}
