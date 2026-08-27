# Prometheus on a local PersistentVolume

## Status

accepted

## Context

The cluster was built without observability. Adding it raises a storage question
before anything else, because Prometheus is the only component so far that keeps
state of its own.

The cluster has exactly one StorageClass, `nfs-client`, which provisions
directories on the export served by `nfs-server` at `10.0.10.10`. Every other
workload would use it without a second thought.

Prometheus cannot. Its time series database memory-maps its data files and relies
on POSIX file locking and rename semantics that NFS approximates rather than
guarantees. Upstream documentation states plainly that NFS, including EFS, is not
supported. The failure mode is not a refusal to start: it is silent corruption of
the blocks on disk, discovered when a query returns nothing.

This is a single Prometheus instance on a three-node cluster running on one
physical machine. High availability is not on the table, which widens what is
acceptable.

## Considered Options

**`emptyDir`.** kubelet creates a scratch directory on the node's disk and deletes
it when the pod is destroyed. POSIX-compliant, zero configuration, no storage
object to write. The history dies with the pod, which includes every chart upgrade
and every eviction — and history is the entire point of collecting metrics.

**NFS anyway.** Uses the existing StorageClass and keeps Prometheus schedulable on
any node. Works long enough to look fine. Corrupts on the first network hiccup, in
a way that is hard to attribute to storage after the fact.

**Remote write to a store on `nfs-server`.** Run VictoriaMetrics or Thanos on the
storage VM and have Prometheus push to it over HTTP. This does not remove the
problem: `remote_write` is an additional tier, not a replacement, and Prometheus
still writes a local write-ahead log and replays it to feed the send queue. It
also adds a component outside the cluster, unmanaged by any role, on a VM with
1 GB of RAM.

**A `local` PersistentVolume.** A directory on a worker's own disk, declared as a
statically provisioned PV with `nodeAffinity`. POSIX-compliant because it is an
ordinary filesystem. Pins Prometheus to that node for the life of the volume.

## Decision

A `local` PersistentVolume of 10 Gi on `k8s-worker-2`, with a `local-storage`
StorageClass in `WaitForFirstConsumer` mode, and 15 days of retention.

`WaitForFirstConsumer` is what makes the binding correct: with the default
`Immediate` mode the claim binds before the scheduler has chosen a node, and the
pod can be placed where the volume does not exist.

The worker was chosen over the control plane for its memory headroom — roughly
2.7 GB available against 1.7 GB on the master — and `k8s-worker-2` over
`k8s-worker-1` arbitrarily.

## Consequences

Prometheus is pinned to `k8s-worker-2`. No `nodeSelector` says so: the constraint
comes from the volume and reaches the scheduler through the claim. If that node is
lost, the pod stays `Pending` and monitoring is down at the moment it would be most
useful. The blast radius is narrower than it looks, since all four VMs share one
hypervisor and lose everything together anyway; what this adds is the case where
that single worker fails on its own.

Nothing recreates the directory. Kubernetes references a `local` volume, it does
not manage its lifecycle, which is why the volume is provisioned statically by
Ansible and why the PV must be deleted by hand if the node is rebuilt.

The 10 Gi come out of the worker's 32 GB root disk, which was 9% used before this.
Prometheus enforces retention by size as well as time, so the volume caps the
damage a runaway cardinality can do to the node.

A second stateful workload needing POSIX semantics now has a pattern to copy, and
a second `local` PV to declare — this does not generalise into a provisioner.

Long-term retention remains open. The path is `remote_write` to a store on
`nfs-server`, which becomes worth its cost once 15 days is the binding limit.
