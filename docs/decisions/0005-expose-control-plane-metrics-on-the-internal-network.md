# Expose control-plane metrics on the internal network

## Status

accepted

## Context

`kubeadm` starts `kube-controller-manager` and `kube-scheduler` with
`--bind-address=127.0.0.1`, and `etcd` with
`--listen-metrics-urls=http://127.0.0.1:2381`. All three serve `/metrics`, and all
three serve it to the loopback interface of `k8s-master` and nowhere else.

Prometheus scrapes over the network from a pod on a worker. It will never reach
any of them as configured.

`kube-prometheus-stack` ships a ServiceMonitor for each of these three, plus one
for `kube-proxy`, which does not exist here — [ADR-0002](0002-replace-kube-proxy-with-cilium.md)
replaced it with Cilium. Installed with its defaults, the chart produces four
permanently DOWN targets. Nothing breaks, but a monitoring system that is always
partly red stops being read, and a real outage disappears into the noise.

The two options are therefore to stop asking for these metrics, or to make them
reachable. Which is acceptable depends on what exposure actually means for each
component, and they are not the same.

`kube-controller-manager` and `kube-scheduler` serve `/metrics` on a secure port —
10257 and 10259 — over TLS, with authentication and authorisation delegated to the
API server. Binding them to `0.0.0.0` makes the port reachable; it does not make
the metrics public. An unauthenticated request gets a 401. Prometheus presents its
ServiceAccount token and is authorised by RBAC that the chart installs.

`etcd` is different. Its metrics port 2381 is plain HTTP with no authentication at
all. Binding it to `0.0.0.0` genuinely exposes it to anything that can route to the
node.

What can route to the node is `10.0.10.0/24`, on `vmbr1`: a bridge with no physical
port, no address on the hypervisor and no gateway. [architecture.md](../architecture.md)
already leans on that isolation for a heavier exposure — the NFS export is served
`no_root_squash`, so root on any machine in the segment is root on the cluster's
data.

## Considered Options

**Disable all four ServiceMonitors.** Four values in the Helm release, no target
ever red, no change to a running control plane. This is what every managed cluster
does, because on EKS, GKE and AKS the control plane belongs to the provider and
there is nothing to scrape. It costs the metrics: no scheduling latency, no
controller work queues, no etcd disk latency.

**Rebind the two secure ports, disable `etcd` and `kube-proxy`.** Keeps the
components whose exposure is authenticated, drops the one that is not. Loses
`etcd_disk_wal_fsync_duration_seconds`, which is the canonical signal for a slow
cluster and the most relevant one here: four VMs share a single consumer NVMe
through an LVM-thin pool.

**Scrape `etcd` over mutual TLS on its client port 2379.** Correct, and what a
cluster holding anything sensitive should do. Requires mounting etcd's client
certificates into Prometheus and a `ServiceMonitor` configured against them.

**Rebind all three, `etcd` included, in the clear.** Accepts an unauthenticated
metrics endpoint on the internal segment, on the same reasoning already applied to
`no_root_squash`.

## Decision

Rebind all three. `kube-controller-manager` and `kube-scheduler` bind `0.0.0.0` on
their existing secure ports; `etcd` serves `http://0.0.0.0:2381`. `kube-proxy`
monitoring is disabled, since there is nothing to monitor.

Refusing `etcd` while accepting `no_root_squash` on the same network would not be a
security position, only an inconsistent one: the export gives away the cluster's
data, the metrics port gives away request rates and latencies. The isolation of
`vmbr1` is either sufficient for both or for neither, and this build has already
committed to the first answer.

Mutual TLS was rejected on effort, not on principle. It is the correct answer for a
segment that is not isolated.

## Consequences

`vmbr1` carries one more thing that depends on it having no gateway. That list is
now the NFS export, the API server, and these metrics. Giving the bridge a gateway
was already a decision that could not be taken lightly; it is now one that would
require revisiting three records.

The isolation holds against the LAN, not against the cluster. Pod traffic leaves
through `vmbr1`, so a compromised pod can read `etcd`'s metrics port. What it reads
is operational — request counts, latencies, database size, leader changes — and not
the contents of any key. A NetworkPolicy is the remedy, and none is written.

The arguments live in `ClusterConfiguration`, which `kubeadm` reads once, at `init`.
The running cluster carries them in the static manifests under
`/etc/kubernetes/manifests/`, so the Ansible role has to reconcile both: the
template, which is the record of what a rebuild produces, and the manifests, which
are what the cluster is actually running. The two would silently diverge otherwise.

Editing a static manifest restarts the component, because the kubelet watches the
directory. For `etcd` on a single-control-plane cluster that means a brief window
with no API server. The role waits for the component to come back rather than
assuming it.

`kube-proxy` monitoring stays disabled for as long as ADR-0002 stands. If
kube-proxy ever returns, this is one of the places that has to be revisited.
