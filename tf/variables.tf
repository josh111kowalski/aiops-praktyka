variable "kubeconfig_path" {
  description = "Ścieżka do pliku kubeconfig."
  type        = string
  default     = "~/.kube/config"
}

variable "kube_context" {
  description = "Kontekst z kubeconfig, w którym działa provider."
  type        = string
  default     = "aiops"
}

variable "namespace" {
  description = "Namespace uczestnika, w którym działa Kantyna."
  type        = string
  default     = "jacek"
}

variable "release" {
  description = "Nazwa release'u Helm Kantyny (etykieta app.kubernetes.io/instance)."
  type        = string
  default     = "kantyna"
}
