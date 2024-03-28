locals {
  name_prefix = "demo"
  auth_mount = "${local.name_prefix}-auth-mount"
  auth_policy = "${local.name_prefix}-auth-policy"
  auth_role = "auth-role"
}