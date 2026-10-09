# Compact operation state

Keep one authoritative coordinator ledger in the session database or an operation-
scoped JSON artifact. Owners need self-contained messages, not access to that
database. In owner-light mode, the separate durable clone lease is the authority
for freezing/resuming local owners, not a copied coordinator artifact. Do not
create planning files in the product repository.

## Schema

Store full OIDs. Distinct values must have distinct fields; equality may be reported
once with explicit flags. Use exact app-surfaced owner IDs, never guessed IDs.

```text
operation:
  id, generation, mode
  coordination_policy: owner-driven | owner-light
  coordinator_id, executor_id, repository
  executor_worktree, executor_common_directory, registered_executor_branch
  executor_is_layer_owner, execution_and_publication_lease
  authorizations: feedback, local_rewrite, checkout, publication, reply_resolution
  stack_identity, ordered_membership_including_merged
  remotes: fetch_url, push_url, names
  parent_or_trunk: policy, fetched_ref, pinned_sha
  installed_tool: version_or_identity, verified_semantics
  writer_leases: common_directory, actor, phase
  durable_clone_leases: path, token, environment, revision, scopes, pending_action

layer:
  pr, branch_ref, owner_id, worktree, canonical_common_directory
  live_pr: head, base, state
  starting_owner_head, coordinator_old_head, historical_parent, remote_lease_head
  prepared_head, final_head, expected_detached_head, expected_owner_ref
  phase, generation, backup_refs, transfer_refs
  executor_receipts, completion_policy, owner_resume_state
  feedback_dispositions, pending_reply_ids_and_text
  acknowledgments, validation_ids

validation:
  id, generation, commit_or_tree, relevant_blob_ids
  build_inputs: runtime, architecture, configuration, flags, toolchain
  commands, logs, passed, failed, skipped, limitations
  status: passed | failed | waived | not_run | invalidated
  reuse_proof_or_waiver_scope
```

Use the fields applicable to the mode. Checkout-sync needs target identities and
checkout evidence, not invented historical replay boundaries or fresh test results.
Keep unchanged metadata in the ledger rather than repeating it in every reply.

## Gates and generations

```text
replay:
  DISCOVERED -> [FEEDBACK_DONE] -> PREPARED_DETACHED -> IMPORTED
  -> REBASED -> VALIDATED -> ATTACHED_FROZEN
  -> [PUBLISHED -> TRACKING_SYNCED] -> RELEASED

checkout-sync:
  DISCOVERED -> PREPARED_DETACHED -> IMPORTED
  -> ATTACHED_VERIFIED -> TRACKING_SYNCED -> RELEASED
```

An already clean, correctly attached, fully synced checkout may take a verified
no-op path to RELEASED. Skipped phases are explicit, not fictional acknowledgments.
Only a matched operation/generation/expected-SHA report advances a gate.
Owner-light mechanical gates accept executor receipts with the same identities
and full postconditions; read the actual receipt. They do not require a second
owner LLM turn to repeat the checks.

New intended source/ref snapshots require a new generation. A correction affects
its layer and descendants the tool may touch, not unrelated layers. Carry forward
unchanged-layer evidence only after checking its SHA, frozen lease, cleanliness,
occupancy, and operation state; record that verification for the new generation.
Retain old evidence for recovery, but never let a stale report advance the new gate.

Keep non-executing owners detached through validation. An owner executor may keep
its registered branch attached under its frozen execution lease; record its final
owner acknowledgment locally once validation completes. ATTACHED_FROZEN permits
observation only. Publication requires all matching final acknowledgments. A
local-only operation may attach and release in one message after its verified endpoint.

Owner-light owners freeze after one acquired-scope acknowledgment. Do not broadcast
generation updates to unchanged owners: advance/revalidate clone records locally
and retain the global generation barrier here. Necessary source corrections return
only that scope to its owner. Release records precede notices; `resume` validates
the matching terminal record before further owner work, including queued requests
and automation. Timer expiry and an available process lock do not imply release.

## Evidence reuse and output budgets

Validation reuse requires identical relevant source and build inputs, not merely
the same commit subject or an equal range-diff. Record exact-blob/tree evidence for
centrally validated owner patches. A changed trunk, flag, runtime, or generated
input invalidates affected results unless equivalence is proved.

Record waivers prospectively with their scope. If an earlier generation ran tests
but later tests were waived, report both facts; never summarize "no tests run."
Do not sum overlapping selections as unique tests or present builds as execution.

Batch independent reads. For shell commands, use explicit exit checks and
operation-scoped logs; return status plus bounded relevant excerpts. Inspect actual
result counts. Persist complete evidence, but do not repeatedly stream logs or
entire inventories into the conversation. Use targeted owner reads to resolve
actual ambiguity or human gates; read the exact question/plan before answering.

After compaction, reload this ledger, current authorization, and applicable
instructions. Refresh live safety checks at mutation boundaries. Reuse installed
tool semantics only if its version/identity is unchanged.

Duplicate phase reports add no new gate transition; record once without repeating
instructions or public actions. Unrelated/repeated idle notifications require no
status response. This suppresses chatter, not platform-generated wake-ups.
