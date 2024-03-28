# Secret Injection Sampler

This is a sampling of mechanisms for injecting secrets into a container. The techniques
include Vault agent, Secrets Storage CSI driver and K8s Secrets.

## Prerequisites

```shell
brew install colima kubernetes-cli terraform vault
```

## Setup

```shell
alias k=kubectl

# run the server in a separate shell
vault server -dev -dev-root-token-id root -dev-listen-address 0.0.0.0:8200

colima start -c 6 -m 16 -k

terraform init --upgrade
terraform apply -auto-approve -compact-warnings
```

## Inspection

Run a shell in the `busybox` container to inspect the various mounts and environment variables.

```shell
k exec -it deploy/busybox -- sh
env | grep CSI_SECRET
ls -al /home/nonroot
cat /home/nonroot/config && echo
cat /home/nonroot/token && echo
ls -al /mnt/secret
cat /mnt/secret/url && echo
cat /mnt/secret-subpath && echo
ls -al /mnt/csi
cat /mnt/csi/username && echo
cat /mnt/csi/password && echo
```

## Secret Rotation

Use the `vault` & `kubectl` to inspect and modify the various secrets.

```shell
export VAULT_ADDR='http://0.0.0.0:8200'
vault login root

# update the Vault secret
vault kv put secret/example/config username='helloUser' password='helloSecret' ttl='30s'

# update the Secret
k create secret generic example-secret --save-config --dry-run=client --from-literal url='mongodb://new-user:new-pass@some.mongodb.server' -o yaml | k apply -f -

# inspect the Secret
k get secret example-secret -o jsonpath='{.data.url}' | base64 -d

# inspect the CSI generated Secret
k get secret csi-secret -o jsonpath='{.data.password}' | base64 -d

# inspect the current CSI secret version loaded in the pod mount
k get secretproviderclasspodstatus -o json | jq -r '.items[] | select(.metadata.name | test("busybox-"))'
k get secretproviderclasspodstatus -o json | jq -r '.items[] | select(.metadata.name | test("busybox-")).metadata.generation'

# inspect
vault read auth/kubernetes/config
vault kv get secret/example/config
vault policy list
vault policy read example-policy
vault list auth/kubernetes/role
vault read auth/kubernetes/role/example-role
```

## Cleanup

```shell
terraform apply -destroy -auto-approve -compact-warnings
k delete crd --all
colima delete -f
rm -rf .terraform* terraform*
```

## Dev Notes

Random commands useful during the development of the examples.

```shell
# example of Vault login using a ServiceAccount token
http POST :8200/v1/auth/kubernetes/login jwt=$(k create token vault-auth) role=example

# examples of getting the cluster CA and server address for cluster "colima"
k config view --raw -o json | jq -r '.clusters[] | select(.name=="colima") | .cluster."certificate-authority-data"'
k config view --raw -o jsonpath='{.clusters[?(@.name=="colima")].cluster.certificate-authority-data}' | base64 -d
k config view --raw -o jsonpath='{.clusters[?(@.name=="colima")].cluster.server}'

# check for ServiceProviderClass CRD
k --kubeconfig ~/.kube/config get crd secretproviderclasses.secrets-store.csi.x-k8s.io --ignore-not-found -o jsonpath='{.status.conditions[?(@.type=="NamesAccepted")].reason}'
```

## References

- <https://developer.hashicorp.com/vault/docs/platform/k8s/injector/annotations>
- <https://secrets-store-csi-driver.sigs.k8s.io/>
- <https://registry.terraform.io/providers/gavinbunney/kubectl/>
- <https://piotrminkowski.com/2023/03/20/vault-with-secrets-store-csi-driver-on-kubernetes/>
- <https://github.com/piomin/terraform-local-k8s/>
- <https://github.com/hashicorp/vault-secrets-operator/blob/main/demo/infra/app/auth.tf>
- <https://github.com/thoughtbot/flightdeck/blob/main/aws/secret-provider-class/main.tf>
- <https://github.com/escaletech/terraform-modules/blob/master/modules/app-deploy/secrets.tf>
- <https://github.com/GoogleCloudPlatform/cloud-foundation-fabric/blob/master/blueprints/gke/patterns/redis-cluster/main.tf>
- <https://github.com/hashicorp/terraform-provider-kubernetes/issues/1367>
