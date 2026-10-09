# Handoff templates

Read only the current phase. Send immediate messages for work intended now; retain
exact owner IDs. Populate the envelope once per recipient, with enough concrete
context to act without access to the coordinator's ledger:

```text
op=<id> gen=<g> phase=<phase>
owner=<session-id> repo=<repo> PR=<number> branch=<full-ref>
worktree=<path> commonDir=<absolute-path> coordinator=<id>
executor=<session-id/worktree/registered branch> executorIsOwner=<true/false>
authority=<precise authorized actions> exclusions=<other layers/prototypes>
protocol=<accessible skill path/current section; concrete commands if unavailable>
```

Later messages need changed fields and phase instructions, not repeated histories.
Full OIDs are required. Never omit expected-old or target identities to save tokens.

## Owner-light preparation and release

Use only when owner-light eligibility and durable lease support are verified.
Send the normal envelope once with the exact request path and its concrete scope:

```text
coordination=owner-light request=<json-path> token=<lease-id>
executor=<id> actions=<exact approved actions> completion=<policy>
expectedPreparedHead=<full-oid> ownerChecklist=<accessible owner-checklist.md>
helper=<accessible owner-light.py> leaseRecord=<verified common-directory path>
Finish requested feedback and owned processes; verify clean detached readiness.
Review the request and acquire your scope with owner-light.py. Report prepared SHA,
token, generation and receipt only (plus real feedback/correction blockers).
Remain frozen. Before any future mutation/queued request/automation/restart, inspect
the durable lease; do not infer release from idle or elapsed time.
No starting/received acknowledgments, status polling, independent Git changes,
or full protocol/stack histories in replies.
```

After the executor verifies completion and the global gate:

```text
op=<id> token=<lease-id> gen=<g> phase=RELEASED
branch=<full-ref> head=<full-oid> completion=<local-only/published/checkout-sync>
receipt=<verified durable receipt> lease=<record-path>
No acknowledgment-only reply needed. On your next substantive turn, validate this
matching terminal record with owner-light.py resume before editing. If a newer
lease, active sibling scope, interrupted action or drift exists, remain frozen.
```

Keep full receipts and integration logs outside the owner conversation. Sections
D/E are executor operations in owner-light mode, not additional owner messages.
Use section C only for a necessary owned correction after the executor records its
explicit correction handoff. The owner validates/commits/detaches and reprepares.
Owner-driven mode retains the following phase exchanges.

## A. Prepare

```text
expectedStartingHead=<sha> feedback=<requested/not requested>
If feedback requested: refresh every page of inline threads, reviews, human general
comments, and relevant local feedback. Record implemented/already addressed/not
applicable/blocked with evidence. Follow repository skills; validate and review
owned edits, commit incrementally with required credit; no empty commits.
Build owner=<id>; coordinate costly validation rather than duplicate it.
Otherwise preserve existing commits; do readiness checks only.
Finish owned processes, verify full cleanliness and Git/tool state, detach Git HEAD
with git switch --detach HEAD, and remain frozen. This is not app detachment.
Return PREPARED_DETACHED evidence and pending reply IDs/text; no push, independent
rebase, sibling/trunk update, CI rerun, metadata change, or premature delivery reply.
```

## B. Compact acknowledgment

```text
op=<id> gen=<g> phase=<PREPARED_DETACHED/ATTACHED_FROZEN/RELEASED>
owner=<id> branch=<full-ref> head=<full-sha> branchEqualsHead=<true/false>
symbolicHead=<null/full-ref> worktree=<path> commonDir=<path>
clean=<true/false> gitOperations=<list> branchOccupants=<paths>
ownedProcessesFinished=<evidence> stackToolIdle=<evidence>
backupRefs=<refs> transferRefs=<refs> feedback=<dispositions or not requested>
validation=<snapshot/commands/counts/logs/limitations or precise not-run scope>
pendingReplies=<exact thread/comment IDs and text, or none>
```

At release add the tracking/published SHA or explicit local-only status. Equality
flags replace duplicate OID strings, not the checks. Failures return a precise
blocker instead of success-shaped defaults.
An executor owning this layer records the acknowledgment locally; do not self-message.
Its already attached, exact clean final checkout needs verification, not a second
detach/Attach-helper cycle. Execution attachment itself is not a final handback.

## C. Integration correction

```text
phase=INTEGRATION_FIX expectedHead=<sha> failingSnapshot=<sha/tree>
evidence=<localized failure, command/log and relevant upstream change>
change=<small necessary owned correction> preserve=<unaffected behavior>
attachmentOrTransferPermission=<exact refs/SHAs, if needed>
Review and send exact patch plus blob/tree identity. Validation owner=<id>.
Hold commit until exact-snapshot validation arrives, unless assigned validation.
After matching evidence, commit that patch with credit and detach again.
No other layer changes, push, independent rebase, trunk refresh, or public reply.
```

Send matching validation evidence and commit/detach authorization together. Do not
ask the user to reauthorize a necessary correction already within scope.

## D. Attach and optional local release

```text
phase=FINAL_CHECKOUT expectedDetachedHead=<sha> expectedOwnerRef=<sha>
target=<sha> parent=<ref/sha> cloneRelationship=<shared/separate>
source=<authorized source/ref if transfer needed> generation=<g>
writeWindow=<exclusive common-directory window> validation=<evidence>
endState=<ATTACHED_FROZEN / RELEASED local-only / RELEASED checkout-sync>
Verify clean/detached/quiesced state and unoccupied branch. Use the guarded Attach
helper or protocol C/E: create-only backup, narrow fresh transfer, exact SHA, CAS.
Choose the ps1 helper on PowerShell or the sh helper on Bash.
Executor occupancy release=<verified handoff if distinct worktrees share this clone>.
If already at target, verify without fetch/CAS. An unexpected SHA is a blocker.
Attach with per-command longpaths when needed; verify full clean HEAD/ref identity.
If publishing later: remain ATTACHED_FROZEN; no edit/build/fetch/public reply.
If local-only: attach and report RELEASED, explicitly unpushed.
If checkout-sync: verify remote/PR target, narrowly sync own tracking, then RELEASED.
Never pull, change siblings/trunk/metadata, or claim unverified delivery.
```

## E. Publication confirmed

```text
phase=SYNC_AND_RELEASE target=<sha> PR=<number> base=<parent-ref>
publicationEvidence=<verified remote/PR heads and bases>
writeWindow=<exclusive common-directory window> remote/tracking=<exact values>
Use protocol F's narrow tracking refresh; verify clean attached local/tracking/
published equality and 0/0 divergence. No pull, rebase, sibling/trunk change or CI.
Approved pending replies=<IDs/text/scope>; check duplicates, use correct endpoints
and disclosure policy. Follow explicit reply/resolve instructions.
Report TRACKING_SYNCED/RELEASED evidence and reply IDs, or blocker.
No further coordinator mutation under this generation.
```

## Waiting and duplicate delivery

Wait for explicit reports; do not poll refs or send status reminders. Idle is not
success. Read live status only for actual ambiguity or human gates.
Duplicate reports need no acknowledgment chatter. For duplicate action requests,
verify matched state and return one compact no-op result. Stale generation/SHA:
return current state for reconciliation, never repeat mutation or public replies.
