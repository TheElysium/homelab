# PostgreSQL on CloudNativePG with NFS storage

## Status

accepted

## Context

The cluster gains its first stateful application workload: a PostgreSQL
database. Two questions arrive together — how to run it, and where to put its
data.

Running it means more than a container image. PostgreSQL needs its data
directory initialised, its configuration rendered, and, after an unclean exit,
recovery supervised. A hand-written StatefulSet can do all of this, but every
rule it encodes — when to run `initdb`, when to run `pg_rewind`, when a replica
is too far behind to rejoin — is a rule someone has to get right once, under
pressure.

Where to put the data is constrained by the same record that constrained
Prometheus. [ADR-0004](0004-prometheus-on-a-local-persistentvolume.md) rejected
NFS for the time-series database because its on-disk format memory-maps files
and relies on POSIX semantics that NFS approximates rather than guarantees, and
upstream refuses to support it. That reasoning is specific to Prometheus's
storage engine, and it does not transfer. PostgreSQL is built on `fsync` and
file locks, not mmap, and its data lands on the NFS server's own ext4
filesystem — the same class of storage it expects. CloudNativePG documents
network storage, NFS included, as a supported option. What NFS cannot offer is
consistency under split brain, which here cannot happen: one server, one
client per file, no cluster-wide filesystem in between.

A third option exists outside the cluster entirely: a PostgreSQL package
installed by Ansible on `nfs-server` or a new VM. That is how the previous
lab generations ran databases. It is rejected here because it recreates the
problem ADR-0003 solved for helm: a component whose lifecycle no role owns,
configured by out-of-band edits, and invisible to the cluster that consumes it.

## Considered Options

**A `local` PersistentVolume, as Prometheus does.** POSIX-compliant, proven in
this cluster, zero new software. But it pins the database to one worker's root
disk, and "the workers are disposable, the storage VM is not" is the load-
bearing line of this build. Rebuilding the workers would strand the data; the
NFS export survives them by design.

**PostgreSQL on a VM, managed by Ansible.** Outside the cluster, invisible to
`kubectl`, backed by the same NFS server or a new data disk. One more
long-running process on a VM with 1 GB of RAM, or one more VM on a 16 GB host.

**A hand-written StatefulSet.** No operator, no new CRDs, but `initdb`,
recovery and version upgrades become Ansible's problem. Everything Ansible
would encode is what the operator below already implements, and has already
implemented better.

**CloudNativePG on the `nfs-client` StorageClass.** An operator that owns the
full lifecycle, dynamic volume provisioning on the storage VM, and a resource
model — one PVC per instance — that matches how the cluster already consumes
storage.

## Decision

CloudNativePG, installed by Helm, running one single-instance `Cluster` whose
volumes come from the `nfs-client` StorageClass — 20 Gi per instance, dynamic.

Single instance, not three: this cluster runs on one hypervisor, so replicas
buy nothing against the failure that matters, and the memory budget of the
workers is close to spent. High availability would be replication theatre.

The `Cluster` manifest is applied with `kubectl`, not Helm, exactly like the
monitoring role's local-PV manifest: it is a single object of the operator's
own API, and helm-as-the-deployment-channel applies to charts.

## Consequences

The database's data lives on the NFS export and shares its fate: it survives
every rebuild of the three Kubernetes nodes, and it dies with the storage VM.
That is the same trade every other claim in the cluster has already made, and
`protection = true` plus the 40 GB data disk are its existing mitigations.

A single PostgreSQL instance changes nothing about the failover story of the
cluster: losing the node running the instance means a reschedule onto another
worker, an NFS remount, and crash recovery — seconds to minutes, handled by
the operator, with the WAL on NFS doing exactly what it is designed for.

The NFS export is not backed up. PostgreSQL makes taking a consistent backup
easier than any other stateful workload here — `pg_dump` alone suffices at
this scale — but nothing in the build runs it, and until something does, the
database's durability is identical to Prometheus's, which is to say one SSD.

The operator watches the `Cluster` object and reconciles drift, which means
the manifest under `/etc/kubernetes/addons/` is the source of truth in the
same way the kubeadm templates are: a rebuild, or a replay of the tag, returns
the database to what the repository says it should be.

The CRD registration race is the same one the cilium role met:
`kubectl wait --for=condition=established` on `clusters.postgresql.cnpg.io`
sits between the release and the manifest, retried, because `kubectl wait`
errors on a resource that does not exist yet instead of waiting for it.
