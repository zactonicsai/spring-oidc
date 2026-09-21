# Setting Up Base Linux Machines: Scripts, cloud-init and Ansible

*Not everything is Kubernetes. Sometimes you need one plain Linux server — a delivery truck
instead of a whole store. This project configures such hosts **from the same `app.config.yaml`**
three ways: bash scripts (`setup/`), cloud-init (renders those scripts into a first-boot file),
and an Ansible role. All three produce the same result, so you can compare them side by side.
Ubuntu 24.04 LTS, Docker Engine 28, Ansible core 2.19 / ansible 12, current as of September 2026.*

| Part | What you learn |
|---|---|
| [1](#part-1--step-by-step) | Run the three methods locally (docker "host" container) and on an Azure VM |
| [2](#part-2--what-a-host-gets) | The exact things that are configured and where they end up |
| [3](#part-3--the-bash-scripts-setupsetupsh--setupconfiguresh) | `setup.sh` and `configure.sh` line by line |
| [4](#part-4--cloud-init) | How the scripts travel to an Azure VM |
| [5](#part-5--ansible) | The `base-linux` role, task by task, and how it reads the schema |
| [6](#part-6--bring-your-own-scripts) | Replacing the scripts with your own, keeping every path working |
| [7](#part-7--best-practices) | Idempotence, identities over passwords, checksums, firewalls |
| [8](#part-8--pros-and-cons) | bash vs cloud-init vs Ansible vs golden images |

---

## Part 1 — Step by step

### Locally, in a docker "host" container (no cloud account)

```bash
cd terraform/local-docker && terraform init && terraform apply     # starts ubuntu:24.04 as python-demo-host
docker exec -it python-demo-host bash
  cat /etc/python-demo/config.env                                   # settings from hosts.settings
  ls -la /etc/python-demo/downloaded/                               # sources.files downloaded
  id azureuser                                                      # hosts.adminUser created
  docker --version                                                  # Docker CLI installed (no daemon in a container)
  exit
cd ../.. && terraform -chdir=terraform/local-docker apply -var run_ansible=true   # same host, now via Ansible: mostly "ok"
```

(`ufw` and running containers are skipped inside a container — no `NET_ADMIN`, no daemon.
Set `mount_docker_socket = true` to let `configure.sh` start the app containers on your Docker.)

### On an Azure VM

```bash
./scripts/azure/00-login.sh && ./scripts/azure/01-create-resources.sh && ./scripts/azure/02-build-push-images.sh
./scripts/azure/10-create-vm.sh                # cloud-init runs setup.sh + configure.sh at first boot
ssh azureuser@<ip> sudo tail -f /var/log/cloud-init-output.log     # watch it (≈ 3 min)
curl http://<ip>/                              # the web app, running as a docker container on the VM
./scripts/azure/11-run-ansible.sh              # re-configure with Ansible: everything reports ok/unchanged
```

Terraform does the same: `terraform/azure` with `create_vm = true` (default from the config)
and optionally `run_ansible = true`.

### On any Ubuntu/Debian box you already have

```bash
python3 tools/appconfig.py render host        # build/host-config.env, host-files.tsv, env/*.env
scp -r build/host-config.env build/host-files.tsv build/env setup/*.sh user@box:/opt/python-demo/
ssh user@box 'cd /opt/python-demo && sudo bash setup.sh && sudo bash configure.sh'
```

---

## Part 2 — What a host gets

| Step | From `app.config.yaml` | Result on the host | bash | cloud-init | Ansible |
|---|---|---|---|---|---|
| packages | `hosts.packages` | `apt-get install curl git jq ufw …` | setup.sh §1 | `packages:` + setup.sh | `apt` |
| Docker | — | Docker Engine from Docker's apt repo (CLI only inside a container) | setup.sh §2 | via setup.sh | `deb822_repository` + `apt` |
| firewall | `hosts.exposePorts` | `ufw default deny incoming; allow 22/tcp, 80/tcp` (+ Azure NSG rules) | setup.sh §3 | via setup.sh | `community.general.ufw` |
| admin user | `hosts.adminUser` | user exists, in `docker` group | setup.sh §4 | via setup.sh | `user` |
| timezone | `hosts.settings.TIMEZONE` | `timedatectl set-timezone` | setup.sh §5 | via setup.sh | `community.general.timezone` |
| files | `sources.files[]` | downloaded to `dest`, sha256 verified, mode set | configure.sh §1 | via configure.sh | `get_url` (checksum) |
| settings | `hosts.settings` | `/etc/<name>/config.env` (`KEY=value`) | configure.sh §2 | via configure.sh | `template` |
| containers | `services[]`, `sources.imageRegistry` | `docker network <name>`; one container per service; only `public` ports published; ACR login via managed identity | configure.sh §3 | via configure.sh | `docker_login/_network/_container` |
| markers | — | `/var/lib/<name>/setup.done`, `configure.done` | ✓ | ✓ | (Ansible is idempotent by nature) |

The inputs are three small generated files (never edit them by hand — edit the YAML):

```
host-config.env   APP_NAME, APP_VERSION, IMAGE_REGISTRY, ADMIN_USER, PACKAGES, EXPOSE_PORTS,
                  SERVICES, SERVICE_<SVC>_{IMAGE,HOST_PORT,CONTAINER_PORT,EXPOSE}, SETTING_<KEY>
host-files.tsv    name <TAB> url <TAB> dest <TAB> mode <TAB> sha256-or-dash
env/<svc>.env     docker --env-file per service: APP_NAME, SERVICE_NAME, APP_VERSION + services[].config
```

`tools/appconfig.py render host` writes them; Terraform's `app-config` module produces
byte-identical content (`host_config_env`, `host_files_tsv`, `host_service_envs`).

---

## Part 3 — The bash scripts: `setup/setup.sh` + `setup/configure.sh`

Both are **idempotent** (safe to re-run), run as root, `set -euo pipefail`, and pass
`shellcheck`. They take their inputs from the same folder (or `HOST_CONFIG=` / `HOST_FILES=`).

### `setup.sh` — the machine

1. **Packages** — `apt-get update && apt-get install -y $PACKAGES` (non-interactive).
2. **Docker** — adds Docker's official apt repository with its GPG key (`/etc/apt/keyrings/docker.asc`,
   `signed-by=`), installs `docker-ce docker-ce-cli containerd.io docker-buildx-plugin
   docker-compose-plugin`, enables the service. Inside a container (detected via `/.dockerenv`
   or cgroups) it installs the CLI only. Skips everything if `docker` already exists.
3. **Firewall** — `ufw --force reset; default deny incoming; default allow outgoing; allow <port>/<proto>`
   for each `EXPOSE_PORTS` entry; `ufw --force enable`. Skipped in containers.
4. **Admin user** — `useradd -m -s /bin/bash` if missing; `usermod -aG docker` if the group exists.
5. **Timezone** — `timedatectl set-timezone` (or the `/etc/localtime` symlink without systemd).
6. **Marker** — `/var/lib/<app>/setup.done`.

### `configure.sh` — the application

1. **Files** — for each TSV line: `curl -fsSL --retry 3` to a temp file, `sha256sum -c` if a checksum
   is given (mismatch → *not installed*), `install -m <mode>` to `dest`.
2. **Settings** — writes `/etc/<app>/config.env` from every `SETTING_*` variable (mode 0640).
3. **Containers** (only if `SETTING_RUN_DEMO_CONTAINERS=true` and the Docker daemon answers):
   * if the registry is `*.azurecr.io`: **`acr_login_managed_identity`** — asks the Azure
     Instance Metadata Service (`169.254.169.254`) for an AAD token for the VM's identity, POSTs it
     to `https://<acr>/oauth2/exchange` for an ACR refresh token, and runs `docker login` with the
     well-known username `00000000-0000-0000-0000-000000000000`. **No password exists anywhere.**
     Requires the VM identity to have `AcrPull` (phase 10 / Terraform assign it).
   * `docker network create <app>`; per service: `docker pull` (or check a local image), then
     `docker run -d --restart unless-stopped --name <app>-<svc> --network <app> --network-alias <app>-<svc>
     --env-file env/<svc>.env [--env-file secrets.env] [-p <servicePort>:<containerPort>] <image>`.
     Only `expose: public` services get `-p`. The network alias equals the Kubernetes Service name,
     so `API_URL=http://python-demo-api` works unchanged.
4. **Marker** — `/var/lib/<app>/configure.done`.

Both scripts were executed during development (downloads, settings, user creation verified);
the Docker/ufw steps run only on a real host.

---

## Part 4 — cloud-init

**cloud-init** is the standard first-boot agent in cloud Linux images. `tools/appconfig.py render
cloudinit` produces `build/cloud-init.yaml`:

```yaml
#cloud-config
package_update: true
packages: [curl, ca-certificates, git, jq, ufw, unzip, python3]
write_files:                                   # base64-encoded, so any content is safe
  - { path: /opt/python-demo/host-config.env, permissions: "0640", encoding: b64, content: ... }
  - { path: /opt/python-demo/host-files.tsv,  permissions: "0640", encoding: b64, content: ... }
  - { path: /opt/python-demo/setup.sh,        permissions: "0750", encoding: b64, content: ... }
  - { path: /opt/python-demo/configure.sh,    permissions: "0750", encoding: b64, content: ... }
  - { path: /opt/python-demo/env/web.env, ... }
  - { path: /opt/python-demo/env/api.env, ... }
runcmd:
  - bash /opt/python-demo/setup.sh 2>&1 | tee -a /var/log/python-demo-setup.log
  - bash /opt/python-demo/configure.sh 2>&1 | tee -a /var/log/python-demo-configure.log
final_message: "python-demo host setup finished after $UPTIME seconds"
```

`az vm create --custom-data build/cloud-init.yaml` (or Terraform `custom_data =
base64encode(local.cloud_init)`) hands it to the VM. Azure's limit is 64 KB; ours is ≈ 15 KB.
Debug on the VM: `cloud-init status --long`, `/var/log/cloud-init-output.log`,
`sudo cloud-init clean && sudo reboot` to re-run.

cloud-init runs **once**. To change settings later, re-run the scripts (`az vm run-command invoke
… --scripts 'bash /opt/python-demo/configure.sh'`) or use Ansible.

---

## Part 5 — Ansible

**Ansible** is an agentless configuration tool: it SSHes into hosts (or `docker exec`s into
containers) and runs *modules* that are idempotent by design — `apt: name=curl state=present`
installs only if missing and reports `ok` otherwise.

```
ansible/
├── ansible.cfg                  # inventory default, roles path, yaml result format, pipelining
├── requirements.yml             # community.docker, community.general, ansible.posix
├── inventory/example.ini        # copy to azure.ini / local-docker.ini (generated by scripts/terraform)
├── site.yml                     # loads app.config.yaml, derives facts, applies the role
└── roles/base-linux/
    ├── defaults/main.yml        # run_demo_containers (from hosts.settings), docker package list
    ├── tasks/main.yml           # packages → docker → ufw → user → timezone → files → settings → containers
    ├── tasks/docker.yml         # deb822_repository (modern apt sources) + apt
    ├── tasks/files.yml          # get_url with checksum, retries
    ├── tasks/containers.yml     # IMDS → ACR token → docker_login; docker_network; docker_container per service
    ├── templates/config.env.j2  # /etc/<app>/config.env
    └── handlers/main.yml        # restart docker
```

### How it reads the schema

```yaml
- ansible.builtin.include_vars: { file: "{{ playbook_dir }}/../app.config.yaml", name: appcfg }
- ansible.builtin.set_fact:
    app_name: "{{ appcfg.metadata.name }}"
    registry: "{{ image_registry if image_registry else (appcfg.sources.imageRegistry | default('')) }}"
    hostcfg:  "{{ appcfg.hosts | default({}) }}"
    in_container: "{{ ansible_facts.virtualization_type in ['docker','container','containerd','podman'] and ansible_facts.virtualization_role == 'guest' }}"
```

Then tasks loop over the data: `loop: "{{ hostcfg.exposePorts }}"` for ufw,
`loop: "{{ appcfg.sources.files }}"` for downloads (`dest | replace('${name}', app_name)` expands
the placeholder), `loop: "{{ appcfg.services }}"` for containers. Secrets come from
`secrets.env` on the controller (parsed with Jinja into a dict) and only the keys a service
declares are injected into its container.

### Running it

```bash
cd ansible
ansible-galaxy collection install -r requirements.yml
ansible-playbook -i inventory/azure.ini site.yml -e image_registry=myacr.azurecr.io
ansible-playbook -i inventory/azure.ini site.yml --check --diff          # dry run
ansible-lint --offline site.yml                                          # passes the "production" profile
```

Inventory examples (generated for you by `11-run-ansible.sh` and both Terraform roots):

```ini
[app_hosts]
vm-python-demo   ansible_host=20.1.2.3 ansible_user=azureuser
python-demo-host ansible_connection=community.docker.docker      # a local container, no SSH
```

---

## Part 6 — Bring your own scripts

The contract is small on purpose:

1. Point `hosts.setupScript` and `hosts.configureScript` at your files (paths relative to the repo root).
   `make validate` checks they exist.
2. Your scripts receive `host-config.env` next to them (or at `$HOST_CONFIG`) — `source` it and use
   `APP_NAME`, `PACKAGES`, `EXPOSE_PORTS`, `SERVICES`, `SERVICE_<SVC>_IMAGE`, `SETTING_<KEY>` — plus
   `host-files.tsv` and `env/<svc>.env`.
3. Keep them **idempotent** and **root-safe**; exit non-zero on failure so cloud-init and
   Terraform report it.
4. That's it: cloud-init (`render cloudinit`), Terraform (`local-docker` base host, `azure` VM) and
   `10-create-vm.sh` all embed *whatever files those two fields point at*.

Need extra inputs? Add keys under `hosts.settings` — they arrive as `SETTING_<KEY>` and in
`/etc/<app>/config.env` with no other changes. Need extra files? Add `sources.files[]` entries.

To customise the Ansible side, edit `roles/base-linux/tasks/*.yml` or add a role in `site.yml`;
the schema is already loaded as `appcfg`.

---

## Part 7 — Best practices

* **Idempotence first.** Every step must be safe to repeat: check-then-change (`command -v docker`,
  `id user`, markers) in bash; Ansible modules do it for you.
* **Identities, not passwords.** The VM pulls from ACR with its managed identity. Never bake registry
  passwords, SSH private keys or tokens into cloud-init (it's visible in the VM's metadata and logs).
* **Verify downloads.** Fill in `sources.files[].sha256` for anything you execute or trust;
  `configure.sh` refuses mismatches, `get_url` too.
* **Least-open firewall.** `ufw default deny incoming` + only `hosts.exposePorts`; mirror it in the
  NSG; set `source: YOUR_IP/32` for SSH. Consider Azure Bastion or SSH over a VPN instead of port 22.
* **Non-root containers, read-only where possible, `--restart unless-stopped`.** The same hardening the
  pods use; add `--read-only --tmpfs /tmp` in your own scripts if you don't need writable roots.
* **Log everything to files** (`tee -a /var/log/<app>-*.log`) so first-boot failures are diagnosable.
* **Unattended upgrades** on real hosts (`unattended-upgrades` package) and periodic image
  rebuilds; a VM configured once and forgotten is the classic security hole.
* **Prefer immutable images for fleets**: bake a golden image (Packer) from the same scripts, then
  cloud-init only writes settings. For one demo box, scripts on first boot are fine.

---

## Part 8 — Pros and cons

| | bash scripts (`setup/`) | cloud-init | Ansible | golden image (Packer) |
|---|---|---|---|---|
| Runs when | whenever you call them | first boot only | whenever you run the playbook | build time; boot is instant |
| Needs on the host | bash, curl | nothing (built into cloud images) | python3 + SSH | nothing |
| Needs on your laptop | ssh/scp | nothing (the cloud delivers it) | ansible | packer + a build pipeline |
| Idempotence | you write the checks | delegates to your scripts | built into modules | n/a (rebuild image) |
| Readability | high for small tasks | YAML wrapper around the scripts | high, declarative, self-documenting | depends on the provisioner |
| Multi-host / fleets | loops over ssh — clumsy | per-VM at boot | excellent (inventory, groups, parallel) | excellent (many VMs from one image) |
| Dry run / diff | no | no | `--check --diff` | no |
| Debugging | `bash -x`, logs | `/var/log/cloud-init-output.log` | verbose output per task | image builds are slow to iterate |
| Secrets handling | env files | visible in metadata — avoid | vault (`ansible-vault`), lookups | baked in — avoid |
| Best for | one host, learning, bootstrap | cloud VMs at creation | ongoing configuration, many hosts | large fleets, fast autoscaling |

The layered answer most teams end up with: **cloud-init or a golden image to bootstrap, Ansible
(or your platform's agent) to keep hosts converged, containers for the application itself** —
and Kubernetes once you have more than a couple of services.
