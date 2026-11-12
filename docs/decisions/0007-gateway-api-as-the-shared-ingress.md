# Gateway API as the shared ingress

## Status

accepted

## Context

The first application to need an HTTP entry point is cadence, and it sets the
shape of the problem: its frontend and backend must reach the browser as a
single origin (`SameSite=Lax` refresh cookie with path `/api/auth`), with
`/api/*` forwarded to the backend and the prefix stripped, and no proxy in the
chain rewriting `Set-Cookie`. Any ingress mechanism must support path matching
with rewrite, and the simplest way to keep one origin is one listener serving
both halves.

The cluster already has a way to hand out addresses: Cilium LB-IPAM with the
`lan` pool (192.168.1.210–220). Handing every application its own
`type: LoadBalancer` Service works, but burns pool addresses at one per app,
and path routing between an app's frontend and backend is impossible at the
Service layer — the split has to happen above it.

Cilium 1.20 ships an embedded Envoy in its agents and implements the Kubernetes
Gateway API when enabled. The chart does not carry the Gateway API CRDs, so
they must be installed separately. Kube-proxy replacement is already on, which
is a prerequisite for the embedded Envoy datapath.

## Considered Options

**One LoadBalancer Service per app.** Keep using LB-IPAM directly. No new
concepts, but the frontend/backend split needs two addresses (losing the
single origin) or an app-owned reverse-proxy sidecar (what cadence uses today
as a stopgap), and the pool of eleven addresses becomes the ceiling on how
many HTTP services the cluster can host.

**ingress-nginx with Ingress resources.** The incumbent answer and the most
documented. Adds a second traffic component to operate — its own Deployment,
ConfigMaps, upgrade cadence, CVE surface — for a job the CNI in this cluster
can already do. Ingress is also frozen as an API: everything it does next
happens in Gateway API.

**Gateway API, one Gateway per app.** Adopt the API, but let each chart own a
Gateway in its own namespace with its own pinned address. Isolation is
complete, but it reproduces the one-address-per-app cost and every app carries
listener configuration that is identical in spirit.

**Gateway API, one shared Gateway.** Enable Cilium's implementation, create a
single Gateway owned by the platform (this repository), and let applications
attach HTTPRoutes to it. One address, one listener, routing by hostname and
path. Apps declare only routes; the entry point belongs to the cluster.

## Decision

Gateway API served by Cilium's embedded Envoy, with one shared Gateway:

- The standard-channel CRDs (`v1.6.1`) are downloaded to
  `/etc/kubernetes/addons/gateway-api-crds.yaml` and applied like every other
  manifest, per ADR-0003. The Cilium chart does not ship them, and the version
  is pinned beside the Cilium version: Cilium 1.20 requires Gateway API v1.6.1
  or newer to work correctly. They are applied **before** the Cilium release:
  the chart renders the cluster's GatewayClass itself
  (`gatewayAPI.gatewayClass.create=true`), and that object cannot be applied
  against an API the server does not serve yet. The GatewayClass therefore
  belongs to the Helm release, not to the addon manifests; the addon manifest
  carries only the Gateway namespace and the Gateway.
- The Cilium release gains `gatewayAPI.enabled: true` in the Ansible role's
  Helm values. The Ingress controller stays off. The `lbipam.cilium.io`
  annotation prefix is in the operator's default propagation allow-list, so
  the Gateway's pinned address needs no extra configuration.
- A single Gateway `homelab` in `gateway-system`, `gatewayClassName: cilium`,
  one HTTP listener on port 80, `allowedRoutes` from all namespaces, address
  pinned to 192.168.1.212 with `lbipam.cilium.io/ips` — an address previously
  reserved for an ingress-nginx that was never installed. Nothing else in the
  pool moves. The monitoring grafana keeps .210 in parallel; .211 was freed by
  the t0 migration behind this Gateway, together with the stray one-IP
  `homelab-lan` pool that reserved it.
- Applications attach HTTPRoutes with their `hostnames` pinned — the
  convention is `*.homelab.internal`, each name mapped to 192.168.1.212 by a
  line in the `hosts` file of every client machine; the router holds no record
  for the domain. A request for a hostname no route claims is answered 404 by
  Envoy; nothing falls through to another app.

The frontend/backend split cadence needs is its own HTTPRoute: a
`PathPrefix /api` match forwarded to the backend with `URLRewrite`
(`ReplacePrefixMatch`) stripping the prefix, and a catch-all rule to the
frontend. `URLRewrite` is Extended conformance, but it is part of the standard
CRD schema and Cilium implements it, so the standard bundle is enough. The
rewrite happens between Envoy and the backend only; the browser keeps seeing
`/api/...`, which is why the backend's `Set-Cookie` path is correct as issued
and no proxy may rewrite it.

## Consequences

No new component: there is no extra controller to install, scale, or patch —
the datapath lives in the Cilium agents already running on every node, and
upgrades of the ingress are upgrades of Cilium.

The pool cost of an HTTP app drops to zero addresses: a new app is an
HTTPRoute plus a name under `homelab.internal`. The eleven-address pool stays
free for services that genuinely need their own address.

Routing is by hostname, so name resolution becomes part of deploying an app:
each new hostname needs a `hosts` line on every machine that browses to it,
added by hand outside this repository. On Windows, WSL resolves through the
Windows resolver and picks up the same file. A wildcard record at the router
would replace all of these lines with one. Bare `192.168.1.212` answers 404 for
anything that is not claimed by a route's hostname.

Gateway API CRDs upgrade ahead of the cluster: they are cluster-scoped and
applied by hand here, so bumping `cilium_gateway_api_version` is part of the
repository, not something Helm does. Cilium and the CRDs must move together:
1.20 requires Gateway API v1.6.1 or newer, and the bundle version is pinned
beside the Cilium version in the role defaults so the two are bumped in the
same commit — serving a controller a schema older than the one it was built
against is how reconciliation goes wrong.

Two entry points coexist for now: the grafana instances keep their dedicated
addresses, and migrating them behind the Gateway is optional future work, not
a consequence of this decision.
