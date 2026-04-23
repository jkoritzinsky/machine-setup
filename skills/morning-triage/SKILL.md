---
name: morning-triage
description: >
  Triage GitHub notifications by priority. Use when asked to triage notifications,
  check what needs attention today, do morning triage, or review GitHub inbox.
---

# Morning Triage

Fetch and triage the user's GitHub notifications, categorizing them by priority.

## Steps

1. **Fetch notifications** using `gh api /notifications --paginate` and parse the JSON.
   Extract: id, reason, title, type, subject URL, repository, and updated_at.

2. **Fetch area labels** for each notification that points to a dotnet/runtime issue or PR.
   Use `gh api repos/{repo}/issues/{number}/labels` and extract labels matching `area-*`.

3. **Check closed/merged status** for each PR and issue notification.
   - For PRs: `gh api repos/{repo}/pulls/{number}` — check `state`, `merged`, `merged_at`.
   - For Issues: `gh api repos/{repo}/issues/{number}` — check `state`, `closed_at`.
   - Also check the notification's `subject.latest_comment_url`. If it is non-null, fetch it
     and extract its `created_at` timestamp. If `latest_comment_url` is null, treat the last
     comment time as epoch zero (i.e., no comment after close).
   - Mark the item as **stale-closed** if it is closed/merged AND the last comment time
     is before the closed_at/merged_at time (meaning no new discussion since closure).

4. **Check for prior @-mention and approval status** on `comment` and `team_mention`
   notifications that point to PRs. This determines whether the item should be promoted.
   - Fetch PR comments via `gh api repos/{repo}/issues/{number}/comments` and check
     whether any comment body contains `@{your_username}` (e.g., `@jkoritzinsky`).
   - Fetch PR reviews via `gh api repos/{repo}/pulls/{number}/reviews` and check
     whether you have submitted a review with `state` = `APPROVED`.
   - Mark the item as **prior-mention-pending** if you were @-mentioned in any comment
     AND you have NOT approved the PR.

5. **Categorize by priority** using the rules below, then present a triage summary
   organized from highest to lowest priority.

## Priority Rules

### Engagement priority (higher = more important)
1. **assigned** — you are assigned to this item
2. **mention** — you were directly @-mentioned
3. **review_requested** — your review was requested
4. **comment** — you previously participated and there is new activity
5. **team_mention** — your team was mentioned (lowest direct engagement)

### Area priority (higher = more important)
1. **Interop, AppModel, or ReadyToRun** — labels containing `Interop`, `AppModel`, or `ReadyToRun` (case-insensitive)
2. **Infrastructure** — labels containing `Infrastructure` (case-insensitive)
3. **Other areas** — labels that do NOT contain Interop, AppModel, ReadyToRun, or Infrastructure
   are the **lowest priority** regardless of engagement level

### Combined priority tiers

Present results in these tiers, each as a markdown table:

- 🔴 **HIGH** — assigned or mentioned (regardless of area);
  OR review_requested AND area is Interop/AppModel/ReadyToRun
- 🟠 **MEDIUM-HIGH** — review_requested (regardless of area);
  OR comment AND area is Interop/AppModel/ReadyToRun
- 🟡 **MEDIUM** — team_mention or comment AND area is Interop/AppModel/ReadyToRun/Infrastructure;
  OR comment or team_mention that is **prior-mention-pending** (you were @-mentioned
  in a prior comment and have not approved the PR), regardless of area
- 🔵 **MEDIUM-LOW** — team_mention AND area is other or no labels (e.g., VMR PRs)
- ⚪ **LOWEST** — comment or other engagement where area does NOT include
  Interop, AppModel, ReadyToRun, or Infrastructure

### Additional rules

- For repositories other than dotnet/runtime (e.g., dotnet/dotnet, dotnet/sdk),
  treat notifications as infrastructure-related unless labels say otherwise.
- Automated merge PRs (`[automated] Merge branch ...`) are always MEDIUM-LOW.
- **Stale-closed demotion:** Any closed/merged PR or closed issue where the last comment
  time is before the closed_at/merged_at time is demoted to ⚪ LOWEST regardless of
  other priority rules. These items were closed without subsequent discussion and
  likely need no action. Annotate them with "(closed)" or "(merged)" in the output.
- Include a **TL;DR** at the end summarizing the top 2–3 items to focus on first.

## Output Format

For each tier, show a table with columns: Issue/PR number (as a link), Title, Reason, Area label.
Omit empty tiers. End with a short TL;DR.

## Today's Meetings

After presenting the notification triage, use the **workiq** skill to fetch today's
calendar meetings. Present a summary of meetings the user regularly attends that were
organized by someone in **Steve Carroll's organization**.

- Show each meeting's time, title, and organizer.
- Omit meetings organized by people outside Steve Carroll's org.
- If a meeting has an agenda or recent related documents/threads, briefly note them.
- Keep it concise — just enough context to prepare for the day.

## Recent Emails

Also use the **workiq** skill to fetch recent emails from people in
**Steve Carroll's organization**. Summarize any unread or notable emails
from today or the previous business day.

- Show sender, subject, and a one-line summary of the content.
- Omit automated/no-reply emails and distribution list noise.
- Highlight anything that looks action-required or time-sensitive.
