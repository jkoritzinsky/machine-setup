# Layer-specific context handoff

The packet is the durable layer context; the kickoff is a compact index and a
bounded setup task. Put both in session artifacts, not product source. Full
conversation forks and repeated stack-wide narratives defeat owner-light setup.

## Packet contract

Use one packet per layer with stable headings. Include all applicable information,
explicitly labeling `unknown`, `not run`, `not applicable`, or `pending` instead of
inventing facts or silently omitting a section:

```text
# Layer <ordinal> - <concern> - <repository>#<PR>

## Identity and ownership
Setup ID/revision, coordinator ID, source owner, exact project/repository
PR URL/state, head repository/ref, published full SHA, pinned source full SHA
Snapshot policy, parent ref/SHA, historical replay boundary, owned commit range
Live base tip and aligned/needs-restack status, separately from historical ancestry
Owner session/worktree supplied at allocation, setup status, no active lease

## Purpose and scope
What this layer implements; owned files/symbols/components
What belongs to lower/upper layers; excluded prototypes and unrelated work
Definitions of done and public/API/compatibility constraints

## Implementation and rationale
Architecture, control/data flow, important invariants and lifetime contracts
Significant decisions and alternatives rejected, with reasons
Relevant upstream changes and conflict resolutions; don't repeat obsolete designs

## History and provenance
Layer-only commits, imported/copied code, required author/coauthor credit
Unpublished follow-ups, prior replays/patch-equivalence evidence, backups
Exact source turns/checkpoints/commits for reasoning, not unsupported summaries

## Review and unfinished work
Every actionable recommendation and disposition; exact inline/comment IDs
Pending replies/drafts and publication scope; already delivered items
Known bugs/blockers, user decisions, experiments, and remaining work
Uncommitted/unsaved state accounted for in the source readiness gate

## Validation
Build/test/benchmark commands, runtimes/architectures/configurations/flags
Exact snapshots/blob/tree identities, passed/failed/skipped counts, logs
Baseline identity/reuse proof; limitations, waivers and failed investigations
Distinguish historical evidence from fresh validation and overlapping selections

## Artifacts and source index
Necessary repros, scripts, logs, diagrams, design notes and generated outputs
Verified paths/hash identities, source/session/turn provenance, accessibility
Preserve the full supporting evidence outside the kickoff and conversation

## Operational handoff
Concrete pinned checkout instruction and authority; expected old refs
Same-host owner-light owner checklist/helper/record paths and future freeze rule
No initial lease; no implied edits, rebase, push, PR creation or public comments
Future executor and relevant lower/upper interface dependencies
```

Keep quoted user requirements exact where meaning would otherwise be lost. Preserve
API approvals, author credit and publication restrictions. Do not include credentials,
unrelated personal data, excluded file contents, or other sessions' irrelevant history.
Obey content-exclusion restrictions; do not reconstruct blocked context from caches.

The recipient must be able to continue its layer without the coordinator remembering
hidden facts. Links alone are insufficient for known decisions: summarize the
decision/invariant and retain a precise source/evidence reference. Conversely,
megabytes of transcript/log text do not belong in the packet body when an indexed
artifact supplies the complete evidence.

## Bootstrap packet

Start from the live PR and pinned layer range: read code, PR description, relevant
review threads/comments, linked design/API issues, and available local artifacts.
Do not guess original implementation rationale. Label missing historical context
and include the verified sources the owner can consult later.

Include interface constraints inherited from lower layers and the expected effects
on upper layers. This is preparation, not a new independent PR review or CI triage
for every owner. Do not start expensive builds or fix feedback during setup.

## Spinout packet

Use the actual implementation conversation, checkpoints, source/ref history and
its complete artifact index. Prefer time/session/ref-bounded history queries; use
checkpoint summaries to locate relevant turns rather than loading the whole
transcript repeatedly. Include the current source owner's decisions, not stale
earlier plans presented as final.

Build a coverage map from the original implementation to packets:

```text
source decision/task/artifact -> owning layer(s) or coordinator-only context
pending recommendation -> disposition and recipient
validation result -> exact tested snapshot and applicable layer(s)
unpublished commit -> owned layer, source branch/ref and transfer evidence
```

Every relevant item must have a destination or an explicit exclusion reason.
Shared contracts go in each affected packet as concise invariants with one source
reference; unrelated sibling implementation details stay with their own layer.
Retain full global history with the coordinator. Include the top layer's complete
packet and allocate its own child; neither the coordinator nor an unassigned
original top checkout is an acceptable substitute.

Before release, confirm each child loaded its packet and necessary supporting
artifacts. Any inaccessible item is a visible context limitation/blocker, not
an implied complete handoff. Source artifacts are preserved even after copies
are verified in child-accessible storage.

## Single setup kickoff

Populate concrete values after the idle child is verified:

```text
SETUP_ONLY setup=<id> revision=<r> layer=<ordinal>
You own <repository> PR <number>, branch <full-ref>, in project <exact-project-id>.
Coordinator=<exact-id>. You are a separate layer owner, not a new PR author.
Expected execution environment=<verified host, OS/runtime identity>.
Packet=<verified-accessible-path>, identity=<hash>; read its applicable sections
and required artifact index. Owner checklist/helper=<verified paths>.

Pinned source=<full-sha>; published=<full-sha>; historicalParent=<ref/full-sha>.
Live base=<ref/full-sha>; restack status=<aligned/needs-restack>.
Source transport=<authorized worktree/ref or remote/ref>.
Generated branch/head=<values>; expected owned ref=<sha or create-only absent>.
Checkout authority=<concrete narrow transfer/create/CAS/attachment instruction>;
common-directory write window=<assigned actor/window>.

Verify project, repository and actual host/runtime; stop before checkout/ref
mutation if the execution environment differs. Check full cleanliness,
Git/stack-tool/lease state and branch occupancy. Follow guarded Git protocol;
preserve recovery refs. Do not overwrite unexpected work or reapply a stale CAS.
Verify owned symbolic HEAD/ref, pinned SHA, parent ancestry and app branch metadata.

No source edits, commits, build/test, rebase, push, new PR, public-stack mutation,
app/private-extension metadata rewrite,
CI action, public reply, source deletion, or active lease acquisition during setup.
Accept the cooperative owner-light rule: check the durable record before future
mutation, queued work, automation, restart or compaction; do not infer release.

Return one setup receipt with session/project/repository IDs, worktree/common-dir/
environment, actual branch/head, clean and no-operation evidence, packet/artifact
identities loaded, owner-light prerequisites/cooperation, app PR binding status,
and any exact blocker. Then await substantive work; no starting/received chatter.
```

The setup receipt is not a lease-acquisition receipt or evidence of new validation.
If a child is human-gated, the coordinator reads and resolves the real question/plan
within existing authority; do not send repeated reminders to a blocked session.
