# Documentation

Written at a middle-school reading level, with grocery-store and school analogies, but
technically complete and current (September 2026: Kubernetes 1.34–1.36, Helm 4, kind 0.30,
Terraform 1.16 / AzureRM 5, Ansible 12, AKS with Cilium).

## Learning path

| # | Document | Read it when |
|---|---|---|
| 1 | [Kubernetes, explained with a grocery store](01-kubernetes-tutorial-grocery-store-edition.md) | **Start here.** Runs the demo on your laptop step by step, then explains every concept, `kubectl`, `helm`, images, network access, secrets and scaling, and every script phase by phase. |
| 2 | [The same store in the cloud: Azure with `az`](02-azure-cli-tutorial.md) | You want the identical app on AKS, with a registry, Key Vault, load balancer, and a plain VM. |
| 3 | [The store as code: Terraform](03-terraform-tutorial.md) | You want the environments (local Docker, local kind, Azure) described as code. |
| 4 | [`app.config.yaml` schema reference](04-app-config-schema-reference.md) | You are changing the one file that drives everything, or using the repo as a template. |
| 5 | [Base Linux setup: scripts, cloud-init, Ansible](05-base-linux-setup-and-ansible.md) | You need plain Linux machines configured (VM path) or want to compare the three methods. |
| 6 | [Best practices and pros & cons](06-best-practices-and-pros-cons.md) | You need to decide: kubectl vs Helm, kind vs minikube, AKS vs VM, az vs Terraform, bash vs Ansible, where secrets live, how to scale. |
| 7 | [Command cheat sheet](07-command-cheatsheet.md) | You forgot a flag. |
| 8 | [Troubleshooting](08-troubleshooting.md) | Something is red. |
| 9 | [Keycloak: 2+ replicas, exposed port](09-keycloak.md) | You want a real identity server (SSO) on the cluster with the min-2 / exposure / policy patterns applied. |
| 10 | [Developer pod for Java/C++ with SSH](10-developer-pod-ssh.md) | You want to build and debug inside the cluster from your IDE over SSH. |
| 11 | [OIDC CLI clients: Java + Go, group-based access](11-oidc-cli-clients-java-go.md) | You need a command-line tool that logs in through Keycloak and checks group membership. |
| 12 | [Prometheus + Grafana, monitoring above k8s metrics](12-monitoring-prometheus-grafana.md) | You want dashboards and alerts for Keycloak and your services, and to know what to watch beyond CPU. |

Also: [`../TEMPLATE.md`](../TEMPLATE.md) — how to turn this repo into your own project in one
command — and [`../CHANGELOG.md`](../CHANGELOG.md).

## Suggested order for a class or a self-study week

1. **Day 1** — Tutorial 1, Part 1 (run it) and Part 2 (the big ideas). Homework: change `GREETING`
   in `app.config.yaml`, redeploy, see it in the browser.
2. **Day 2** — Tutorial 1, Parts 3–5 (kubectl, Helm, images). Homework: add a third service
   (`TEMPLATE.md` §3) and make `web` call it.
3. **Day 3** — Tutorial 1, Parts 6–8 (network, secrets, scaling). Homework: block `web` from `api`
   and prove it; rotate the secret; watch the HPA under load.
4. **Day 4** — Tutorial 2 (Azure). Homework: lock the public site to your IP; find the cost in the
   Portal; destroy everything.
5. **Day 5** — Tutorials 3 and 5 (Terraform, hosts). Homework: `terraform apply` the local-docker
   root, read the plan line by line; run the Ansible playbook against the base host.
