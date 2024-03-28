terraform {
  required_providers {
    kubectl = {
      source  = "gavinbunney/kubectl"
    }
  }
}
provider "kubernetes" {
  config_path    = var.k8s-config-path
  config_context = var.k8s-config-context
}

provider "kubectl" {
  config_path = var.k8s-config-path
  config_context = var.k8s-config-context
}


provider "helm" {
  kubernetes {
    config_path    = var.k8s-config-path
    config_context = var.k8s-config-context
  }
}

provider "vault" {
  token   = "root"
  address = local.vault-addr
}

resource "helm_release" "secrets-store-csi-driver" {
  chart            = "secrets-store-csi-driver"
  name             = "csi-secrets-store"
  namespace        = "default"
  create_namespace = true
  repository       = "https://kubernetes-sigs.github.io/secrets-store-csi-driver/charts"

  set {
    name  = "syncSecret.enabled"
    value = "true"
  }

  set {
    name  = "enableSecretRotation"
    value = "true"
  }

  wait = true
}

resource "helm_release" "vault" {
  depends_on       = [helm_release.secrets-store-csi-driver]
  name             = "vault"
  namespace        = "default"
  create_namespace = true

  repository = "https://helm.releases.hashicorp.com"
  chart      = "vault"

  set {
    name  = "server.enabled"
    value = "false"
  }

  set {
    name  = "csi.enabled"
    value = "true"
  }

  set {
    name  = "injector.enabled"
    value = "true"
  }

  set {
    name  = "injector.externalVaultAddr"
    value = local.vault-ext-addr
  }
}

# resource "null_resource" "check-csi-crd" {
#   triggers = {
#     always_run = "${timestamp()}"
#   }

#   provisioner "local-exec" {
#     command = <<EOT
# while [ true ]; do
#   STATUS=$(kubectl --kubeconfig ~/.kube/config get crd secretproviderclasses.secrets-store.csi.x-k8s.io --ignore-not-found -o jsonpath='{.status.conditions[?(@.type=="NamesAccepted")].reason}')
#   if [ "$STATUS" = "NoConflicts" ]; then
#     echo "EXISTS"
#     break
#   else
#     echo "INPROGRESS"
#   fi
# done
# EOT
#     interpreter = ["/bin/bash", "-c"]
#   }

#   depends_on = [ helm_release.secrets-store-csi-driver, helm_release.vault ]
# }

resource "kubernetes_service" "external-vault" {
  metadata {
    name = var.vault-ext-name
  }
  spec {
    port {
      protocol = "TCP"
      port     = var.vault-port
    }
  }
}

resource "kubernetes_endpoints" "external-vault" {
  metadata {
    name = var.vault-ext-name
  }
  subset {
    address {
      ip = var.vault-ext-ip
    }
    port {
      port = var.vault-port
    }
  }
}

resource "kubernetes_service_account" "vault-auth" {
  metadata {
    name      = "vault-auth"
    namespace = "default"
  }
}

resource "kubernetes_cluster_role_binding" "role-tokenreview-binding" {
  metadata {
    name = "role-tokenreview-binding"
  }
  role_ref {
    api_group = "rbac.authorization.k8s.io"
    kind      = "ClusterRole"
    name      = "system:auth-delegator"
  }
  subject {
    kind      = "ServiceAccount"
    name      = kubernetes_service_account.vault-auth.metadata[0].name
    namespace = "default"
  }
}

resource "kubernetes_secret" "vault-auth-token" {
  type = "kubernetes.io/service-account-token"
  metadata {
    name      = "vault-auth-token"
    namespace = "default"
    annotations = {
      "kubernetes.io/service-account.name" = "vault-auth"
    }
  }
}

resource "vault_auth_backend" "kubernetes" {
  type = "kubernetes"
}

data "kubernetes_secret" "vault-auth-token" {
  depends_on = [kubernetes_secret.vault-auth-token]
  metadata {
    name      = kubernetes_secret.vault-auth-token.metadata[0].name
    namespace = kubernetes_secret.vault-auth-token.metadata[0].namespace
  }
}

resource "vault_kubernetes_auth_backend_config" "auth" {
  backend                = vault_auth_backend.kubernetes.path
  kubernetes_host        = var.k8s-host
  kubernetes_ca_cert     = data.kubernetes_secret.vault-auth-token.data["ca.crt"]
  token_reviewer_jwt     = data.kubernetes_secret.vault-auth-token.data.token
  disable_iss_validation = true
  disable_local_ca_jwt   = true
}

resource "vault_kv_secret_v2" "secret" {
  mount = "secret"
  name  = "example/config"
  data_json = jsonencode(
    {
      username = "exampleUser"
      password = "examplePass"
    }
  )
}

resource "vault_policy" "policy" {
  name   = var.v-policy-name
  policy = <<EOT
path "${vault_kv_secret_v2.secret.mount}/data/${vault_kv_secret_v2.secret.name}" {
  capabilities = ["read", "list"]
}
EOT
}

resource "kubernetes_secret" "secret" {
  metadata {
    name      = var.k8s-secret-name
    namespace = "default"
  }
  data = {
    "${var.k8s-secret-key}" = "mongodb://s-user:s-pass@some.mongodb.server"
  }
}

resource "vault_kubernetes_auth_backend_role" "role" {
  backend                          = vault_kubernetes_auth_backend_config.auth.backend
  role_name                        = var.v-role-name
  bound_service_account_names      = ["vault-auth"]
  bound_service_account_namespaces = ["default"]
  token_ttl                        = 300
  token_policies                   = [var.v-policy-name]
}

resource "kubectl_manifest" "secretproviderclass" {
  depends_on = [ helm_release.vault ]
  yaml_body = templatefile("spc.yaml", {
    csi-spc-name = var.csi-spc
    vault-secret-mount = vault_kv_secret_v2.secret.mount
    vault-secret-path = vault_kv_secret_v2.secret.name
    vault-role = var.v-role-name
  })
}

resource "kubectl_manifest" "busybox" {
  depends_on = [ kubectl_manifest.secretproviderclass ]
  yaml_body = templatefile("busybox.yaml", {
    csi-spc-name = var.csi-spc
    secret-name = var.k8s-secret-name
    secret-url = var.k8s-secret-key
    vault-secret-mount = vault_kv_secret_v2.secret.mount
    vault-secret-path = vault_kv_secret_v2.secret.name
    vault-role = var.v-role-name
  })
}
