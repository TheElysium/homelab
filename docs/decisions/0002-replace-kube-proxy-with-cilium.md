# Replace kube-proxy with Cilium

## Status

accepted

## Context

[ADR-0001](0001-cilium-as-the-cni.md) chose Cilium in part for its L2
announcements, which are what give `LoadBalancer` services an address on the LAN.

Cilium's documentation states that L2 announcements require kube-proxy
replacement to be enabled. The feature is not additive: it is implemented in the
same eBPF service data path that replaces kube-proxy, and is unavailable when
kube-proxy owns service routing.

The design written before this record kept kube-proxy and enabled L2
announcements at the same time. That combination does not exist. The
contradiction had to be resolved one way or the other before the cluster could
be built.

kube-proxy is installed by `kubeadm init` unless the phase is skipped. Removing
it after the fact leaves its iptables rules on every node, so the choice is
effectively made once, at initialisation, for the life of the cluster.

## Considered Options

**Keep kube-proxy, give up `LoadBalancer`.** Services stay on `NodePort`. Cilium
is then a CNI and a policy engine only, and half the reason it was chosen in
ADR-0001 disappears.

**Keep kube-proxy, add MetalLB.** MetalLB does its own L2 announcements and does
not care about the service data path. This works, and it is the combination most
homelabs run — at the cost of the second component ADR-0001 set out to avoid.

**Replace kube-proxy with Cilium.** Skip the `addon/kube-proxy` phase at
`kubeadm init` and let Cilium own service routing. Unlocks L2 announcements and
leaves one implementation in the data path.

**Do nothing.** Keep the flannel cluster as built, with neither `LoadBalancer`
nor enforced policy. The option of not deciding, recorded because it was real:
the cluster was running and usable.

## Decision

Replace kube-proxy. `InitConfiguration` carries `skipPhases: [addon/kube-proxy]`,
and Cilium is installed with `kubeProxyReplacement: true`, pointed at the API
server by address since no ClusterIP is routable before the agent is up.

The deciding argument is that the second option — kube-proxy plus MetalLB — is a
working design that contradicts the reason Cilium was chosen. Choosing it would
have meant reopening ADR-0001 rather than completing it.

## Consequences

One implementation of services instead of two, and no iptables rule set to grow
with the number of services.

Cilium becomes a hard dependency of service routing. When the agent is down on a
node, ClusterIP resolution on that node is down with it — there is no kube-proxy
underneath to fall back to. On a single-control-plane cluster this widens the
blast radius of a bad Cilium upgrade considerably.

Debugging service routing no longer means reading `iptables -t nat -L`. The
equivalent is `cilium service list` and `cilium monitor`, from inside the agent
pod.

`skipPhases` must survive every future `kubeadm upgrade`. If it is ever dropped,
kube-proxy reappears and two implementations fight over the same traffic.

The replacement requires a kernel with the eBPF features Cilium expects. Debian
13's kernel provides them; a distribution change is now constrained by that.
