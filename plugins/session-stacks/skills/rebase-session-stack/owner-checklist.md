# Layer-owner checklist

Read this page for owner-light preparation; the executor owns the full stack
protocol. Use owner-driven coordination if the same-host/local-filesystem lease
requirements or cooperative freeze cannot be honored.

1. Finish only requested feedback and owned processes. Validate/review source
   changes using repository guidance. Preserve unrelated work; never force a
   dirty checkout clean. Verify readiness and detach Git HEAD, not the app session.
2. Read the exact scoped request: executor, owner/worktree/branch, prepared SHA,
   actions, completion policy, and fresh lease token. No implied push permission.
   Acquire it with `owner-light.py acquire --worktree <path> --request <json>
   --owner <id> --generation <g> --mutation-authorized --quiesced`.
3. Return only the prepared SHA, token, generation, receipt path, and genuine
   feedback/blockers. Stay frozen. No starting/received replies or status polling.
4. Before any subsequent mutation, queued user work, automation, restart, or
   compaction recovery, use `owner-light.py inspect --worktree <path>`. An active,
   pending, newer, or inaccessible record is a blocker. Idle and elapsed time
   never release you; coordinate necessary work instead of silently editing.
5. A release notice needs no acknowledgment-only reply. On your next substantive
   turn run `owner-light.py resume --worktree <path> --lease-id <token> --owner <id>
   --generation <g> --head <final-oid>`. Resume only if it succeeds against the
   matching terminal record and clean checkout.

For an explicitly assigned source correction, the executor must first record
your `correction` handoff. Edit only your layer, validate, commit, detach, then
`reprepare` with the new full head, larger generation, and fresh preparation
attestations. Other owners stay frozen. Keep full logs/receipts in artifacts, not
your conversation.
