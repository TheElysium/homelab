# Homelab

A three-node Kubernetes cluster running as virtual machines on a single Proxmox host.
Terraform creates the virtual machines and Ansible configures the hosts and cluster.
The setup is disposable so it can be rebuilt for experiments.

The cluster currently has three `Ready` nodes running Kubernetes v1.35.7. Cilium
provides the pod network and announces `LoadBalancer` addresses on the LAN. The
default `StorageClass` uses an NFS server outside the cluster. Prometheus and
Grafana collect the cluster's own metrics. PostgreSQL runs under CloudNativePG,
with its volumes on the same NFS server.

## Hardware

The entire lab runs on one machine:

| | |
|---|---|
| Machine | Dell OptiPlex 7060 |
| CPU | Intel Core i5, 8th generation |
| Memory | 16 GB |
| Storage | 238 GB NVMe SSD |
| Hypervisor | Proxmox VE 9.2.10 |

Proxmox uses LVM-thin rather than ZFS, leaving more RAM available to the virtual
machines. The resulting storage and VM sizing are described in
[docs/architecture.md](docs/architecture.md).

The Proxmox host is a single point of failure for the entire lab.

## Status

| Phase | State | What it covers |
|---|---|---|
| Hypervisor preparation | Done | Proxmox install, bridges, storage, API and SSH access for Terraform |
| Terraform — virtual machines | Done | Cloud image, per-VM cloud-init, four VMs with two NICs each |
| Ansible — `common` | Done | Timezone, base packages, `systemd-timesyncd`, internal `/etc/hosts` |
| Ansible — `nfs_server` | Done | Data disk mounted by UUID, `/srv/nfs/kubernetes` exported to `10.0.10.0/24` |
| Ansible — `kube_prereq` | Done | Swap, kernel modules, sysctl, `containerd`, `kube*` pinned and held at 1.35.7 |
| Ansible — `control_plane` | Done | `kubeadm init` on the internal network, `kube-proxy` skipped |
| Ansible — `cilium` | Done | Cilium 1.20.1 by Helm, VXLAN over `eth1`, kube-proxy replacement |
| Ansible — `worker` | Done | `kubeadm join`, both workers labelled and `Ready` |
| Ansible — `nfs_provisioner` | Done | Dynamic provisioner, `nfs-client` as the default `StorageClass` |
| Decision records | In progress | One file per decision, under `docs/decisions/` |
| `LoadBalancer` addresses | Done | Cilium LB-IPAM over `192.168.1.210`–`.220`, announced by ARP |
| Ansible — `monitoring` | Done | `kube-prometheus-stack`, Prometheus on a `local` PV, Grafana on `192.168.1.210` |
| Ansible — `postgres` | Done | CloudNativePG operator, single-instance PostgreSQL cluster on `nfs-client`, PodMonitor + Grafana storage dashboard |

## Limitations

The build does not perform Kubernetes upgrades; the packages are held. The cluster
certificates expire on **17 August 2027**. Both limitations are covered in
[docs/provisioning.md](docs/provisioning.md#maintenance-the-build-does-not-cover).

## Repository layout

```
homelab/
├── README.md
├── LICENSE                 MIT
├── .gitignore              state files, tfvars and SSH material are excluded
├── .gitattributes          LF line endings, enforced at commit time
├── .editorconfig           LF line endings, enforced in the editor
├── docs/
│   ├── architecture.md     what the system is made of
│   ├── provisioning.md     how it is built, and in which order
│   └── decisions/          architecture decision records
├── terraform/
│   ├── versions.tf         Terraform floor, provider pinned exactly
│   ├── .terraform.lock.hcl provider checksums, committed on purpose
│   ├── main.tf             cloud image, cloud-init snippets, the four VMs
│   ├── variables.tf        Proxmox endpoint and API token
│   └── terraform.tfvars.example
└── ansible/
    ├── ansible.cfg
    ├── inventory.yml       four hosts, written by hand
    ├── group_vars/         all, k8s_cluster, storage
    ├── requirements.yml    pinned Ansible collections
    ├── site.yml            nine plays, in dependency order
    ├── checks.yml          read-only verification, safe at any time
    └── roles/              common, nfs_server, kube_prereq, control_plane,
                            helm, cilium, worker, nfs_provisioner, monitoring,
                            postgres
```

## Prerequisites

Run Ansible from a Linux control machine.

Before applying Terraform, create the following manually:

- A Proxmox user `terraform@pve` with an API token, granted only the privileges the
  provider actually needs (VM lifecycle, storage allocation, bridge attachment,
  outbound download on the node).
- A dedicated unprivileged system account on the hypervisor, reachable by SSH key.
  Proxmox has no API endpoint for uploading cloud-init snippets, so the provider
  writes them to the host filesystem over SSH. The `bpg/proxmox` provider only
  accepts a PEM-formatted RSA key here, and ignores `~/.ssh/config`.
- The `local` datastore configured to accept the **Snippets** and **Import** content
  types. Without them Terraform can neither upload the cloud-init files nor download
  the cloud image, and both failures surface as storage errors that do not mention
  the missing checkbox.
- An SSH keypair for the virtual machines, stored under `~/.ssh/` and never in the
  repository. The Windows mount cannot express mode `600`, and `ssh` refuses a
  private key it considers world-readable.

There are two SSH keypairs: one for the hypervisor account and one injected into the
VMs by cloud-init.

## Building it

From WSL, create the machines first in `terraform/`:

```bash
cp terraform.tfvars.example terraform.tfvars
# fill in proxmox_endpoint and proxmox_api_token
terraform init
terraform plan
terraform apply
```

`terraform init` downloads the provider version recorded in `.terraform.lock.hcl`.
The lock file is committed so the provider and its checksums are reproducible.
`terraform apply` downloads the Debian 13 cloud image onto the hypervisor, writes one
cloud-init snippet per machine, and creates the four VMs.

The first apply takes a few minutes, mostly for the image download and for the QEMU
guest agent to report an address on each new machine.

Then configure the cluster in `ansible/`:

```bash
ansible-playbook checks.yml
ansible-playbook site.yml
```

`checks.yml` is read-only and can be run before or after provisioning. `site.yml` is
idempotent: a second run on a healthy cluster reports `changed=0` on every host.

## Documentation

- [docs/architecture.md](docs/architecture.md) — the layers, the four machines, the
  two networks, the address plan, the sizing, and what runs inside the cluster.
- [docs/provisioning.md](docs/provisioning.md) — how the system is built: the manual
  prerequisites, what Terraform does, the eight Ansible plays and why they are in
  that order.
- [docs/decisions/](docs/decisions/) — architecture decision records: why things are
  the way they are, one decision per file.
