# Command Cheat Sheet

*All commands assume the project name `python-demo` and namespace `python-demo`. Replace as needed.*

## This project

```bash
make help                                  # list every make target
make validate | show | render              # check / summarise / render app.config.yaml
python3 tools/appconfig.py get name        # one value (also: get targets.azure.location)
make new-project NAME=my-shop DEST=../my-shop

./scripts/run-all.sh                       # local kind: phases 0–5           (make up)
./scripts/06-port-forward.sh               # http://localhost:8080             (make open)
./scripts/07-scale.sh manual web 4 | load 60 | watch
./scripts/08-secrets.sh show | rotate NEWVALUE
./scripts/09-network.sh show | test | off | on
./scripts/10-cleanup-apps.sh  ./scripts/99-destroy.sh

./scripts/azure/run-all.sh                 # full Azure path                   (make az-up)
./scripts/azure/07-scale.sh pods web 4 | nodes 3 | autoscaler 1 5 | load 90 | status
./scripts/azure/08-secrets.sh create | set API_TOKEN v | deploy | csi
./scripts/azure/09-network.sh policies | nsg | lock-to-me | unlock
./scripts/azure/10-create-vm.sh  ./scripts/azure/11-run-ansible.sh  ./scripts/azure/12-status.sh  ./scripts/azure/99-destroy.sh

make compose-up | compose-down             # web + api on plain docker compose
make tf-local-docker | tf-local-kind | tf-azure | tf-destroy-<root>
make lint                                  # shellcheck, helm lint, kubeconform, ansible-lint, terraform fmt
```

## kubectl

```bash
# context
kubectl config current-context / get-contexts / use-context kind-python-demo
# look
kubectl get nodes -o wide
kubectl -n python-demo get all,hpa,netpol,cm,secret
kubectl -n python-demo get pods -o wide -w
kubectl -n python-demo get pod <pod> -o yaml | less
kubectl -n python-demo describe pod <pod>                 # events at the bottom
kubectl -n python-demo get events --sort-by=.metadata.creationTimestamp
kubectl -n python-demo logs deploy/python-demo-api -f --tail=100 [--previous]
kubectl -n python-demo top pods / kubectl top nodes
kubectl -n python-demo get endpoints python-demo-web
kubectl -n python-demo get pods -l app.kubernetes.io/component=api
# touch
kubectl apply -f k8s/  |  kubectl delete -f k8s/
kubectl -n python-demo exec -it deploy/python-demo-web -- sh
kubectl -n python-demo port-forward svc/python-demo-web 8080:80
kubectl -n python-demo scale deploy/python-demo-web --replicas=3
kubectl -n python-demo rollout status|history|restart|undo deploy/python-demo-api
kubectl -n python-demo set image deploy/python-demo-api api=python-demo-api:1.0.1
kubectl -n python-demo run t --rm -it --restart=Never --image=curlimages/curl -- curl -m5 http://python-demo-api/health
kubectl -n python-demo create secret generic x --from-env-file=secrets.env --dry-run=client -o yaml
kubectl -n python-demo delete pod <pod>                   # the Deployment replaces it
kubectl delete namespace python-demo
# learn
kubectl explain deployment.spec.template.spec.containers.resources
kubectl api-resources | kubectl api-versions
```

## helm (v4)

```bash
helm version
helm lint helm/python-demo -f build/helm-values.yaml
helm template python-demo helm/python-demo -f build/helm-values.yaml [--debug]
helm upgrade --install python-demo helm/python-demo -n python-demo --create-namespace \
     -f build/helm-values.yaml -f build/secrets-values.yaml --set publicServiceType=LoadBalancer \
     --wait --timeout 5m [--rollback-on-failure] [--dry-run]
helm list -A  |  helm status python-demo -n python-demo
helm get values|manifest|notes python-demo -n python-demo
helm history python-demo -n python-demo  |  helm rollback python-demo 2 -n python-demo
helm test python-demo -n python-demo --logs
helm uninstall python-demo -n python-demo
helm repo add metrics-server https://kubernetes-sigs.github.io/metrics-server/  && helm repo update
helm install metrics-server metrics-server/metrics-server -n kube-system --set 'args[0]=--kubelet-insecure-tls'
helm package helm/python-demo  |  helm push python-demo-0.2.0.tgz oci://<acr>.azurecr.io/charts
# Helm 4 renames: --atomic → --rollback-on-failure, --force → --force-replace
```

## kind / docker

```bash
kind create cluster --name python-demo --config kind-config.yaml
kind get clusters  |  kind get nodes --name python-demo
kind load docker-image python-demo-web:1.0.0 --name python-demo
kind delete cluster --name python-demo
docker build --pull -t python-demo-web:1.0.0 apps/web
docker run --rm -p 8080:8080 -e GREETING=hi python-demo-web:1.0.0
docker ps  |  docker logs -f python-demo-web  |  docker exec -it python-demo-host bash
docker network create python-demo  |  docker network inspect python-demo
docker compose -f build/docker-compose.yaml --project-directory . up --build -d
docker image ls | grep python-demo  |  docker image prune
```

## az

```bash
az login [--use-device-code]  |  az account show  |  az account set --subscription <name>
az group create -n rg-python-demo -l eastus  |  az group delete -n rg-python-demo --yes --no-wait
az acr create -g rg -n <acr> --sku Basic --admin-enabled false
az acr build --registry <acr> --image python-demo-web:1.0.0 --platform linux/amd64 apps/web
az acr repository list -n <acr>  |  az acr repository show-tags -n <acr> --repository python-demo-web
az acr login -n <acr>                                      # for local docker push (3h token)
az aks get-versions -l eastus -o table
az aks create -g rg -n aks-python-demo --tier free --node-vm-size Standard_B2ms --node-count 2 \
   --enable-cluster-autoscaler --min-count 1 --max-count 3 \
   --network-plugin azure --network-plugin-mode overlay --network-dataplane cilium --network-policy cilium \
   --attach-acr <acr> --enable-oidc-issuer --enable-workload-identity \
   --enable-addons azure-keyvault-secrets-provider --generate-ssh-keys
az aks get-credentials -g rg -n aks-python-demo --overwrite-existing
az aks show -g rg -n aks-python-demo --query '{v:kubernetesVersion,policy:networkProfile.networkPolicy}'
az aks nodepool list -g rg --cluster-name aks-python-demo -o table
az aks update -g rg -n aks-python-demo --update-cluster-autoscaler --min-count 1 --max-count 5
az aks scale -g rg -n aks-python-demo --node-count 3            # autoscaler off only
az aks stop|start -g rg -n aks-python-demo                       # pause billing for nodes
az aks upgrade -g rg -n aks-python-demo --kubernetes-version 1.36.x
az aks command invoke -g rg -n aks-python-demo --command "kubectl get pods -A"
az keyvault create -n <kv> -g rg -l eastus --enable-rbac-authorization true
az keyvault secret set --vault-name <kv> -n API-TOKEN --value s3cret
az keyvault secret show --vault-name <kv> -n API-TOKEN --query value -o tsv
az role assignment create --role AcrPull --assignee-object-id <id> --assignee-principal-type ServicePrincipal --scope <acr id>
az vm create -g rg -n vm-python-demo --image Ubuntu2404 --size Standard_B1s --admin-username azureuser \
   --generate-ssh-keys --assign-identity '[system]' --public-ip-sku Standard --nsg-rule NONE --custom-data build/cloud-init.yaml
az vm open-port -g rg -n vm-python-demo --port 80 --priority 1010
az vm show -d -g rg -n vm-python-demo --query publicIps -o tsv
az vm run-command invoke -g rg -n vm-python-demo --command-id RunShellScript --scripts 'docker ps'
az network nsg rule list -g <node rg> --nsg-name <nsg> -o table --include-default
az resource list -g rg -o table  |  az provider register --namespace Microsoft.ContainerService --wait
```

## terraform / tofu

```bash
terraform init [-upgrade]  |  terraform fmt -recursive  |  terraform validate
terraform plan [-var-file=prod.tfvars] [-out=plan.tfplan]  |  terraform apply [plan.tfplan] [-auto-approve]
terraform output [-raw name] [-json]
terraform state list  |  terraform state show <addr>  |  terraform state mv|rm
terraform import <addr> <id>
terraform destroy [-target=<addr>]
terraform providers  |  terraform providers lock -platform=linux_amd64
export TF_VAR_secrets='{"API_TOKEN":"x"}'  ARM_SUBSCRIPTION_ID=...  TF_LOG=DEBUG
```

## ansible

```bash
ansible-galaxy collection install -r requirements.yml
ansible-inventory -i inventory/azure.ini --list
ansible -i inventory/azure.ini app_hosts -m ping
ansible-playbook -i inventory/azure.ini site.yml [-e image_registry=<acr>] [--check --diff] [-v|-vvv] [--limit vm-python-demo] [--tags x]
ansible-lint --offline site.yml
ansible-doc community.docker.docker_container
```

## Debug one-liners

```bash
kubectl -n python-demo get pods -o custom-columns=NAME:.metadata.name,NODE:.spec.nodeName,IP:.status.podIP,READY:.status.containerStatuses[0].ready
kubectl -n python-demo get svc python-demo-web -o jsonpath='{.status.loadBalancer.ingress[0].ip}'
kubectl -n python-demo get hpa -w
kubectl -n python-demo describe netpol
kubectl get --raw /apis/metrics.k8s.io/v1beta1/nodes | jq .
echo Y2hhbmdlLW1l | base64 -d          # decode a Secret value
curl -s localhost:8080/api-config | jq .
```
