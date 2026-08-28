---
name: notification-cleanup
description: >
  Clean up stale GitHub notifications by marking closed/merged items as done.
  Use when asked to clean up notifications, dismiss stale notifications, or mark
  old notifications as read/done, including eligible comment-free approvals on
  someone else's PR.
---

# Notification Cleanup

Mark stale notifications as "Done" — i.e., closed/merged PRs and closed issues
where there has been no new comment since closure. Also dismiss eligible
comment-free approval notifications for someone else's open PRs.

## Steps

1. **Fetch all notifications** using `gh api /notifications --paginate` and parse the JSON.
   Extract: id, reason, subject type, subject URL, latest_comment_url, repository, updated_at.

2. **Filter to candidates**: only process notifications where `subject.type` is
   `PullRequest` or `Issue`.

3. **Check closed/merged status** for each candidate:
   - For PRs: fetch `repos/{owner}/{repo}/pulls/{number}` and check `state` and `merged_at`.
   - For Issues: fetch `repos/{owner}/{repo}/issues/{number}` and check `state` and `closed_at`.
   - Process closed items through the stale-closed checks in this step. Process
     open PR items through the approval-only notification check in step 6.

4. **Check for post-closure comments**:
   - If the notification's `subject.latest_comment_url` is non-null, fetch it and
     extract the `created_at` timestamp.
   - If `latest_comment_url` is null, treat last comment time as having no post-closure activity.
   - An item is **stale-closed** if it is closed/merged AND either there is no
     latest_comment_url OR the last comment's `created_at` is before the
     `closed_at`/`merged_at` time.
   - **CCR no-op exception**: If there are post-closure comments, fetch ALL
     comments after the closure time. Treat the item as stale-closed if the
     comments are exclusively a single comment from `@copilot code review` (for
     example, `@copilot` / `copilot-pull-request-reviewer[bot]` in the GitHub
     review app) whose body says it reviewed `N` files and no comments were
     generated, e.g. the body contains both "reviewed N files" and "no comments
     were generated". This is a code-review pass with no actionable feedback, so
     it should not block dismissal.
   - **Backport exception**: If the latest comment is after closure, fetch ALL
     comments posted after the `closed_at`/`merged_at` time using
     `repos/{owner}/{repo}/issues/{number}/comments?since={closed_at}`.
     The item is still considered **stale-closed** if every post-closure comment
     matches the successful-backport pattern:
       - A user comment whose body starts with `/backport to`, OR
       - A comment from `github-actions[bot]` (or `github-actions`) about starting
         or completing a backport (e.g., body contains "Started backporting" or
         "backport to").
     If ANY post-closure comment does NOT match these patterns, or if any comment
     indicates a **failed** backport (body matches the pattern
     "backporting to {branch} failed"), the item is NOT stale-closed and
     should be skipped.

5. **Revert PR exception**: For each PR notification that would otherwise be
   dismissed as stale-closed, check whether it reverts a PR authored by the
   current user:
   - Detect revert PRs by checking if the PR body contains
     `Reverts {owner}/{repo}#{number}` (GitHub's default revert body format).
   - If a reverted PR number is found, fetch the original PR via
     `repos/{owner}/{repo}/pulls/{original_number}` and check whether its
     `user.login` matches the current user (use `gh api /user` to resolve).
   - If the current user authored the original PR, check for participation
     on the **revert** PR:
     - Fetch comments via `repos/{owner}/{repo}/issues/{number}/comments`
       and check if any `user.login` matches the current user.
     - Fetch reviews via `repos/{owner}/{repo}/pulls/{number}/reviews`
       and check if any `user.login` matches the current user.
     - Check whether the revert PR's `merged_by.login` matches the current user.
   - If the current user authored the reverted PR AND has **not** participated
     in the revert PR (no comments, no reviews, did not merge it), **do not
     dismiss** the notification — the user needs to know their work was reverted.
   - If the user has participated, proceed normally (dismiss if stale-closed).

6. **Approval-only notification exception**: Also consider notifications for an
   open PR when the notification is solely about another user approving it:
   - Fetch the PR via `repos/{owner}/{repo}/pulls/{number}`. Apply this rule when
     `user.login` is different from the current user, so the PR belongs to someone
     else.
   - Fetch the PR's reviews via `repos/{owner}/{repo}/pulls/{number}/reviews`,
     inline review comments via `repos/{owner}/{repo}/pulls/{number}/comments`,
     and issue comments via `repos/{owner}/{repo}/issues/{number}/comments`.
     Identify the approval associated with the notification and require that it
     was submitted by someone other than the current user, has no review body,
     and has no inline review comments. Treat any issue comment, review body, or
     inline review comment as meaningful discussion.
   - Group notifications for the same PR and order them by `updated_at`. Find the
     user's most recent approval notification before the candidate. The candidate
     is eligible when either the immediately prior notification is the user's
     approval, or every notification since the user's approval through the
     candidate is an approval with no review body, issue comment, or inline review
     comment. The notification sequence must include a prior approval by the
     current user, and each notification in the interval must be an approval;
     comment, non-approval review, mention, assignment, or other activity makes
     the candidate ineligible.
   - This exception only dismisses the approval notification; it does not dismiss
     the PR's other notifications. Report it as "approval with no comments".

7. **Mark eligible notifications as Done** by calling:
   ```
   gh api -X DELETE /notifications/threads/{thread_id}
   ```
   where `thread_id` is the notification `id`.

8. **Report results**: Print a summary of how many notifications were marked done,
   listing each one with its title and reason it was dismissed (e.g., "merged",
   "closed", or "approval with no comments"). Also list any notifications that
   were skipped because they had post-closure comments or did not meet the
   approval-only exception, so the user is aware of them.

## Safety

- Dismiss closed/merged notifications with no post-closure comments, and dismiss
  open-PR approval notifications when they meet every condition in the
  approval-only exception.
- Never dismiss notifications where there is a comment newer than the closure time,
  as that may indicate follow-up discussion the user should see, except when the
  only post-closure comment is a single `@copilot code review` no-op summary that
  says it reviewed `N` files and generated no comments.
- Approval-only dismissal requires a PR owned by someone else, an approval with
  no body or review comments, and either a prior notification that is the user's
  approval or a sequence where every notification since the user's approval is
  an approval with no comments.
- Never dismiss notifications for revert PRs that revert the user's own PRs unless
  the user has already participated in the revert PR conversation.
- Print what will be dismissed and ask for user confirmation before making any
  DELETE calls, unless the user has explicitly asked to proceed without confirmation.
