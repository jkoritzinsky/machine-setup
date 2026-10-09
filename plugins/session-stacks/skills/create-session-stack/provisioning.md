# Project-local provisioning and ownership

Use the current app tool schemas; do not infer capabilities from old orchestration
examples. This skill authorizes no calls until SKILL.md's explicit session-stack gate
is satisfied. Authoring/testing the skill is not a request to execute it.

Resolve the companion [Git protocol](../rebase-session-stack/git-protocol.md),
[owner checklist](../rebase-session-stack/owner-checklist.md), and
[lease helper](../rebase-session-stack/scripts/owner-light.py) from this installed
skill directory, not a personal installation. Owners receive only the short
checklist, concrete helper paths, and their indexed layer packet.

## 1. Verify the project and stack

Use current session/project metadata for the exact project ID; consult `list_projects`
only when it is unknown or ambiguous. Projects with identical GitHub repositories
may have different clones or hosts. Children belong to the coordinator's project,
not whichever project a repository-wide PR lookup happens to select.

Read existing sessions once, then target their exact IDs. Keep source/existing-owner
sessions in the manifest with their authority and worktree/common-directory identity.
Existing independent owners must hand off before a new child takes their branch.
Reuse only a matching child already allocated by this setup on retry, unless the
user explicitly changes the request to adopting existing sessions. Do not silently
substitute an unrelated parent tree for the requested new coordinator's subsessions.
In a Side chat, coordinate with the real source session; neither an idle Side chat
nor a quiet branch proves the main implementation has stopped.

Discover native stack order using supported read-only tooling and live PR bases.
The installed `gh stack view --json` inspected while authoring has **no PR/stack
selector**: it describes the current locally registered stack. A fresh coordinator
may have no registration. Do not invent `view <PR>` syntax or run checkout/unstack
merely to discover membership. Use supplied PR/stack links and supported read-only
GitHub lookup; if complete membership cannot be established, ask for the PR list.
Do not treat an inferred chain as verified native membership.
For an explicitly supplied ordinary PR chain, verified bases can establish its
order without native registration. Record that distinction; never create a public
native stack as a discovery shortcut.

For each selected PR, read live state, base, head repository, full head ref and SHA.
Fetch narrowly into fresh refs, without moving owned branches, tags, tracking refs,
FETCH_HEAD or occupied trunk. Verify historical parent boundaries and code ranges.
Do not confuse a missing old SHA after replay with a lost patch.
Keep the historical parent/fork-point separate from today's live base tip. An
existing upper PR may need restacking after its lower layer advanced. Preserve
its pinned head, verify its historical ancestry, and record `needs_restack`;
setup does not authorize rewriting it or claiming latest-parent alignment.

Merged/closed PRs remain historical entries. Ask about owners for such entries when
scope is unclear; do not create deleted branches automatically. Reject ambiguous
forks or shared branch identities until scope/ownership is resolved.

## 2. Select the source snapshot

`bootstrap` normally uses the pinned published heads. Do not silently add local
unpublished commits discovered in another owner session. Transfer its context and
ownership only after a real handoff.

`spinout` preserves the implementation's committed layer tips, including unpublished
follow-ups belonging to those layers. Record published heads separately, compare
the ranges, and preserve authorship, branch boundaries and source recovery refs.
If local and published tips diverge ambiguously, resolve the intended snapshot before
creating sessions. Do not replace local work with the remote merely to match a PR.

Uncommitted/unsaved source work cannot be transferred by fetching commits. Preserve
it and ask how to checkpoint or retain it; do not auto-commit, stash, reset, broadly
copy a dirty worktree, or declare all context delivered while omitting that work.
Pending review text, test failures and excluded prototypes belong in the packet,
but do not authorize implementing them during setup.

Verify all affected source worktrees, branch occupancy, owned processes, Git
operations, active owner-light records, and supported stack-tool/server operation
state. Resolve existing owners rather than rewriting their refs under them.
The original implementation must release **every selected layer, top included**,
with Git-detached HEAD where needed. This is not app/sidebar detachment or archival.
Do not touch forbidden main-checkout files to make that happen.

## 3. Persist an allocation manifest

Keep a session-scoped JSON artifact accessible on the verified host. A SQL table
can track coordinator progress, but children cannot assume access to that database.

```text
setup:
  schema, setup_id, mode, explicit_user_session_stack_request
  coordinator_session_id, project_id, logical_repository, execution_environment
  source_session_ids, source_worktrees/common_directories, source_release_evidence
  native_stack_identity, ordered_membership_including_history
  selected_layer_ids, selected_snapshot_policy
  setup_status, future_executor_session_id

layer:
  stable_layer_id, ordinal, repository, PR, title, state
  head_repository, full_head_ref, published_sha, pinned_source_sha
  historical_parent_ref/sha, live_base_ref/sha, ancestry_status
  source_worktree/ref
  packet_path/hash, supporting_artifact_paths/hashes
  source_owner_id, source_backup_refs, source_release_evidence
  allocation_status: planned | created_idle | bootstrapping | verified | blocked
  child_session_id, exact_app_url, child_project_id, child_worktree
  child_generated_branch/head, child_common_directory/environment
  expected_old_owned_ref, child_transfer/backup_refs
  checkout_receipt, context_acknowledgment, owner_light_capability_evidence
  app_PR_binding_status, blocked_reason
```

Save a creation result before any follow-up. On tool timeout/ambiguous creation,
reconcile against the exact app inventory and setup slot; do not blindly retry.
Reuse an already matching verified child. A lost notification does not require
another child. Record historical layers without pretending they have active owners.

## 4. Allocate idle worktree sessions

`create_session` can target the exact project; its `worktree` mode creates an
isolated checkout with a generated branch. It does **not** document adoption of
an existing PR branch. Do not assume `base_branch` changes that: it supplies the
base for a new worktree branch.

```json
{
  "name": "<short setup/layer/PR label>",
  "execution_location": "local",
  "workspace_type": "worktree",
  "coordinate_with_creator": true,
  "notify_on_idle": "once"
}
```

Omit `project_id` for the current project, or pass its exact verified ID. Omit
`base_branch` and `kickoff`; no owner starts acting before its identity and
concrete handoff are ready. Do not guess model/host overrides or copy unrelated
model preferences into children.

Validate the first returned project/worktree before creating all other slots.
The current `create_session` schema has no arbitrary remote-host selector.
`local` is not proof of the intended host when the caller is remote: verify the
actual child runtime and access paths. Windows and WSL are different environments.
If metadata cannot prove the runtime, send that first child its single bounded
bootstrap task and require its environment receipt before allocating the rest.
It must check the packet's expected environment before any checkout/ref mutation.
If the app cannot create on the required host/project, leave the slot blocked;
do not choose cloud, invoke wsl.exe, or route through another project silently.

`open_pr_session` has no explicit `project_id` selector and may return an existing
session. Do not use it as a substitute that can violate project identity or reuse
the implementation session as the top owner. Use supported binding only when the
returned ownership and project are known to satisfy the request.

The app may not expose an existing-PR binding action for a created worktree session.
Keep the exact PR-to-owner mapping in the manifest and kickoff; label the session
with its PR. Do not fabricate a UI badge, edit app databases/configuration, or
create a new PR to obtain a link. Surface missing UI association separately.

## 5. Prepare concrete checkout authority

Inspect each idle child using its returned worktree path, not a guessed directory.
Verify its clean generated branch/head, Git common-directory relationship, and
actual access to the packet, helpers and source refs. Do not read a main checkout.

Establish the exact old value of the owned branch in that clone. If it is occupied
or contains unexpected/unpublished work, stop and reconcile. An arbitrary observed
SHA is not permission to overwrite it. Preserve any authorized stale copy with a
fresh backup before CAS. Same-project worktrees may share refs, so different slots'
ref operations are serialized by common-directory identity.

For an absent owned ref, narrowly import the pinned source into a fresh transfer
ref, verify it, and create the owned branch with create-only `update-ref --no-deref`
and the correctly sized zero OID. Do not replace an existing ref or bypass occupancy.
For an existing ref, follow the guarded transfer/CAS protocol in
`rebase-session-stack`; already-at-target is verification, not another update.

The child can then detach its clean generated checkout and attach its assigned
existing PR branch. Its full HEAD/ref must equal the pinned source and parent
ancestry must match the selected snapshot. Retain the generated branch as recovery
metadata; do not rename branches with raw Git or delete them to evade collisions.
If app branch metadata does not reflect the verified checkout, use a supported
reconciliation action or report a blocker rather than falsifying the owner map.

Bootstrap is read/checkout work only. No code edits, baseline builds, new commits,
rebase, tracking "repair" with pull, publication, PR edits or CI actions.
For unpublished tips, stale published/tracking divergence is intentional and
must be labeled, not synchronized away.

## 6. Minimal owner kickoff and one acknowledgment

After the manifest slot and checkout plan are concrete, send one immediate
`send_session_message`, explicitly using an execution mode rather than silently
leaving the owner waiting for plan approval. The [handoff](handoff.md) template
is a complete bounded bootstrap task. Read actual human gates before answering.

Children have fresh conversations; give them their own packet and necessary
cross-layer contracts, not the full coordinator transcript or sibling packets.
Use direct same-host artifact paths only after accessibility is verified. If the
available tool supports attachments, follow its staging schema; do not assume
arbitrary artifact paths qualify as attachments or upload to GitHub for transport.

Wait for the real acknowledgment, not idle polling. Verify context identity,
actual checkout, same project/repository/environment, owner-light helper access,
and cooperative freeze understanding. A required helper/runtime or artifact missing
on a child is a blocker, not permission to claim owner-light readiness.

Once every selected slot is verified, record the coordinator as coordinator-only
and normally designate the top owner as the future registered-branch executor.
No extra integration child is needed. Do not leave an active setup lease merely
to advertise readiness. Future maintenance needs fresh user authorization and
the real owner-light acquisition barrier.
Record whether that executor can use the existing `gh stack` registration or only
owner-local Git. Same-project worktrees may inherit local registration through their
shared common directory; separate clones may not. For a requested `gh stack` workflow,
verify/import local registration only through supported noninteractive tooling
that preserves the public identity/order; never edit private extension state or
run unstack/link/submit to fabricate readiness. If that requirement cannot be met,
leave that capability blocked. Do not silently substitute Git for requested tooling.

## Partial setup and preservation

Keep known children, receipts, recovery refs and original source context on failure.
Resume only blocked/unfilled slots. Do not delete/archive a source or duplicate a
child to silence notifications or repair state. The standard verified-empty-child
archival rule may apply only when its full conditions are met; otherwise require
explicit user direction. Never assume clean means no persistent work.

If published heads move during setup, distinguish intentional pinned local work
from remote drift. Reconcile affected snapshots and packets in a new setup revision;
do not overwrite a newly bootstrapped owner or restart the whole stack blindly.
