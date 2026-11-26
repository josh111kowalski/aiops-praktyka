# Rola, którą pipeline Kantyny przejmuje przez OIDC: push do ECR i helm upgrade w EKS.
# Bez kluczy w GitHubie: workflow dostaje krótkotrwałe poświadczenia od STS.

terraform {
  required_version = ">= 1.6"
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 6.0"
    }
  }
}

variable "github_repo" {
  description = "Repozytorium z pipeline'em, np. kantyna-org/kantyna"
  type        = string
}

variable "github_owner_id" {
  description = "Niezmienne ID właściciela repo (gh api users/<owner> -q .id)"
  type        = number
}

variable "github_repo_id" {
  description = "Niezmienne ID repozytorium (gh api repos/<owner>/<repo> -q .id)"
  type        = number
}

variable "ecr_repository_arns" {
  description = "Repozytoria ECR, do których pipeline wypycha obrazy"
  type        = list(string)
}

variable "eks_cluster_arn" {
  type = string
}

locals {
  owner = split("/", var.github_repo)[0]
  repo  = split("/", var.github_repo)[1]
}

resource "aws_iam_openid_connect_provider" "github" {
  url            = "https://token.actions.githubusercontent.com"
  client_id_list = ["sts.amazonaws.com"]
}

data "aws_iam_policy_document" "ci_trust" {
  statement {
    actions = ["sts:AssumeRoleWithWebIdentity"]

    principals {
      type        = "Federated"
      identifiers = [aws_iam_openid_connect_provider.github.arn]
    }

    condition {
      test     = "StringEquals"
      variable = "token.actions.githubusercontent.com:aud"
      values   = ["sts.amazonaws.com"]
    }

    # Tylko gałąź main. Nowe repozytoria wysyłają sub z niezmiennymi ID:
    # repo:<owner>@<id>/<repo>@<id>:ref:... — akceptujemy oba formaty, ID wpisane wprost.
    condition {
      test     = "StringLike"
      variable = "token.actions.githubusercontent.com:sub"
      values = [
        "repo:${var.github_repo}:ref:refs/heads/main",
        "repo:${local.owner}@${var.github_owner_id}/${local.repo}@${var.github_repo_id}:ref:refs/heads/main",
      ]
    }
  }
}

resource "aws_iam_role" "ci" {
  name                 = "kantyna-ci"
  assume_role_policy   = data.aws_iam_policy_document.ci_trust.json
  max_session_duration = 3600
}

data "aws_iam_policy_document" "ci" {
  statement {
    sid       = "EcrLogin"
    actions   = ["ecr:GetAuthorizationToken"]
    resources = ["*"]
  }

  statement {
    sid = "PushImages"
    actions = [
      "ecr:BatchCheckLayerAvailability",
      "ecr:BatchGetImage",
      "ecr:GetDownloadUrlForLayer",
      "ecr:InitiateLayerUpload",
      "ecr:UploadLayerPart",
      "ecr:CompleteLayerUpload",
      "ecr:PutImage",
    ]
    resources = var.ecr_repository_arns
  }

  statement {
    sid       = "Kubeconfig"
    actions   = ["eks:DescribeCluster"]
    resources = [var.eks_cluster_arn]
  }
}

resource "aws_iam_role_policy" "ci" {
  name   = "kantyna-ci"
  role   = aws_iam_role.ci.id
  policy = data.aws_iam_policy_document.ci.json
}
