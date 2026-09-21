# AKS + Keycloak OIDC lab

Terraform stack that provisions an Azure Kubernetes Service cluster and deploys:

- **Keycloak 26.7.4** (official image) with a preloaded `demo` realm
- **PostgreSQL 16** as Keycloak's database (in-cluster, official image)
- **ingress-nginx** with nip.io hostnames
- Example **Java 27** OIDC resource-server pod
- Example **Golang** OIDC resource-server pod
- A **developer SSH workstation** with JDK 27, Maven, Gradle, C++ toolchains, and Go

This is a lab / inner-loop environment, not a hardened production design. HTTP is used on the public ingress so you can bring it up without certificates.

## Architecture

```
                    Azure LoadBalancer
                            |
                      ingress-nginx
                     /      |       \
            keycloak     java-oidc   golang-oidc
         <ip>.nip.io   java.<ip>.nip.io  go.<ip>.nip.io
                    \
                     postgres (PVC)
workspace/devbox  -- SSH via kubectl port-forward
```

In-cluster apps talk to Keycloak at:

`http://keycloak.identity.svc.cluster.local:8080/realms/demo`

## Prerequisites

- Azure CLI logged in (`az login`) with permission to create resource groups, AKS, ACR, and role assignments
- Terraform >= 1.6
- kubectl
- Optional: Docker / `az acr build` if you want the baked devbox image

## Deploy

```bash
cp terraform.tfvars.example terraform.tfvars
# edit name_prefix / location / ssh keys

terraform init
terraform apply
terraform output
terraform output -raw keycloak_admin_password
az aks get-credentials -g "$(terraform output -raw resource_group_name)" -n "$(terraform output -raw aks_name)"
```

First apply takes 15–25 minutes (AKS + node pull of Keycloak / Corretto / Go images).

If the ingress IP was not ready, `keycloak_public_url` may show `http://keycloak.local`. Wait for the controller Service to get an external IP and re-run `terraform apply`.

## What gets created in Keycloak

Realm **`demo`** is imported on first start (`--import-realm`).

| Client | Type | Purpose |
| --- | --- | --- |
| `java-oidc` | confidential | Java example app (auth code + client credentials) |
| `golang-oidc` | confidential | Go example app |
| `public-web` | public + PKCE | Browser / CLI experiments |
| `svc-client-credentials` | confidential, service account only | Machine-to-machine |

Users (same generated password, see `terraform output demo_users`):

- `developer` — roles `user`, `developer`
- `adminuser` — roles `user`, `admin`

Master-realm admin is `admin` / `keycloak_admin_password`.

## Exercise the OIDC clients

```bash
chmod +x scripts/*.sh
./scripts/oidc-token.sh java-oidc
TOKEN=$(./scripts/oidc-token.sh java-oidc | python3 -c 'import json,sys; print(json.load(sys.stdin)["access_token"])')

curl -sH "Authorization: Bearer $TOKEN" "$(terraform output -raw java_app_url)/protected"
curl -s "$(terraform output -raw java_app_url)/client-credentials"

TOKEN=$(./scripts/oidc-token.sh golang-oidc | python3 -c 'import json,sys; print(json.load(sys.stdin)["access_token"])')
curl -sH "Authorization: Bearer $TOKEN" "$(terraform output -raw golang_app_url)/protected"
```

Admin console: `terraform output -raw keycloak_public_url`

## Developer SSH pod

Default image is `ubuntu:24.04`. On first start the pod runs `apps/devbox/bootstrap.sh` and installs:

- Amazon Corretto **JDK 27** (falls back to 25 if the package is not on the mirror)
- Maven 3.9 and Gradle 9.1
- GCC / Clang / CMake / GDB
- Go 1.25
- OpenSSH

That first boot takes several minutes. For a faster, repeatable workstation, build the Dockerfile into ACR:

```bash
./scripts/build-devbox.sh
# then set devbox_image = "<acr>.azurecr.io/devbox:27" and terraform apply
```

Connect:

```bash
kubectl -n workspace port-forward svc/devbox 2222:22
# password from: terraform output -json devbox_ssh
ssh -p 2222 dev@127.0.0.1
```

Prefer putting your laptop key in `devbox_ssh_authorized_keys`. Home directory is on a 32Gi PVC.

To expose SSH on a public LoadBalancer (not recommended on the open internet):

```hcl
devbox_service_type = "LoadBalancer"
```

## Layout

```
versions.tf / providers.tf / variables.tf / locals.tf
main.tf            Azure RG, VNet, AKS, ACR, Log Analytics
secrets.tf         generated passwords
ingress.tf         ingress-nginx + public hostname
postgres.tf        Keycloak database
keycloak.tf        Keycloak + realm import
apps.tf            Java and Go example Deployments
devbox.tf          SSH workstation
k8s/demo-realm.json.tftpl
apps/java-oidc/App.java
apps/golang-oidc/main.go
apps/devbox/Dockerfile
apps/devbox/bootstrap.sh
```

## Images and versions

| Component | Default |
| --- | --- |
| Keycloak | `quay.io/keycloak/keycloak:26.7.4` |
| PostgreSQL | `postgres:16-alpine` |
| Java runtime | `amazoncorretto:27` |
| Go runtime | `golang:1.25` |
| ingress-nginx chart | 4.12.3 |
| AKS networking | Azure CNI Overlay + Azure Network Policy |

If `amazoncorretto:27` is not yet in Docker Hub in your region, set `java_runtime_image = "amazoncorretto:25"`.

## Notes and limits

- Keycloak runs `start-dev` so hostname checks stay relaxed for nip.io. Switch to `start` + TLS before any real traffic.
- Realm import only happens when the realm does not already exist. Changing the JSON later does not rewrite the DB; delete the Keycloak PVC/database or use the admin API.
- Example apps decode the JWT payload and call Keycloak userinfo. They are teaching samples, not a full JOSE stack.
- Estimated Azure spend is roughly a few dollars per hour with 3 × `Standard_D2s_v5`. Destroy when idle.

## Destroy

```bash
terraform destroy
```
