output "vault_policy" {
  description = "vault policy"
  value = var.v-policy-name
}
output "k8s-host" {
    value = var.k8s-host
}

output "secret-key" {
  value = var.k8s-secret-key
}