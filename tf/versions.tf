terraform {
  required_version = ">= 1.5"

  required_providers {
    kubernetes = {
      source  = "hashicorp/kubernetes"
      version = "~> 3.5"
    }
  }

  # Stan lokalny w tym katalogu (tf/), pliki stanu są w .gitignore.
  backend "local" {
    path = "terraform.tfstate"
  }
}
