# Homelab

A three-node Kubernetes cluster, virtualised on a single Proxmox host, built to be
learned rather than merely used. Everything is provisioned declaratively so the
cluster can be destroyed and rebuilt without hesitation — that is the condition for
experimenting freely with it.

The cluster is up: three nodes `Ready` on Kubernetes v1.35.7, Cilium carrying the
pod network and announcing `LoadBalancer` addresses on the LAN, and a default
`StorageClass` backed by an NFS server that lives outside the cluster. There is no
application workload in it yet.

## Hardware

One machine, and no plan for a second one:

| | |
|---|---|
| Machine | Dell OptiPlex 7060 |
| CPU | Intel Core i5, 8th generation |
| Memory | 16 GB |
| Storage | 238 GB NVMe SSD |
| Hypervisor | Proxmox VE 9.2.10 |

Proxmox is installed on LVM-thin rather than ZFS, which keeps several gigabytes of
RAM out of a filesystem cache and available to the virtual machines. The consequences
of that choice, and the sizing it allows, are described in
[docs/architecture.md](docs/architecture.md).

A single host means a single point of failure for everything. Nothing in this design
pretends otherwise.

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
| Observability | Not started | Deliberately deferred — there is no memory budget for it yet |

Two things the build does not do, and will not start doing on its own:
Kubernetes upgrades are blocked by design (the packages are held), and the cluster
certificates expire on **17 August 2027**. Both are covered in
[docs/provisioning.md](docs/provisioning.md#maintenance-the-build-does-not-cover).

## Repository layout

```
homelab/
├── README.md
├── .gitignore              state files, tfvars and SSH material are excluded
├── .gitattributes          LF line endings, enforced at commit time
├── .editorconfig           LF line endings, enforced in the editor
├── docs/
│   ├── architecture.md     what the system is made of
│   ├── provisioning.md     how it is built, and in which order
│   └── decisions/          architecture decision records
├── terraform/
│   ├── versions.tf         Terraform floor, provider pinned exactly
│   ├── main.tf             cloud image, cloud-init snippets, the four VMs
│   ├── variables.tf        Proxmox endpoint and API token
│   └── terraform.tfvars.example
└── ansible/
    ├── ansible.cfg
    ├── inventory.yml       four hosts, written by hand
    ├── group_vars/         all, k8s_cluster, storage
    ├── requirements.yml    pinned Ansible collections
    ├── site.yml            seven plays, in dependency order
    ├── checks.yml          read-only verification, safe at any time
    └── roles/              common, nfs_server, kube_prereq,
                            control_plane, cilium, worker, nfs_provisioner
```

Terraform state is local and not committed: it contains the Proxmox API token in
clear text.

## Prerequisites

The control station is a dedicated WSL2 Ubuntu distribution. Ansible cannot run on
Windows — it forks its worker processes, and imports POSIX-only modules — so the
tooling lives on the Linux side even though the repository sits on the Windows
filesystem. Terraform alone would run fine on Windows; keeping both in the same place
avoids maintaining two toolchains.

Before the Terraform layer can be applied, the following must exist and are not
automated:

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

Two keypairs, then: one for the hypervisor account, one injected into the VMs by
cloud-init. Separate uses, separate revocations.

## Building it

From the WSL shell. First the machines, in `terraform/`:

```bash
cp terraform.tfvars.example terraform.tfvars
# fill in proxmox_endpoint and proxmox_api_token
terraform init
terraform plan
terraform apply
```

`terraform init` downloads the provider at the exact version recorded in
`.terraform.lock.hcl`, which is committed on purpose so the plugin and its checksums
are reproducible. `terraform apply` downloads the Debian 13 cloud image onto the
hypervisor, writes one cloud-init snippet per machine, and creates the four VMs.

The first apply takes a few minutes, most of it spent on the image download and on
waiting for the QEMU guest agent to report an address on each new machine.

Then the cluster, in `ansible/`:

```bash
ansible-playbook checks.yml
ansible-playbook site.yml
```

`checks.yml` changes nothing and is safe to run at any time, including on machines
that have never been configured. `site.yml` is idempotent: a second run on a
healthy cluster reports `changed=0` on every host, and anything else is a bug in a
role rather than an expected difference.

If the workstation is connected to a corporate VPN, the `192.168.1.0/24` network may
be unreachable from WSL — disconnect it before blaming the tooling.

## Documentation

- [docs/architecture.md](docs/architecture.md) — the layers, the four machines, the
  two networks, the address plan, the sizing, and what runs inside the cluster.
- [docs/provisioning.md](docs/provisioning.md) — how the system is built: the manual
  prerequisites, what Terraform does, the seven Ansible plays and why they are in
  that order.
- [docs/decisions/](docs/decisions/) — architecture decision records: why things are
  the way they are, one decision per file.
