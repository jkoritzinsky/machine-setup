---
name: notification-cleanup
description: >
  Clean up stale GitHub notifications by marking closed/merged items as done.
  Use when asked to clean up notifications, dismiss stale notifications, or mark
  old notifications as read/done.
---

# Notification Cleanup

Mark stale notifications as "Done" — i.e., closed/merged PRs and closed issues
where there has been no new comment since closure.

## Steps

1. **Fetch all notifications** using `gh api /notifications --paginate` and parse the JSON.
   Extract: id, reason, subject type, subject URL, latest_comment_url, repository, updated_at.

2. **Filter to candidates**: only process notifications where `subject.type` is
   `PullRequest` or `Issue`.

3. **Check closed/merged status** for each candidate:
   - For PRs: fetch `repos/{owner}/{repo}/pulls/{number}` and check `state` and `merged_at`.
   - For Issues: fetch `repos/{owner}/{repo}/issues/{number}` and check `state` and `closed_at`.
   - Skip any item that is still open.

4. **Check for post-closure comments**:
   - If the notification's `subject.latest_comment_url` is non-null, fetch it and
     extract the `created_at` timestamp.
   - If `latest_comment_url` is null, treat last comment time as having no post-closure activity.
   - An item is **stale-closed** if it is closed/merged AND either there is no
     latest_comment_url OR the last comment's `created_at` is before the
     `closed_at`/`merged_at` time.
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

5. **Mark stale-closed notifications as Done** by calling:
   ```
   gh api -X DELETE /notifications/threads/{thread_id}
   ```
   where `thread_id` is the notification `id`.

6. **Report results**: Print a summary of how many notifications were marked done,
   listing each one with its title and reason it was dismissed (e.g., "merged",
   "closed"). Also list any notifications that were skipped because they had
   post-closure comments, so the user is aware of them.

## Safety

- Only dismiss notifications for items that are closed/merged WITH no post-closure comments.
- Never dismiss notifications for open items.
- Never dismiss notifications where there is a comment newer than the closure time,
  as that may indicate follow-up discussion the user should see.
- Print what will be dismissed and ask for user confirmation before making any
  DELETE calls, unless the user has explicitly asked to proceed without confirmation.
