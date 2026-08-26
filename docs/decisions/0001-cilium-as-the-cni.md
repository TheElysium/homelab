# Cilium as the CNI

## Status

accepted

## Context

kubeadm builds a cluster with no pod network. Until a CNI is installed every node
stays `NotReady`, so the choice cannot be deferred.

The cluster runs on a single hypervisor and is intended to host real services. Two
requirements are important:

- Services must be reachable from the LAN at a stable address. `NodePort` works
  but forces every consumer to know a node address and a port above 30000.
- `NetworkPolicy` must actually be enforced. Writing policies that the API server
  accepts and nothing applies teaches the wrong lesson.

The first build of this cluster shipped flannel. It worked, and the nodes came up
`Ready`, but neither requirement above was met: `LoadBalancer` services stayed
`<pending>` and `NetworkPolicy` objects were inert. This record supersedes that
implicit choice.

## Considered Options

**flannel alone.** The smallest thing that works. A VXLAN overlay and nothing
else — no policy engine, no address allocation on the LAN. Fails both
requirements.

**flannel plus MetalLB.** Adds LAN addresses through a second component with its
own controller, speaker DaemonSet and address pools. Solves reachability, leaves
`NetworkPolicy` unenforced, and puts two projects in the data path that must be
upgraded independently.

**Calico plus MetalLB.** Enforces `NetworkPolicy` and is the most widely deployed
combination, so failures are well documented. Still two components, and Calico's
iptables data path duplicates what kube-proxy already does.

**Cilium.** Provides the pod network, enforces `NetworkPolicy`, and allocates
LAN addresses through LB-IPAM with L2 announcements — one component instead of
two. It also uses an eBPF data path, which is the least familiar part of this
setup.

## Decision

Cilium 1.20.1, VXLAN tunnel mode over the internal interface, with LB-IPAM and L2
announcements enabled and a pool of `192.168.1.210`–`.220` on the LAN.

The deciding factor was component count. The cluster has one control-plane node, so
each additional component adds another independent failure point. Cilium was the
only considered option that met both requirements in one project.

## Consequences

The cluster gets `LoadBalancer` addresses on the LAN and enforced network
policies without a second project to install, version and upgrade. Hubble is
available later through Helm values.

The data path is eBPF. There are no iptables rules to read when something is
wrong: diagnosis goes through `cilium status`, `cilium monitor` and Hubble, which
must be learned before they are needed. This is the main operational cost of the
decision.

Cilium publishes a support matrix against Kubernetes versions, so the two are now
upgraded together rather than independently.

L2 announcements are not load balancing. One node answers ARP for a given
service address; if it goes down another takes over after the lease expires, but
traffic is never spread. This is acceptable for a three-node cluster but would not
scale in the same way to a larger deployment.

The overlay is confined to a single L2 domain, which is true of this LAN and
would not survive the cluster being split across networks.
