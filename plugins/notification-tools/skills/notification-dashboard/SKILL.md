---
name: notification-dashboard
description: >
  Open the interactive GitHub notification and pull request review dashboard.
  Use when the user wants to browse, prioritize, or manage GitHub notifications
  visually, or review requested PRs in a dashboard.
---

# Notification Dashboard

Use the `github-notification-triage` canvas for an interactive view of GitHub
notifications and pull request review status.

## Workflow

1. Open the `github-notification-triage` canvas.
2. Use its filters to switch between **My PRs**, **Others' Open PRs**, **Others'
   Draft PRs**, and **Stacked PRs (not bottom)**. Other contributors' open
   non-draft and draft PRs are separate views. The stacked view includes both
   your PRs and other contributors' PRs. Review-work, assigned-or-mentioned,
   and high-priority filters are also available.
3. Use **Mark done** only for notifications the user explicitly chooses. The
   canvas does not run stale-notification cleanup automatically.
   Items with the `community-contribution` label show that label in their
   notification details.
4. Use **Run notification cleanup** to ask the active agent to start the
   `notification-cleanup` skill. The skill still applies its stale-item,
   post-closure activity, backport, and confirmation safeguards.
5. Use the **morning-triage** skill for the full written triage workflow,
   including stack analysis, meetings, and recent email context.
6. Use the **notification-cleanup** skill directly when the user wants stale closed or
   merged notifications dismissed according to its safety rules.
