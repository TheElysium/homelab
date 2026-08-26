# Helm as the deployment channel for cluster components

## Status

accepted

## Context

Every cluster component installed so far follows one pattern: an Ansible template
renders a manifest to `/etc/kubernetes/addons`, `kubectl apply` installs it, and a
`rollout status` waits for it. The manifest is a file in this repository, so what
runs in the cluster is what can be read in git.

Cilium breaks the pattern. It is distributed as a Helm chart and nothing else:
there is no maintained plain-manifest release to download and patch, and the
number of values that must be set — kube-proxy replacement, the API server
address, tunnel mode, devices, L2 announcements, client rate limits — makes
hand-maintaining a rendered manifest a poor idea.

The decision is not confined to Cilium. Most of what this cluster will host next
is published as a chart, so whatever is chosen here becomes the way applications
arrive on the cluster.

## Considered Options

**Plain manifests only.** Vendor a rendered Cilium manifest into the repository
and keep the existing pattern unchanged. Everything stays readable in git, and
every upgrade becomes a manual re-render with the values reapplied by hand.

**`helm template` plus `kubectl apply`.** Use Helm as a renderer inside an
Ansible task, write the output to `/etc/kubernetes/addons`, and apply it exactly
like the other components. Keeps one pattern across the repository. Helm never
talks to the cluster, so there is no release to upgrade or roll back, and objects
dropped from the values are never pruned.

**`kubernetes.core.helm`.** Ansible drives Helm as a release manager. Helm owns
installation, upgrade, rollback and the tracking of what it installed. Adds the
`helm` binary and the `kubernetes.core` collection as dependencies, and moves the
record of what is installed out of the repository and into the cluster.

## Decision

`kubernetes.core.helm`, with the `helm` binary installed by the role that needs
it and `kubernetes.core` pinned in `requirements.yml`.

The second option fits Cilium but does not scale to future applications. Rendering
each chart by hand would add maintenance work and prevent Helm from managing the
release.

## Consequences

Upgrades become a version bump: Helm computes the difference, removes what the
new chart no longer defines, and `helm rollback` exists when it goes wrong. None
of that is available when Helm is used as a renderer.

The state of a release lives in Secrets inside the cluster, not in this
repository. `git show` no longer answers what is deployed; `helm get values`
does. Someone reading the repository sees the inputs and must render the chart to
see the output.

Two deployment methods now coexist. `nfs_provisioner` keeps its hand-written manifest,
because it is a manifest and not a chart, and converting it would be churn.
Anyone adding a component has to decide which pattern applies — the rule being
that charts go through Helm and everything else through `kubectl apply`.

The cluster gains two dependencies that must be installed before a playbook run:
the `helm` binary on the control-plane node and the `kubernetes.core` collection
on the Ansible control machine.
