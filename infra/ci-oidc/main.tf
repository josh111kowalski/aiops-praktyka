# Rola, którą pipeline Kantyny przejmuje przez OIDC: push do ECR i helm upgrade w EKS.
# Bez kluczy w GitHubie: workflow dostaje krótkotrwałe poświadczenia od STS.

terraform {
  required_version = ">= 1.6"
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 6.0"
    }
    github = {
      source  = "integrations/github"
      version = "~> 6.0"
    }
  }
}

provider "github" {
  owner = local.owner
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

variable "release_reviewer_team_ids" {
  description = "ID zespołów GitHub, które zatwierdzają wdrożenia z release/* (gh api orgs/<org>/teams/<slug> -q .id)"
  type        = list(number)
  default     = []
}

variable "release_reviewer_user_ids" {
  description = "ID użytkowników GitHub, którzy zatwierdzają wdrożenia z release/* (gh api users/<login> -q .id)"
  type        = list(number)
  default     = []
}

locals {
  owner = split("/", var.github_repo)[0]
  repo  = split("/", var.github_repo)[1]

  # Release'y z release/* NIE przechodzą po samym ref: gałąź release/<cokolwiek> może
  # utworzyć każdy z prawem zapisu. Wdrożenie release'u idzie przez environment
  # "release" (wymagani reviewerzy + tylko gałęzie release/*), a trust policy
  # akceptuje wyłącznie sub tego environmentu — token powstaje dopiero po akceptacji.
  release_environment = "release"

  sub_prefixes = [
    "repo:${var.github_repo}",
    "repo:${local.owner}@${var.github_owner_id}/${local.repo}@${var.github_repo_id}",
  ]
}

resource "github_repository_environment" "release" {
  repository          = local.repo
  environment         = local.release_environment
  prevent_self_review = true
  can_admins_bypass   = false

  reviewers {
    teams = var.release_reviewer_team_ids
    users = var.release_reviewer_user_ids
  }

  deployment_branch_policy {
    protected_branches     = false
    custom_branch_policies = true
  }

  lifecycle {
    precondition {
      condition     = length(var.release_reviewer_team_ids) + length(var.release_reviewer_user_ids) > 0
      error_message = "Environment release musi mieć co najmniej jednego reviewera — bez tego każdy z prawem zapisu przejmie rolę kantyna-ci."
    }
  }
}

resource "github_repository_environment_deployment_policy" "release" {
  repository     = local.repo
  environment    = github_repository_environment.release.environment
  branch_pattern = "release/*"
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

    # Dokładnie dwa źródła, w obu formatach sub (klasycznym i z niezmiennymi ID):
    #  - gałąź main (ref),
    #  - environment "release" (z reviewerami, ograniczony do release/*).
    # StringEquals, bez wildcardów — żaden wzorzec gałęzi nie wpuszcza tokenu.
    condition {
      test     = "StringEquals"
      variable = "token.actions.githubusercontent.com:sub"
      values = flatten([
        for p in local.sub_prefixes : [
          "${p}:ref:refs/heads/main",
          "${p}:environment:${local.release_environment}",
        ]
      ])
    }
  }
}

resource "aws_iam_role" "ci" {
  name                 = "kantyna-ci"
  assume_role_policy   = data.aws_iam_policy_document.ci_trust.json
  max_session_duration = 7200 # build release'u z testami e2e trwa ponad godzinę

  tags = {
    app   = "kantyna"
    owner = "platform"
  }
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
