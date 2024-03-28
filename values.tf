variable "k8s-config-path" {
  type = string
  default = "~/.kube/config"
}

variable "k8s-config-context" {
  type = string
  default = "colima"
}

variable "k8s-host" {
  type = string
  default = "https://127.0.0.1:6443"
}

variable "k8s-secret-name" {
  type = string
  default = "example-secret"
}

variable "k8s-secret-key" {
  type = string
  default = "url"
}

variable "vault-ext-name" {
  type = string
  default = "external-vault"
}

variable "vault-ext-ip" {
  type = string
  default = "192.168.5.2"
}

variable "vault-port" {
  type = number
  default = 8200
}

variable "v-policy-name" {
  type = string
  default = "example-policy"
}

variable "v-role-name" {
  type = string
  default = "example-role"
}

variable "csi-spc" {
  type = string
  default = "csi-spc"
}

locals {
  vault-addr = "http://0.0.0.0:${var.vault-port}"
  vault-ext-addr = "http://${var.vault-ext-name}:${var.vault-port}"
}