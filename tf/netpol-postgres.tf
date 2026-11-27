# NetworkPolicy dla Postgresa Kantyny.
# Ruch przychodzący do poda postgres jest dozwolony tylko z podów orders-api
# z tego samego namespace i tylko na TCP 5432. Pozostały ingress jest blokowany.
# Ruch wychodzący z Postgresa nie jest ograniczany (policy_types = ["Ingress"]).
resource "kubernetes_network_policy_v1" "postgres" {
  metadata {
    name      = "${var.release}-postgres"
    namespace = var.namespace

    labels = {
      "app.kubernetes.io/name"       = "postgres"
      "app.kubernetes.io/component"  = "postgres"
      "app.kubernetes.io/instance"   = var.release
      "app.kubernetes.io/part-of"    = "kantyna"
      "app.kubernetes.io/managed-by" = "terraform"
    }
  }

  spec {
    pod_selector {
      match_labels = {
        "app.kubernetes.io/name"     = "postgres"
        "app.kubernetes.io/instance" = var.release
      }
    }

    policy_types = ["Ingress"]

    ingress {
      from {
        pod_selector {
          match_labels = {
            "app.kubernetes.io/name"     = "orders-api"
            "app.kubernetes.io/instance" = var.release
          }
        }
      }

      ports {
        protocol = "TCP"
        port     = "5432"
      }
    }
  }
}
