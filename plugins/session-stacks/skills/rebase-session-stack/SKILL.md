---
name: rebase-session-stack
description: >
  Coordinate an existing session-owned PR stack: fetch/recheckout published tips,
  replay affected descendants, or rebase onto trunk, with optional feedback and
  authorized publication. Do not use for creating, splitting, reordering, or
  merging stacks, or ordinary single-branch rebases.
---

# Rebase a session-owned PR stack

Use one coordinator and each layer's existing owner. Central Git mutation requires
an authorized ownership handoff; otherwise execute sequentially in owner sessions.
Reuse sessions, PRs, stack identity, and ordered membership, including merged layers.
Never commandeer uncommitted work or access a forbidden main checkout.

For an explicitly requested **new session stack**, use `create-session-stack`
first. Do not create replacement layer sessions as part of ordinary rebasing,
PR-stack work, or owner-light maintenance.

## Route before loading details

Record feedback and publication authorization separately from the execution mode:

| Mode | Work | Read from `git-protocol.md` |
| --- | --- | --- |
| `checkout-sync` | Fetch published tips; update requested owner checkouts only | A, C, E; F's tracking-refresh paragraph |
| `descendant-replay` | Replay affected descendants onto a pinned parent; no trunk refresh | A-E; F only if publishing |
| `trunk-rebase` | Fetch trunk once; rebase the requested stack | A-E; F only if publishing |

Choose coordination policy independently: **owner-driven** is the fallback.
Opt into [owner-light](owner-light.md) only for same-host/runtime local worktrees,
Python 3.9+, accessible durable leases, and owners that honor the freeze on future
turns. Separate clones are allowed. Owners acquire narrow scopes once; executor
receipts then replace mechanical handback/sync messages. Do not use idle status,
cross-host paths, or message delivery as ownership authority.

Read [operation state](operation-state.md) once. Load only applicable protocol
sections and the current [handoff template](handoffs.md); recovery section G is
conditional. Do not read helper source just to execute it. Load repository skills
when their work starts, and `gh-stack` when that tool is requested.

## Discover and freeze

Discover sessions once; retain exact IDs and use targeted reads thereafter. In a
Side chat, read the main transcript first. Resolve order from live stack membership
and PR bases, not names or sidebar nesting. Match owners by repository, PR, and
branch; verify worktree/common-directory identity. Shared clones share refs.

Choose the executor explicitly. A coordinator owning the top layer normally executes
in its own worktree and records its owner acknowledgments locally, without self-
messaging. Otherwise prefer an existing layer owner, normally the top owner, as
executor; the coordinator still manages gates. An authorized, separately cloned
integration copy is also valid. Do not create a replacement session/worktree just
to obtain an execution branch.

Maintain the operation ledger with authority, topology, expected SHAs, and evidence.
Cached topology is not a substitute for live cleanliness, occupancy, expected-ref,
Git-operation, or remote-lease checks at mutation boundaries.

For replays, freeze historical parent boundaries before importing feedback. For
`trunk-rebase`, pin the actual fetched trunk SHA: "latest" means that snapshot, not
a moving target. Later trunk drift alone does not restart integration. A new refresh
requires user direction or a demonstrated blocker and a new generation.

Parallelize reads and independent feedback, not stack rewrites or shared-clone
writes. Assign one costly integration build window. Owners finish owned processes,
commit requested changes, verify full cleanliness, detach **Git HEAD**, and report
`PREPARED_DETACHED`. Never detach the app session, archive it, or infer readiness
from idle status. Wait for matching reports, not polling.

## Execute the selected mode

**Checkout-sync:** fetch only requested branches into fresh transfer refs; verify
remote/PR identities and parent ancestry. Preserve old refs; update detached,
unoccupied owner branches with CAS, or verify already-at-target refs. Attach, sync
only their tracking refs, and report `RELEASED` together. No rebase, new commits,
push, feedback sweep, or integration build is needed merely to copy existing tips.
Do not overwrite unpublished follow-ups without explicit replacement authority.

**Replays:** import only affected prepared tips. Use fresh transfer refs and
create-only backups; shared clones need verification, not duplicate transfers.
Freeze every branch the selected tool may touch. Run `gh stack rebase` from an
authorized registered branch, never detached HEAD or an unrelated scratch branch.
Check installed semantics once per operation/version, registration, remote, and
resume behavior. Never force-update occupied trunk, edit private tool state, or
silently substitute another execution mode.

Resolve conflicts against current upstream semantics; preserve logical commits and
credit. Review rerere, range-diffs, ancestry, and non-equivalent changes. Keep
non-executing owners detached until integration finishes, except a specific owner
making a correction. The executor's registered checkout is an execution lease,
not an early handback or permission to resume unrelated edits.

## Keep review and validation bounded

Without requested feedback, focus review on replay resolutions, changed ranges,
and integration effects. Do not repeatedly re-review equivalent existing code.
Report independent findings separately; fix defects caused by or necessary for
this operation in their correct layer. Requested feedback still covers all pages
of reviews/comments, records dispositions, and avoids duplicate or empty commits.

Use repository build/test and review guidance. Check directly related generated
outputs before costly integration work. Record actual commands, snapshot identities,
counts, logs, limitations, and explicit waivers. Reuse results only when relevant
source/build inputs are provably identical. A later waiver does not erase earlier
runs, and patch equivalence is not a behavioral test.

For a necessary correction, advance generation, validate the owner's exact patch,
have it committed and detached, then replay affected descendants **without another
trunk refresh**. Reconfirm snapshot equivalence and invalidate affected evidence.

## Hand back, publish, release

For local-only work, combine verified final attachment and release; state unpushed.
For publication, require all final `ATTACHED_FROZEN` acknowledgments or owner-light
executor receipts first. Recheck
affected remote leases, PR heads/bases/state, and stack membership. Use the authorized
lease-protected command; do not assume atomicity. Reconcile every remote result,
including partial failures. Then serialize tracking refreshes per common directory
and require clean attached owners with matching local/tracking/published SHAs.

Owner-light release is durable before its one compact notice. Owners verify the
matching terminal lease/checkpoint on their next substantive turn; no acknowledgment-
only turn is needed. Pending/crashed actions keep owners frozen. Scoped leases do
not replace fresh Git guards or user publication authorization.

The executor's verified final checkout counts as its owner acknowledgment. In a
shared clone, release an executor-occupied branch before its distinct owner attaches.
Keep a registered execution branch available through publication without double
checkout; if that cannot be arranged, delegate execution/publication to the owner.

Post authorized pending replies once, after delivery is verified, using the correct
inline/general endpoint and disclosure policy. Follow explicit reply/resolve scope.
Preserve recovery refs; remove only known disposable artifacts. Never rerun CI to
classify failures.

Return only changed results or blockers. Ignore duplicate notifications without a
gate transition. A patch is not a commit, a rebase is not a push, and idle is not
release. Restore the ledger and current instructions after compaction, not the
entire transcript.
