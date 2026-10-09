# Git protocol and recovery

These are command templates, not a script to paste blindly. Execute in the actor's
authorized worktree, substitute verified values, and check every exit code and
postcondition. Use native filesystem paths: Windows paths in PowerShell and Unix
paths in Bash. Git refs and refspecs retain their normal `/` separators.

Do not use `Invoke-Expression` or concatenate untrusted API text into executable
shell code. Validate branch names with `git check-ref-format --branch`, full refs
with `git check-ref-format`, object IDs as full hexadecimal IDs for the repository's
object format, and repository/remote names before interpolation. Pass dynamic values
as arguments and quote them. Read available tool schemas instead of guessing them.

In PowerShell, `$ErrorActionPreference = 'Stop'` alone does not reliably catch native
command failures. Capture `$LASTEXITCODE` immediately and stop on an unexpected code.
For commands with meaningful nonzero results, distinguish those results from errors.

Read only the sections selected by SKILL.md; load G only for recovery. Locate
headings once and use bounded file ranges rather than repeatedly reading this file.

Owner-light mode uses the optional Python lease/executor companion described in
[owner-light.md](owner-light.md). Its whole-action clone locks and durable receipts
replace owner-driven mechanical messages, not the checks below. Use owner-driven
mode when same-host/local-filesystem/cooperative-freeze requirements are not met.

Choose `scripts\git-handoff.ps1` on PowerShell 7 or `scripts/git-handoff.sh` on
Unix with Bash 3.2+. Both batch read-only checks or perform one authorized detached
transfer/checkout and return the same compact JSON fields. The Bash helper needs
Git and standard Unix utilities, not PowerShell, Python, or jq.

```powershell
& <skill-path>\scripts\git-handoff.ps1 -Mode Inspect -Worktree <path> -Branch <full-ref>
& <skill-path>\scripts\git-handoff.ps1 -Mode Attach -Worktree <path> -Branch <full-ref> `
    -ExpectedHead <detached-sha> -ExpectedOld <branch-sha> -Target <final-sha> `
    -Operation <id> -Generation <g> -Source <source-worktree-or-remote> `
    -SourceRef <full-source-ref> -MutationAuthorized -Quiesced
```

```bash
bash "<skill-path>/scripts/git-handoff.sh" --mode inspect \
    --worktree "<path>" --branch "<full-ref>"
bash "<skill-path>/scripts/git-handoff.sh" --mode attach \
    --worktree "<path>" --branch "<full-ref>" \
    --expected-head "<detached-sha>" --expected-old "<branch-sha>" --target "<final-sha>" \
    --operation "<id>" --generation "<g>" \
    --source "<source-worktree-or-remote>" --source-ref "<full-source-ref>" \
    --mutation-authorized --quiesced
```

Omit source arguments when the branch is already at target. The switches attest
to authority, the assigned exclusive write window, finished owned processes, and
checked stack-tool state; the helper cannot discover those facts. It checks local
Git state, but does not establish ancestry, authorize access to another worktree,
acquire a coordinator lease, detach an owner, rebase, push, or sync tracking refs.
Use the explicit protocol if neither shell is available. Read-only Inspect does not
create Git recovery refs; both helpers remove only their own disposable scratch.

Maintainers can exercise the helper without touching a real stack:

```powershell
& <skill-path>\tests\git-handoff.Tests.ps1 -ScratchRoot <existing-session-artifacts-directory>
```

```bash
bash "<skill-path>/tests/git-handoff.Tests.sh" "<existing-session-artifacts-directory>"
```

The Bash fixture runner additionally requires Python 3 for JSON assertions.
The tests create and remove only their uniquely named disposable fixture directory.
On helper failure, retain operation-scoped recovery refs and inspect actual state;
never reset or delete an owner's work to retry.

## A. Read-only topology and release checks

```text
git status --porcelain=v1 --untracked-files=all
git symbolic-ref --quiet --short HEAD
git rev-parse HEAD
git rev-parse <full-owned-branch-ref>
git rev-parse --path-format=absolute --git-common-dir
git worktree list --porcelain -z
git remote -v
git rev-parse --git-path rebase-merge
git rev-parse --git-path rebase-apply
git rev-parse --git-path MERGE_HEAD
```

Empty porcelain output demonstrates cleanliness only if the command succeeded.
`symbolic-ref --quiet` exits 1 for detached HEAD; other failures are not detachment.
Resolve the operation paths and check their existence rather than assuming `.git`
is a directory. Include any documented stack-tool operation state in the preflight.
Do not manually read or modify forbidden main-checkout files to inspect that state.

Inspect every worktree record in the common directory for occupancy of an affected
branch. An unrelated worktree using that branch is a blocker, not permission to
detach it. Owner acknowledgment and occupancy checks complement each other.
Compare canonical common-directory identities, accounting for path casing and
symlink/junction aliases; different spellings alone do not prove separate clones.
Check queued/server-side stack operations and live PR state using supported tools.

Finish owned builds before detaching:

```text
git switch --detach HEAD
```

Then re-run cleanliness, symbolic-HEAD, and head/ref checks. Record exact SHAs, not
abbreviations. Do not use destructive reset, branch deletion, or auto-stash to reach
a "clean" state.

For checkout-sync, an already clean, attached, fully synced owner may acknowledge
a verified no-op. Otherwise acquire its detached handoff before changing its branch.
Checkout-sync is not permission for source edits or a new rebase.

## B. Freeze history before moving refs

Keep these values distinct:

| Value | Meaning |
| --- | --- |
| Starting owner head | What the layer session had before this feedback round |
| Prepared head | What the owner committed and released for integration |
| Coordinator old head | Expected-old value for updating the coordinator's copy |
| Old parent/fork-point | Boundary excluding lower-layer commits from this layer's replay |
| Remote head | Independently recorded publication lease expectation |
| Rebased head | Candidate or final result for the current generation |

Use history, PR snapshots, and merge-base/ancestry checks to prove the replay range:

```text
git merge-base --is-ancestor <old-parent-sha> <prepared-head-sha>
git log --oneline <old-parent-sha>..<prepared-head-sha>
git rev-list --min-parents=2 <old-parent-sha>..<prepared-head-sha>
```

Exit 1 from `merge-base --is-ancestor` means the ancestry claim is false, not that it
was verified. Unexpected merges or ambiguous boundaries need investigation before
linear replay. Merged/squash-merged lower PRs require their historical boundaries;
never replay their old commits simply because their SHAs are absent from new trunk.

Preserve both original and prepared tips as needed. Create unique operation- and
generation-scoped refs; generate the zero OID at the length of the repository's OIDs:

```text
git update-ref --no-deref <fresh-backup-ref> <sha-to-preserve> <all-zero-oid>
git rev-parse <fresh-backup-ref>
```

An existing backup is a collision to verify or replace with a new name, not a ref
to overwrite. Keep recovery refs outside the ordinary branch namespace.

## C. Cross-clone transfer without a public push

Use only an owner-reported, accessible source worktree/ref. If environments cannot
access each other, arrange an authorized bundle/transport or a different execution
plan. Never assume a local path works in a cloud session or publish prematurely
just to transport objects.

The receiving actor allocates a fresh transfer ref for this direction/generation:

```text
git fetch --quiet --no-tags --no-write-fetch-head --no-recurse-submodules --no-prune --no-prune-tags --no-auto-maintenance --no-write-commit-graph --refmap= <source-worktree-or-remote> <source-ref>:<fresh-transfer-ref>
git rev-parse <fresh-transfer-ref>^{commit}
```

Require the imported commit to equal the sender's acknowledged full SHA. The fetch
must not target the owned branch directly, sibling branches, remote-tracking refs,
or trunk. `--no-write-fetch-head` avoids an unnecessary shared `FETCH_HEAD` write.
`--refmap=` suppresses opportunistic configured remote-tracking updates when using
a named remote. Disable configured pruning, tag pruning, automatic maintenance, and
commit-graph writes to keep the assigned write scope narrow. Verify installed Git
supports these controls. Use fresh refs rather than forcing an older transfer.

Before a branch update, revalidate cleanliness, expected branch tip, detachment,
and common-directory occupancy. With the existing writer lease held:

```text
git update-ref --no-deref <full-owned-branch-ref> <verified-new-sha> <expected-old-sha>
git rev-parse <full-owned-branch-ref>
```

The coordinator may update only its authorized integration-copy refs. Each owner
updates only its own branch in its separate clone. No actor rewrites sibling refs
in the owners' shared clone. In owner-light mode, the explicitly designated executor
may update only acquired owner scopes under their durable lease; other refs remain
out of scope. Reject symbolic branch aliases; use `--no-deref` to
avoid redirecting a guarded ref write to another ref.

When the current ref already equals the new SHA, verify the operation/generation and
worktree state, then continue without rewriting it. Any third SHA is unexpected
work: stop and reconcile. CAS is not a substitute for the occupancy check; Git can
update a branch ref even when another worktree has it checked out.

For same-common-directory handoff, objects and refs are already shared. Verify the
new SHA and proceed; no fetch or second branch update is needed.

## D. Central rebase and verification

Check the installed interface and semantics once per operation/tool identity.
Read push help only when publication is in scope:

```text
gh stack rebase --help
gh stack push --help
gh stack view --json
```

Run from an authorized registered stack branch after every affected owner has
released it. Do not create an unrelated temporary branch as the resume anchor.
Do not silently install, update, or patch the extension to make a command work.

Executor selection is independent of coordination. Prefer the coordinator's owned
top-layer worktree; otherwise use an existing owner executor or an authorized
separate-clone integration copy. Record executor session, worktree/common directory,
registered branch, and its execution/publication lease before taking the checkout.

```text
git switch <registered-executor-branch>
gh stack rebase --remote <remote> <registered-executor-branch>
```

Honor an explicit no-trunk/pinned request instead of the regular example. Prevent
interactive editors/prompts using platform-appropriate process-local settings.
Inspect `rebase.updateRefs`: automatic updates must not move unrelated branch or
backup refs. Apply any required override only to the executor process and its Git
children; do not rewrite global/shared Git configuration.

Record the trunk actually used by the tool and keep that SHA fixed through
corrections. Do not fetch a newer trunk just because publication is later.
If the tool cannot honor an already pinned target, reconcile its behavior before
mutation rather than claiming the ledger's SHA was used.

On conflict, inspect the stopped commit and affected files:

```text
git rebase --show-current-patch
git diff --name-only --diff-filter=U
git diff --check
git add -- <resolved-file>
gh stack rebase --continue --remote <remote>
```

Continuation may discover a new conflict and return a generic failure instead of
the initial conflict code. Read the command output and current Git state before
deciding what happened. Never use `rebase --skip` without proving that the entire
commit's intent is already present.

After rebase:

```text
git merge-base --is-ancestor <actual-trunk-sha> <new-bottom-head>
git merge-base --is-ancestor <new-parent-head> <new-child-head>
git range-diff <old-parent>..<prepared-head> <new-parent>..<new-head>
git diff --check <new-parent> <new-head>
```

Inspect every non-equivalent range-diff result. A contextual hunk change can be
benign, but commit counts or a green `needsRebase` flag do not prove preservation.

Focus source review on those results, conflict resolutions, and integration effects.
Do not reopen an unchanged layer's entire implementation unless feedback review
was requested or evidence requires it. Preserve mandatory review of actual edits.
Independent findings are reported separately, not silently added to the operation.

For a validated follow-up after trunk was already refreshed, import the correction
and run the installed tool's appropriate no-trunk replay:

```text
gh stack rebase --no-trunk --remote <remote> <registered-executor-branch>
```

Treat all branches the tool may touch as frozen, even if only some heads actually
change. Recheck the unchanged pinned trunk and the final validation snapshot.

If the agreed workflow instead uses owner-local Git, the underlying replay shape is:

```text
git -c rebase.updateRefs=false rebase --onto <new-parent> <old-parent> <owned-branch>
```

This is an alternative execution mode, not a silent fallback from a specifically
requested `gh stack` operation. Prove boundaries and coordinate sequentially first.

## E. Final checkout and Windows path limits

Once the final ref is verified and unoccupied:

If executor and owner are distinct worktrees in one clone, the executor must
release that branch first. All publication acknowledgments must still be possible
while the executor has a registered branch available. Delegate to a layer owner
when every registered branch would otherwise be occupied by its owner. If the
executor is itself that layer's owner, its exact clean final checkout is the owner
acknowledgment; no self-message or redundant second checkout is needed.

```text
git switch <owned-branch>
git symbolic-ref --quiet --short HEAD
git rev-parse HEAD
git status --porcelain=v1 --untracked-files=all
```

On Windows, use per-command `git -c core.longpaths=true ...` when the verified
worktree needs it. A successful branch attachment is insufficient if checkout left
a tracked file unchanged because its path was too long.

Read and compare the affected file against both recorded commits before recovery.
Only a file proven to be an incomplete checkout, not user work, may be restored
from the intended commit. Prefer preventing the problem with the per-command
setting. Never solve it by resetting the worktree or changing shared configuration.

## F. Lease-protected publication and tracking refresh

Resolve remotes from their URLs, including fork/base differences; do not assume
`origin` is always the desired destination.

```text
git ls-remote <push-remote> <full-layer-branch-ref> ...
```

Compare every remote tip to the recorded lease expectation immediately before push.
Verify how the installed stack command obtains its lease SHAs. If it uses tracking
refs, refresh only the needed refs to the already verified remote tips and protect
that snapshot from competing fetches. Do not mistake plain `--force-with-lease`
against mutable, unverified tracking state for a pinned expectation.

```text
gh stack push --remote <push-remote>
```

Use this only when its installed behavior provides the required protection. If it
cannot bind the reviewed expectations, stop for an authorized safe alternative
rather than claiming safety from the command name. For an authorized direct Git
push, explicit leases have this shape:

```text
git push --force-with-lease=<full-branch-ref>:<expected-remote-sha> <remote> <verified-new-sha>:<full-branch-ref>
```

Do not use unconditional force. Do not assume multi-ref pushes are atomic; request
atomicity only when the selected command/server support it. After any partial failure,
classify each remote ref as old, intended-new, or unexpected. Record already-published
layers and repair/retry only within the authorization and new verified lease snapshot.
Never blindly rerun a force push or automatically roll back successful public updates.

Verify every branch and PR head/base after publication. Then the owner may refresh
only its tracking ref:

```text
git fetch --quiet --no-tags --no-write-fetch-head --no-recurse-submodules --no-prune --no-prune-tags --no-auto-maintenance --no-write-commit-graph --refmap= <remote> +<full-owned-branch-ref>:<owned-remote-tracking-ref>
git rev-list --left-right --count HEAD...<owned-remote-tracking-ref>
```

Require zero ahead/behind and matching full local/tracking/published SHAs. Serialize
tracking updates for owners sharing a common directory; never refresh sibling refs
or trunk as a shortcut.
In owner-light mode, the executor performs this check/sync, records its full receipt,
and verifies live PR identity before release. An owner need not repeat it in a turn.

Checkout-sync uses this tracking refresh after verifying its fetched target still
matches the remote/PR head and base. If a requested remote advances during the
operation, freeze and reconcile that layer's target; do not call a stale tip latest.
It does not execute the publication commands above.

## G. Recovery boundaries

| Situation | Required response |
| --- | --- |
| Dirty, busy, or attached owner | Keep the gate closed; preserve its work and ask for a valid handoff |
| Branch already at intended SHA | Verify identity, generation, occupancy, and cleanliness; acknowledge idempotently |
| Unexpected local or remote SHA | Freeze affected work, inspect the new commits, and start a new snapshot/generation |
| Detached/unregistered executor | Before mutation, attach an authorized registered stack branch |
| Stack tool cannot resume | Preserve patch/state evidence, use supported continue/abort; do not edit private state or discard the resolution |
| Existing tool/rebase operation | Identify its owner and scope before resuming or aborting; do not start another operation |
| Integration correction | Fix in the correct layer, validate the exact snapshot, then replay without another trunk refresh |
| Partial push | Verify all remote refs and record partial publication; do not claim success or overwrite drift |
| Delayed/duplicate message | Compare operation ID, generation, and expected SHA; do not repeat a ref update, commit, or public reply |
| Interrupted owner-light action | Retain pending journal and frozen scopes; verify old executor/children stopped, reconcile exact revision/checkpoints, and use supported recovery |
| Owner receives new work while leased | Check its durable record first; coordinate a targeted correction/cancellation, never silently resume mutation |

Keep operation-scoped backups until recovery is no longer needed. Never delete broad
directories, prune unrelated branches, edit the main checkout, or delete another
session to clean up this operation.
