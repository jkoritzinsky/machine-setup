---
name: create-session-stack
description: Set up an owner-light-ready session stack for an existing PR stack, from a fresh coordinator or by spinning all layers (including the top) out of its implementation session. Use ONLY when the user explicitly requests a session stack or separate layer sessions. A request for a PR stack, rebase, review, or skill authoring alone does not authorize creating sessions.
---

# Create a session-owned PR stack

This sets up **sessions for an existing PR stack**, not new PRs or a new Git stack.
Use one skill with two entry modes because allocation, identity, ownership, and
readiness gates are shared. The caller remains the coordinator; every selected
layer, including the top, has a separate owner session.

## Hard invocation gate

Create sessions only after an explicit user request for a **session stack**,
**one session per PR layer**, or **spinning layers into separate sessions**.
An explicit `/create-session-stack` invocation is sufficient; it still needs a
specified stack. "Create a PR stack," "rebase these PRs," a suggestion in a document,
or a request to author/change this skill is not permission to spawn sessions.
If intent or stack scope is unclear, ask one focused question before allocation.
Never infer this permission from invoking `gh-stack` or `orchestrate` as a helper.
An automatically surfaced current PR is not a supplied complete stack.

## Choose the entry mode

| Mode | Starting point | Layer context |
| --- | --- | --- |
| `bootstrap` | A new coordinator with a provided existing PR stack | Reconstruct from live PRs, pinned code/ranges, available decisions and validation |
| `spinout` | The current session implemented the whole stack | Preserve its complete layer-specific decisions, provenance, history, artifacts and unfinished work |

Choose from the request and verified session history; do not guess implementation
context. Reuse a matching setup manifest on retry instead of creating more sessions.
Read [provisioning](provisioning.md) before allocation and the applicable
[context handoff](handoff.md) sections. [Verification](verification.md) defines the
completion gate and failure cases.

## Discover and pin

In a Side chat, refresh the main transcript and identify the actual source owner.
Do not mistake the Side chat's state for a quiescent implementation session.

Resolve the current coordinator's exact project ID, logical repository, execution
host/runtime, source worktree, and Git common directory. Discover sessions once.
All new owners must use that **same project**, repository and local execution
environment; do not select another project merely because its GitHub repo matches.
Use isolated worktrees, not branch sessions sharing one checkout.

Resolve bottom-to-top order from the supplied stack and live PR bases, not PR
numbers. When native membership exists, verify and preserve it. Pin full heads,
head repositories/branches, historical boundaries, and
selected layers. Do not guess a linear order for forks/ambiguous chains. Retain
merged/closed entries as history; if the requested scope includes them, clarify
whether they need owners instead of silently omitting them or recreating branches.

Record authority, snapshots, source ownership, context-packet paths, and one durable
allocation slot per layer in a setup manifest outside product source. Check existing
owners before allocation. Never duplicate an active owner without a coordinated
handoff. In `spinout`, the implementation session is not reused as the top owner.

## Prepare before creating

Build each layer's handoff packet first. Transfer all relevant context through a
compact index plus complete supporting artifacts, not the whole transcript in every
owner conversation. Cite source turns/commits and label unknown or stale evidence.
Spinout must account for unpublished commits and pending feedback, not just PR text.

Finish affected source processes and inspect Git/owner-light/stack-tool state.
Preserve clean committed source tips with create-only backups. Release occupied
layer branches by a verified Git-detached handoff, including the implementation
session's top branch. Do not reset, stash, commit user work, disable automation,
archive the source, or edit its app configuration to manufacture readiness.
Dirty/unsaved work, an active lease, or disputed ownership is a blocker to settle
before allocating owners. Source history and artifacts remain intact.

## Allocate and hand off

Use `create_session` in the caller's project (`project_id` omitted or that exact
verified ID), `execution_location: local`, `workspace_type: worktree`,
`coordinate_with_creator: true`, and `notify_on_idle: once`.
Leave `base_branch` unset: these are owners of existing pinned tips, not newly
authored dependent branches. Do not use cloud sessions or fork the whole conversation.
Create idle sessions first; save every returned ID/path immediately.

Verify the first child's project, host/runtime and accessible worktree before
allocating the rest. If app metadata cannot prove runtime identity, complete that
first child's bounded setup/acknowledgment before creating the others. Prepare
concrete expected refs and packet transport for each idle worktree. Use one bounded
immediate setup message with the packet, exact
checkout instruction, coordinator identity, and owner-only protocol. Preserve the
generated branch; attach the existing owned PR branch using the guarded Git protocol.
Do not create a replacement PR or trust an app's idle status as a checkout receipt.

Each owner reports one verified setup acknowledgment: loaded packet identity,
project/environment, actual branch/head/common directory, clean checkout, and
cooperative owner-light readiness. Keep substantive code changes out of setup.

## Verify and finish

Require exactly one owner per selected layer, **top included**, all in the same
project/repository/runtime, with verified pinned checkouts and accessible handoffs.
Compare actual Git identity with app metadata and record any missing PR UI binding
honestly. Ambiguous/stale branch metadata is not a completed setup.

The coordinator no longer owns a layer. Normally designate the top owner as future
executor; record supported execution capabilities without changing public membership.
An explicitly requested `gh stack` workflow needs verified local registration;
a plain PR chain must not acquire a new public stack merely to complete setup.
Owner-light-ready means compatible topology and an acknowledged cooperative protocol,
not an active lease or standing rebase/push permission. Acquire fresh scoped leases
only for a subsequently authorized operation using `rebase-session-stack`.

Report the owner map, existing PRs, executor, source handoff, and real readiness
limitations. Link sessions using the exact `app_url` from `list_sessions_and_chats`.
Do not create leases, rebase, push, edit PRs, post comments, or create issues during
setup unless separately requested. Preserve partial setup on failure; retry its
known slots rather than cloning the stack again.
