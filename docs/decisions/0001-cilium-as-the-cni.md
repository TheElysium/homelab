# Cilium as the CNI

## Status

accepted

## Context

kubeadm builds a cluster with no pod network. Until a CNI is installed every node
stays `NotReady`, so the choice cannot be deferred.

The cluster is a household one, on a single hypervisor, and the stated purpose is
to learn by hosting real services. Two requirements follow from that purpose
rather than from scale:

- Services must be reachable from the LAN at a stable address. `NodePort` works
  but forces every consumer to know a node address and a port above 30000, which
  makes the cluster feel like three machines rather than one.
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
two. Carries an eBPF data path, which is the part with the least prior art in
this homelab.

## Decision

Cilium 1.20.1, VXLAN tunnel mode over the internal interface, with LB-IPAM and L2
announcements enabled and a pool of `192.168.1.210`–`.220` on the LAN.

What decided it was the component count rather than any single feature. Every
additional moving part in a cluster with one control-plane node is a part that
can fail alone, and the alternative that met both requirements with one project
was Cilium.

## Consequences

The cluster gets `LoadBalancer` addresses on the LAN and enforced network
policies without a second project to install, version and upgrade. Hubble is
available later at the cost of a Helm value, which makes observability cheap to
add.

The data path is eBPF. There are no iptables rules to read when something is
wrong: diagnosis goes through `cilium status`, `cilium monitor` and Hubble, which
must be learnt before they are needed. This is the real cost of the decision.

Cilium publishes a support matrix against Kubernetes versions, so the two are now
upgraded together rather than independently.

L2 announcements are not load balancing. One node answers ARP for a given
service address; if it goes down another takes over after the lease expires, but
traffic is never spread. On a three-node cluster this is the right trade, and it
would not be at a larger size.

The overlay is confined to a single L2 domain, which is true of this LAN and
would not survive the cluster being split across networks.
