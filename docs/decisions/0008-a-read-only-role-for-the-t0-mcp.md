# A read-only database role for the t0 MCP server

## Status

accepted

## Context

The t0 chart gains an MCP server: a read-only HTTP service that gives an LLM
access to the training marts. Its design contract asks the platform for exactly
one thing the cluster does not have yet — a PostgreSQL role `t0_mcp_ro`, with
login but no privileges of its own, existing **before** the first deploy of the
branch. t0's migration `020_mcp_ro_grants.sql` runs `GRANT` statements against
that role, and a grant to a missing role aborts the migration by design: the
application fails loudly rather than deploy half-readable.

The role cannot be created by a t0 migration itself: the application user `t0`
has no `CREATEROLE`, deliberately — the application must not be able to mint
identities in its own database. Creation therefore belongs to the operator or
to this repository. The application user does share the image's statement
timeout and connection-level `default_transaction_read_only`; the role-level
guarantee is the one layer this repository owns.

The Cluster runs CloudNativePG 1.30 (chart 0.29.0), which has declarative role
management in the `Cluster` spec. The t0 handoff proposed a stanza using
`passwordSecret: {}` and an `inRole: pg_read_only_data`; neither survives
contact with the operator actually running here. `passwordSecret: {}` does not
auto-generate a password for managed roles — the operator generates passwords
for its reserved users only, and a managed role without a password secret is
created with a `NULL` password and can never log in (auto-generation is an open
upstream request). The field is `inRoles`, a list, and there is no
`pg_read_only_data` role in PostgreSQL; the predefined role is
`pg_read_all_data`.

## Considered Options

**Shared `t0` application credentials.** Point the MCP at the `t0` user. Zero
new objects, but every read the MCP makes would carry the write-capable
application identity — and one prompt-injection away from a `DROP TABLE`
executed with the database's own keys. The whole point of the MCP's read-only
posture is that the credentials it holds cannot write, so this only works by
trusting every layer above the database, which is where the trust should be
weakest.

**`pg_read_all_data` membership.** The predefined role, granted through
`inRoles`. One line, and the MCP could read every table in every schema —
including the raw ingest tables the marts are built from, which are not part of
the MCP's contract. It would also make the read access independent of
migration 020, so the "fails loudly until granted" property is lost. The
handoff's own note says read comes from migration 020, "not from role
inheritance"; this option contradicts it.

**A `DatabaseRole` resource, CNPG's newer standalone API.** Functionally
equivalent to the inline stanza and upstream-recommended for GitOps. But it is
a second object type beside the Cluster manifest this repository already
renders and applies, and the inline `managed.roles` stanza is reconciled
periodically against the database catalog — drift is corrected even if nothing
re-applies the manifest. One object, one apply path.

**Inline `managed.roles` in the Cluster spec.** The role is declared where the
Cluster is declared, reconciled back to spec on every pass, and fails visibly
(`status.managedRolesStatus.cannotReconcile`) when something cannot be honored.

## Decision

The `postgres` role declares the role inline in the Cluster spec:

- `managed.roles` gains `t0_mcp_ro` with `login: true`, `connectionLimit: 4`
  (matching the MCP's own pool ceiling), **no memberships**, and a
  `passwordSecret` pointing at a `kubernetes.io/basic-auth` Secret the role
  creates from the vault (`t0_mcp_ro_password`, alongside the Grafana admin
  password). No password is committed; rotating is a vault edit and a replay —
  the Secret carries `cnpg.io/reload: "true"`, so the operator applies the
  change to the database role, and the same replay rewrites the DSN Secret.
- The DSN Secret `t0-mcp-ro-dsn` in the `t0` namespace — which the t0 chart
  references but never creates — is built by the same role from that password
  and the cluster's `-rw` service. There is no `-ro` service to prefer: the
  cluster is single-instance by decision of
  [ADR-0006](0006-postgresql-on-cloudnativepg-with-nfs-storage.md).
- The password Secret is applied **before** the Cluster manifest, so the
  managed role never reconciles against a missing secret.

The rejection of `pg_read_all_data` is the load-bearing choice: the role stays
empty of privileges, so before migration 020 has run, `t0_mcp_ro` can connect
to nothing. The read-only guarantee is layered — role grants (020), connection
`default_transaction_read_only`, statement timeout — and the first layer is the
only one this repository provides.

## Consequences

The role exists before any t0 deploy that needs it: replaying
`site.yml --tags postgres` creates it, and `checks.yml` verifies both the
reconciliation status and the DSN secret, so the handoff checklist item is a
playbook run, not a manual `psql` session.

The vault gains a second required entry. Like the Grafana password, the role
fails loudly with remediation instructions when it is missing — a fresh rebuild
asks for it once and every replay after that is unchanged.

CNPG reconciles the role back to spec: an `ALTER ROLE` issued by hand against
`t0_mcp_ro` (connection limit, login, memberships) is reverted on the next
pass. A write grant granted by hand would be reverted too, but the database
reconciliation is a backstop, not a security boundary — the invariant "no write
grants on `t0_mcp_ro`, ever" is enforced by review, here and in t0's
migrations.

The MCP connects over the `-rw` service even though it only reads. If a replica
pool ever exists, switching the DSN host is a one-line default change away.
