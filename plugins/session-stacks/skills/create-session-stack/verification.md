# Setup completion and failure checks

These are workflow acceptance cases, not claims that live app session creation
was tested while authoring the skill. Existing guarded-Git and owner-light fixtures
cover their Git/lease primitives; app allocation/binding needs live receipts.

## Completion gate

Check all fields against actual tool/Git results:

| Invariant | Evidence |
| --- | --- |
| Explicit session-stack permission | User request or explicit skill invocation; authoring the skill does not qualify |
| Exact selected PR stack | Verified provided chain/native membership as applicable, PR states, pinned heads/ranges and resolved historical-layer scope |
| One owner per selected layer | Unique child IDs/branches with top included; no accidental current-coordinator owner |
| One project and logical repo | App project IDs match the coordinator; verified repository identities and fork/head transports |
| Same execution environment | Actual owner runtime/host and accessible local paths match; Windows/WSL/cloud not conflated |
| Safe source release | Clean committed checkpoints, backup refs, ownership/process/Git/tool/lease evidence; source top detached if transferred |
| Safe destination checkout | Clean symbolic owned branch/HEAD/ref, exact pinned SHA, historical ancestry, separate live-base/restack status, occupancy and guarded transfer evidence |
| Layer context transferred | Packet hash and artifact availability acknowledged; spinout coverage map accounts for relevant original context |
| Owner-light ready | Python 3.9+, helper/checklist and durable record location available, cooperative freeze acknowledged |
| Coordinator-only role | Source history preserved; top child named as normal future executor; requested tool/registration capability verified or its actual limitation reported |
| No accidental maintenance | No new PR, rebase, push, public action, active setup lease, reset, auto-stash, source archive or metadata replacement |
| Durable retry map | Every created child/result recorded; blocked slots retained; app URLs taken from the app inventory |

Do not mark `owner-light-ready` merely because all children share a project.
Sharing a common Git directory is useful but optional; actual writer scope and
host/local-path/record accessibility are the requirements.

If a prerequisite fails, preserve partial setup and report the exact missing
invariant. Do not quietly downgrade an explicitly requested good-path setup to
remote/owner-driven sessions and call it complete. Ask whether to use a different
supported setup only when the user must choose.

## Required scenarios

| Scenario | Required outcome |
| --- | --- |
| "Create a PR stack" only | Do not create sessions; use the appropriate Git-stack workflow |
| "Please author a skill that creates session stacks" | Write the skill only; no live child allocation |
| Fresh coordinator + explicit session stack | Allocate one same-project owner per selected layer and preserve existing PRs |
| Implementation session + explicit spinout | Allocate every layer including top; complete indexed context transfer; source becomes coordinator-only |
| Current implementation used as top owner | Reject as incomplete spinout |
| Two configured projects for the same repo | Use the exact current project, not a repository-only lookup |
| Ordinary PR chain without native stack metadata | Verify supplied order/bases and record owner-local Git capability; do not create a public native stack |
| Required `gh stack` registration absent in executor clone | Supported local import preserving public identity, or explicit blocked capability; no silent tool substitution |
| `create_session` creates generated branch | Preserve it, safely attach the existing PR branch; do not claim base_branch adopted a PR |
| First child on wrong host/project | Stop before allocating the rest; preserve the recorded slot |
| Missing/stale app PR binding | Surface it; do not create a new PR or fabricate a badge |
| App branch metadata contradicts Git checkout | Reconcile through supported tooling or leave setup blocked |
| Dirty source or uncommitted follow-up | Preserve it and resolve checkpoint/scope before allocation |
| Relevant committed unpublished follow-up | Spinout preserves and labels it; bootstrap does not silently import it |
| Existing active layer owner | Obtain a real handoff to the new child; reuse only this setup's matching slots unless adoption is explicitly requested |
| Active/pending owner-light operation | Keep setup gate closed; no lease expiry or manual JSON clearing |
| Branch occupied in unrelated worktree | Stop, never force checkout or detach that worktree |
| Merged/closed native stack entries | Retain history; clarify selected owner scope; do not recreate deleted branches |
| Partial/ambiguous allocation result | Reconcile known app slots; no blind second creation |
| Inaccessible artifact or missing rationale | Report real limitation; never claim complete original context |
| Duplicate setup invocation | Verify/reuse known matching children and packet identities |
| Remote head advances mid-setup | Reconcile affected snapshots/packets in a new revision; preserve existing child work |
| Upper PR predates the lower layer's latest tip | Preserve pinned snapshots and historical ancestry; record needs-restack without rebasing during setup |
| Idle notification without setup receipt | Not success; no polling or acknowledgment chatter |

## Authoring checks

Verify frontmatter/name, supporting links, examples/tool fields, code-fence balance,
ASCII encoding, and no trailing whitespace. Review the actual tool schemas for
project/base-branch/attachment/host-selection assumptions. Do not run a live setup
merely to validate the skill unless the user separately requests a session stack.

After genuine execution, report only verified topology, handoff and readiness.
A creation result is not a configured layer owner; a context packet is not proof
the child loaded it; a good topology is not standing rebase/publication permission.
