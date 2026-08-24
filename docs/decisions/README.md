# Architecture decision records

This directory holds the reasoning behind the design described in
[../architecture.md](../architecture.md). The architecture document says what the
system is; these records say why it is that way, and what was given up in exchange.

One decision per file. A record is written when a choice was not obvious — when there
was a real alternative that a reasonable person might have picked instead. Choices
that had no alternative are not decisions and do not need a record.

Records are not updated when the design changes. A decision that no longer holds
keeps its file and its text intact; a new record supersedes it. The history is the
point.

## Format

The records follow a trimmed-down [MADR](https://adr.github.io/madr/) structure. Five
sections, in this order:

- **Status** — one of the values listed below.
- **Context** — the situation and the constraints that forced a choice. Written so it
  still makes sense to someone who was not there.
- **Considered Options** — what else was on the table, including the option of doing
  nothing.
- **Decision** — what was chosen, and the reason that decided it.
- **Consequences** — what follows, good and bad. The bad half is the one that earns
  the record its keep; a Consequences section listing only benefits is a sign the
  record is advocacy rather than documentation.

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
