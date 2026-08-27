# Architecture decision records

This directory records the decisions behind the design described in
[../architecture.md](../architecture.md). The architecture document describes the
system; these records describe the alternatives and trade-offs.

Use one decision per file. Write a record when a choice had meaningful alternatives.
Choices with no meaningful alternative do not need a record.

Do not update records when the design changes. Keep superseded decisions intact and
add a new record that supersedes them.

## Format

The records follow a trimmed-down [MADR](https://adr.github.io/madr/) structure. Five
sections, in this order:

- **Status** — one of the values listed below.
- **Context** — the situation and the constraints that forced a choice. Written so it
  still makes sense to someone who was not there.
- **Considered Options** — what else was on the table, including the option of doing
  nothing.
- **Decision** — what was chosen, and the reason that decided it.
- **Consequences** — the benefits, drawbacks, and operational impact of the decision.

## Status values

Exactly three are allowed:

| Status | Meaning |
|---|---|
| `accepted` | In force. |
| `superseded by ADR-NNNN` | Replaced by a later record, which must be referenced by number. |
| `deprecated` | No longer in force, and nothing replaced it. |

There is no `proposed` status. A record is written once the decision is made.

## File naming

`NNNN-kebab-title.md`, where `NNNN` is a zero-padded sequence number allocated in
order and never reused, and the title is a short lowercase description of the
decision, in English, with hyphens between words.

For example: `0001-use-kubeadm.md`, `0007-nfs-server-outside-the-cluster.md`.

The number identifies the record permanently. It appears in `superseded by` lines and
in cross-references from other documents, so it must not change once the file exists —
even if the title turns out to be a poor one.

## Index

| Record | Status |
|---|---|
| [ADR-0001 — Cilium as the CNI](0001-cilium-as-the-cni.md) | `accepted` |
| [ADR-0002 — Replace kube-proxy with Cilium](0002-replace-kube-proxy-with-cilium.md) | `accepted` |
| [ADR-0003 — Helm as the deployment channel for cluster components](0003-helm-as-the-deployment-channel.md) | `accepted` |
| [ADR-0004 — Prometheus on a local PersistentVolume](0004-prometheus-on-a-local-persistentvolume.md) | `accepted` |
| [ADR-0005 — Expose control-plane metrics on the internal network](0005-expose-control-plane-metrics-on-the-internal-network.md) | `accepted` |
| [ADR-0006 — PostgreSQL on CloudNativePG with NFS storage](0006-postgresql-on-cloudnativepg-with-nfs-storage.md) | `accepted` |
