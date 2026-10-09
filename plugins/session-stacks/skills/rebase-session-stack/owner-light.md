# Owner-light coordination

Use this opt-in coordination policy to keep mechanical Git work out of long-lived
layer conversations. It changes who performs handback, not what gets verified.
The owner-driven workflow remains the fallback.

## Eligibility and limits

Require the same execution host/runtime, directly accessible local filesystems,
Python 3.9+, and one designated executor. Worktrees may share a Git common directory
or belong to separate clones of the same logical repository/stack. Treat Windows
and WSL as different execution environments. Do not use distributed/network-filesystem
leases, cross-host executors, or guessed mounted paths.

Every participating owner must acknowledge the exact executor, worktree, branch,
actions, prepared SHA, completion policy, and durable lease token. Owners must
check the durable record before future mutation, including user-requested work,
queued turns, automation, restart, and compaction. If that cooperative rule or
record accessibility cannot be maintained, use the owner-driven fallback.

This is cooperative exclusion, not a permission system or Git interceptor. Actor
IDs and approval flags are attestations, not authentication. External editors,
raw Git, and unrelated tools do not honor these locks. Finish owned processes;
recheck actual refs, cleanliness, operation state, and occupancy. No timeout grants
authority, and this skill does not disable automation or discard user work.

## One preparation pair and one release notice

The coordinator sends one small preparation request. The owner completes requested
feedback, validates its source changes, detaches, acquires its scope, and returns
the lease token, prepared SHA, and receipt path. The executor then handles transfers,
replay, integration, checkout, publication if separately authorized, and tracking.
Owners receive nothing during those phases unless they must make a source correction.

Executor receipts replace the repeated owner attachment/tracking acknowledgments.
The coordinator still checks the complete evidence and all stack-level gates.
After verified completion, record release first and send one compact notice;
no acknowledgment-only owner turn is required. On its next substantive turn the
owner validates the matching terminal record with `resume` before editing.
Send owners only [their short checklist](owner-checklist.md), the scoped request,
and helper/record paths, not this executor reference or sibling/integration history.

## Durable request and storage

Prepare one JSON request per owner in accessible session artifacts, not product
source. Generate one fresh `uuid.uuid4().hex` lease token for the operation and use
it across its clone groups. Tokens identify operations; they are not credentials.
The owner inspects and acknowledges the request, not merely its path.

```json
{
  "operation": "stack-refresh-example",
  "leaseId": "<32-lowercase-hex-token>",
  "executor": "<exact-executor-session-id>",
  "owner": "<exact-owner-session-id>",
  "branch": "refs/heads/<owned-branch>",
  "preparedHead": "<full-oid>",
  "completion": "local-only",
  "actions": ["attach", "replay"],
  "source": "<accessible-source-worktree-or-named-remote>",
  "sourceRef": "refs/heads/<source-branch>"
}
```

`completion` is `local-only`, `published`, or `checkout-sync`. Published/checkout-sync
requests also need `sync`, `remote`, `repository` (`owner/repo`), numeric `pr`, and
`prBase`. The helper pins named remote URLs and derives only the owned tracking ref.
Add `publish` and `publicationAuthorized: true` only when the user authorized pushing.
Rebase authorization does not imply publication. Scope expansion requires a new
owner acknowledgment, not an executor-edited request.

`scripts/owner-light.py` stores `copilot-owner-light/lease.json` in the canonical Git
common directory, outside source and discoverable by every local worktree owner.
It holds a nonblocking OS writer lock for the entire action, atomically replaces
the JSON record, and retains immutable receipts, logs, prior-operation history,
and interrupted-action recovery evidence beside it. Separate clones have separate
locks/records; acquire every affected scope and retain the global coordinator
ledger/barrier before replay. No scope can resume while another scope in its clone
is still active.

Use the exact common-directory record, not a copied preview, as authority.
Keep canonical worktree paths and unique branches. A successful acquisition in
one clone does not authorize another clone or satisfy another owner's handoff.

## Commands

The commands are identical on Windows and Unix; use `python` or `python3` and native
filesystem paths. No third-party Python packages are needed.

```text
python <skill>/scripts/owner-light.py inspect --worktree <owner-worktree>
python <skill>/scripts/owner-light.py acquire --worktree <owner-worktree>
  --request <request-json> --owner <owner-id> --generation <g>
  --mutation-authorized --quiesced
```

`inspect` locates existing records; it does not acquire ownership. `acquire` checks
exact clean detached HEAD/ref, unoccupied branch, Git operation state, scope, and
host/runtime identity. Quiescence also attests finished owned processes and checked
stack-tool state, which the helper cannot discover.

The executor supplies a handback plan with full `expectedHead`, `expectedOld`,
`target`, and `parent` OIDs. Expected values must match the durable checkpoint.

```text
python <skill>/scripts/owner-light.py attach --worktree <owner-worktree>
  --lease-id <token> --actor <executor-id> --generation <g> --plan <plan-json>
python <skill>/scripts/owner-light.py sync --worktree <owner-worktree>
  --lease-id <token> --actor <executor-id> --generation <g>
python <skill>/scripts/owner-light.py complete --worktree <owner-worktree>
  --lease-id <token> --actor <executor-id> --generation <g> --quiesced
  --global-gates-verified --evidence <coordinator-evidence-reference>
```

`attach` preserves refs, narrowly transfers exact objects, proves parent ancestry,
uses CAS, and verifies complete attachment. An already-shared target skips transfer.
`sync` additionally needs authenticated `gh` for live PR readback; it verifies remote
SHA and PR head/base/open state before and after the narrow tracking fetch, checks
0/0 divergence, and preserves FETCH_HEAD, sibling refs, tags, and maintenance state.
`complete` verifies those applicable postconditions again and durably releases the
scope. Local-only completion is explicitly unpushed. A receipt path is not evidence
until the coordinator reads its actual result.
Before calling `complete` for any clone, verify all final handback, integration,
publication and tracking gates across the operation. Clone records cannot implement
an atomic cross-clone barrier; that remains the coordinator ledger's responsibility.
Completion requires the explicit gate attestation/evidence and retains it in the
receipt. Never reuse a terminal operation's token for a later operation.

After the global completion barrier, send the release notice with token, generation,
final SHA, completion policy, and receipt. At the next substantive owner turn:

```text
python <skill>/scripts/owner-light.py resume --worktree <owner-worktree>
  --lease-id <matching-token> --owner <owner-id> --generation <g> --head <final-oid>
```

This rejects active/pending leases, stale release notices, newer operations, dirty
checkouts, and changed refs. It records resume locally; no coordinator reply is
needed. Check `inspect` before each new mutation until this resume succeeds.

## Integration, topology, and corrections

Use the existing Git protocol and installed stack-tool semantics. For executor
commands in a participating clone, hold its lease lock and journal the action:

```text
python <skill>/scripts/owner-light.py run --worktree <executor-worktree>
  --lease-id <token> --actor <executor-id> --generation <g>
  --command-action replay -- <reviewed-executable> <arguments>
```

Use `publish` instead of `replay` only if every affected scope authorizes it and has
a final attachment receipt. The command wrapper runs an argument vector without
shell interpolation and writes a log, but does not infer what refs the external
tool can touch. Verify its bounded write set, all owner preparation barriers,
historical ranges, pinned trunk, publication leases, and stack-level semantics
before calling it. An integration-only separate clone may retain the standard
executor workflow; do not grant it authority over owners' uncommitted files.

The executor worktree must have its own acknowledged scope if it shares the owner
clone. A coordinator owning the top layer can acquire its own scope locally and
use `run` to take its registered branch. The executor's `verify-attached`
command accepts the `target`/`parent` plan and records an already-clean final
checkout without self-messaging or a redundant detach/attach cycle. A distinct
owner's branch must be vacated before its handback.
It also verifies an attachment preserved by interrupted-action recovery; the actual
checkout must equal its reviewed durable checkpoint. `verify-executor` is an alias.

Successful replay commands checkpoint actual clean HEAD/ref state but do not prove
validation, ancestry, patch preservation, or publication. Failed commands or a
crash leave `pending` set; subsequent mutations and release are refused.

To advance a corrective snapshot, call `advance` with a larger generation in each
participating clone. It rechecks unchanged checkpoints, invalidates tracking proof,
and updates the clone's generation without owner messages. Global generation and
unchanged-layer reuse still require the coordinator ledger. Reject old receipts.

If an owner must make a source correction, first have the executor attach its
verified candidate and call `correction` with owner ID and precise evidence.
That scope alone is transferred back to its owner; executor operations remain
blocked while it is in `correction`. After the owned correction is validated,
committed, and detached, the owner calls `reprepare` with its full new `--head`,
larger generation, and fresh preparation attestations. Other scopes stay frozen
and are revalidated locally. This targeted exchange is necessary, not chatter.

## Interrupted operations

Never clear a lease because its process lock became available or a timer expired.
The OS lock excludes live participating writers; the durable pending journal
survives process death. Inspect recorded PIDs, command/log, current refs, worktrees,
remote publication, and Git/tool state. Confirm the old executor and its children
have actually stopped before takeover or recovery. Do not kill by process name.

`recover` accepts the same actor/token, exact `--expected-revision`, reviewed
`--plan` containing full `checkpoints` for every clone participant, stopped-executor
attestation, and precise evidence. It restores a usable checkpoint only when all
worktrees are clean and no Git operation remains. It preserves the interrupted
journal and clears only its pending state; it does not release owners or infer
whether a push succeeded. Retry only after normal verification.

An unresolved rebase/conflict cannot pass this clean recovery gate. Use supported
Git/stack-tool recovery under an explicitly reconciled ownership handoff; never
reset files, edit private tool state, silently switch actors, or broaden a lease.
If owner-light recovery is inapplicable, keep affected owners frozen and use the
owner-driven recovery protocol after resolving authority. Changing actor or scope
requires a new acknowledged operation, not editing the JSON by hand.

## Verification and fallback

```text
python <skill>/tests/owner_light_tests.py --scratch-root <existing-session-artifacts>
```

Fixtures use disposable repositories. They exercise actual Git and local OS locks;
PR API responses are mocked, not live publication. Keep native-platform validation
limitations explicit. Existing ps1/sh helpers retain their owner-driven behavior
and refuse Attach under an active owner-light clone record. They do not intercept
raw Git; all participants must honor the cooperative freeze.
