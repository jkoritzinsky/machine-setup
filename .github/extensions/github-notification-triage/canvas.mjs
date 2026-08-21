import { execFile } from "node:child_process";
import { createServer } from "node:http";
import { URL } from "node:url";
import { CanvasError } from "@github/copilot-sdk/extension";

const servers = new Map();
const priorityOrder = ["HIGH", "MEDIUM-HIGH", "MEDIUM", "MEDIUM-LOW", "LOWEST"];
const priorityRank = new Map(priorityOrder.map((value, index) => [value, index]));

const emptyState = () => ({
    refreshedAt: null,
    username: null,
    loading: false,
    error: null,
    counts: Object.fromEntries(priorityOrder.map((value) => [value, 0])),
    categoryCounts: {
        "my-prs": 0,
        "other-open-prs": 0,
        "other-draft-prs": 0,
        "stacked-prs": 0,
    },
    notifications: [],
});

function errorMessage(error) {
    return error instanceof Error ? error.message : String(error);
}

function runGhApi(args) {
    return new Promise((resolve, reject) => {
        execFile(
            "gh",
            ["api", ...args],
            { windowsHide: true, maxBuffer: 32 * 1024 * 1024 },
            (error, stdout, stderr) => {
                if (error) {
                    const details = String(stderr || "").trim() || error.message;
                    reject(new Error(`gh api ${args.join(" ")} failed: ${details}`));
                    return;
                }

                const output = String(stdout || "").trim();
                if (!output) {
                    resolve(null);
                    return;
                }

                try {
                    resolve(JSON.parse(output));
                } catch (parseError) {
                    reject(new Error(`gh api ${args.join(" ")} returned invalid JSON: ${errorMessage(parseError)}`));
                }
            },
        );
    });
}

function flattenPages(value) {
    if (!Array.isArray(value)) {
        return [];
    }

    return value.length > 0 && value.every(Array.isArray) ? value.flat() : value;
}

function parseSubjectUrl(subjectUrl) {
    const match = String(subjectUrl || "").match(/\/repos\/([^/]+\/[^/]+)\/(issues|pulls)\/(\d+)(?:$|\/)/);
    if (!match) {
        return null;
    }

    return {
        repository: match[1],
        kind: match[2] === "pulls" ? "PullRequest" : "Issue",
        number: Number(match[3]),
    };
}

function htmlUrl(repository, kind, number) {
    return `https://github.com/${repository}/${kind === "PullRequest" ? "pull" : "issues"}/${number}`;
}

function labelNames(item) {
    return Array.isArray(item?.labels)
        ? item.labels.map((label) => typeof label === "string" ? label : label?.name).filter(Boolean)
        : [];
}

function areaInfo(repository, labels) {
    const highArea = labels.filter((label) => /interop|appmodel|readytorun/i.test(label));
    const infrastructure = labels.filter((label) => /infrastructure/i.test(label));

    if (highArea.length > 0) {
        return { tier: "high", label: highArea.join(", ") };
    }
    if (infrastructure.length > 0 || repository !== "dotnet/runtime") {
        return {
            tier: "infrastructure",
            label: infrastructure.join(", ") || "Infrastructure",
        };
    }

    const areaLabels = labels.filter((label) => /^area-/i.test(label));
    return { tier: "other", label: areaLabels.join(", ") || "Other" };
}

function reviewStatus(reviews, username) {
    const ownReviews = reviews
        .filter((review) => review?.user?.login === username)
        .sort((left, right) => String(left.submitted_at || "").localeCompare(String(right.submitted_at || "")));
    const latest = ownReviews.at(-1);

    if (ownReviews.some((review) => review.state === "APPROVED")) {
        return "approved";
    }
    if (latest?.state === "CHANGES_REQUESTED") {
        return "changes requested";
    }
    if (latest?.state === "COMMENTED") {
        return "commented";
    }
    return "not reviewed";
}

function stackParent(body) {
    const match = String(body || "").match(/(?:depends on|stacked on|blocked by)\s+(?:[^\s#]+\/[^\s#]+)?#?(\d+)/i);
    return match ? Number(match[1]) : null;
}

function calculatePriority(notification, item, area, priorMentionPending) {
    const reason = notification.reason;
    let priority;

    if (item?.title && /^\[automated\]\s+merge branch/i.test(item.title)) {
        priority = "MEDIUM-LOW";
    } else if (reason === "assigned" || reason === "assign" || reason === "mention") {
        priority = "HIGH";
    } else if (reason === "review_requested" && area.tier === "high") {
        priority = "HIGH";
    } else if (reason === "review_requested") {
        priority = "MEDIUM-HIGH";
    } else if (reason === "comment" && area.tier === "high") {
        priority = "MEDIUM-HIGH";
    } else if (priorMentionPending) {
        priority = "MEDIUM";
    } else if ((reason === "team_mention" || reason === "comment") && (area.tier === "high" || area.tier === "infrastructure")) {
        priority = "MEDIUM";
    } else if (reason === "team_mention") {
        priority = "MEDIUM-LOW";
    } else {
        priority = "LOWEST";
    }

    const parent = stackParent(item?.body);
    if (parent !== null && priority !== "LOWEST") {
        priority = priorityOrder[Math.min(priorityRank.get(priority) + 1, priorityOrder.length - 1)];
    }

    return { priority, stackParent: parent };
}

function baseNotification(notification, subject) {
    const repository = notification.repository?.full_name || subject?.repository || "unknown/unknown";
    const kind = notification.subject?.type || subject?.kind || "Notification";
    const number = subject?.number || null;
    return {
        id: String(notification.id),
        title: notification.subject?.title || "Untitled notification",
        repository,
        kind,
        number,
        reason: notification.reason || "unknown",
        updatedAt: notification.updated_at || null,
        htmlUrl: number ? htmlUrl(repository, kind, number) : null,
        state: null,
        status: "unknown",
        labels: [],
        area: { tier: "other", label: "Other" },
        priority: "LOWEST",
        stackParent: null,
        priorMentionPending: false,
        reviewStatus: null,
        reviewRequested: false,
        requestedReviewers: [],
        approvedByUser: false,
        isMine: false,
        isDraft: false,
        isOtherOpen: false,
        isOtherDraft: false,
        isStacked: false,
        communityContribution: false,
        category: null,
        error: null,
    };
}

async function enrichNotification(notification, username) {
    const subject = parseSubjectUrl(notification.subject?.url);
    const result = baseNotification(notification, subject);
    if (!subject) {
        return result;
    }

    try {
        const item = await runGhApi([`repos/${subject.repository}/${subject.kind === "PullRequest" ? "pulls" : "issues"}/${subject.number}`]);
        const labels = labelNames(item);
        const area = areaInfo(subject.repository, labels);
        const commentsAndReviews = subject.kind === "PullRequest"
            ? await Promise.all([
                runGhApi([`repos/${subject.repository}/issues/${subject.number}/comments`, "--paginate", "--slurp"]),
                runGhApi([`repos/${subject.repository}/pulls/${subject.number}/reviews`, "--paginate", "--slurp"]),
            ])
            : [[], []];
        const comments = flattenPages(commentsAndReviews[0]);
        const reviews = flattenPages(commentsAndReviews[1]);
        const approvedByUser = reviews.some((review) => review?.user?.login === username && review.state === "APPROVED");
        const escapedUsername = String(username).replace(/[.*+?^${}()|[\]\\]/g, "\\$&");
        const priorMentionPending = subject.kind === "PullRequest"
            && comments.some((comment) => new RegExp(`@${escapedUsername}\\b`, "i").test(comment?.body || ""))
            && !approvedByUser;
        const priority = calculatePriority(notification, item, area, priorMentionPending);
        const isMine = subject.kind === "PullRequest" && item.user?.login === username;
        const isDraft = subject.kind === "PullRequest" && item.draft === true;
        const isOtherOpen = subject.kind === "PullRequest" && !isMine && item.state === "open" && !isDraft;
        const isOtherDraft = subject.kind === "PullRequest" && !isMine && item.state === "open" && isDraft;
        const isStacked = subject.kind === "PullRequest" && priority.stackParent !== null;
        const communityContribution = labels.some((label) => label.toLowerCase() === "community-contribution");

        return {
            ...result,
            title: item.title || result.title,
            repository: subject.repository,
            kind: subject.kind,
            number: subject.number,
            htmlUrl: item.html_url || result.htmlUrl,
            state: item.state || null,
            status: item.merged_at ? "merged" : item.state || "unknown",
            labels,
            area,
            priority: priority.priority,
            stackParent: priority.stackParent,
            isMine,
            isDraft,
            isOtherOpen,
            isOtherDraft,
            isStacked,
            communityContribution,
            category: isStacked
                ? "stacked-pr"
                : isMine
                    ? "my-pr"
                    : isOtherOpen
                        ? "other-open-pr"
                        : isOtherDraft
                            ? "other-draft-pr"
                            : null,
            priorMentionPending,
            reviewStatus: subject.kind === "PullRequest" ? reviewStatus(reviews, username) : null,
            reviewRequested: notification.reason === "review_requested",
            requestedReviewers: (item.requested_reviewers || []).map((reviewer) => reviewer.login || reviewer.name).filter(Boolean),
            approvedByUser,
            error: null,
        };
    } catch (error) {
        return {
            ...result,
            repository: subject.repository,
            kind: subject.kind,
            number: subject.number,
            htmlUrl: htmlUrl(subject.repository, subject.kind, subject.number),
            error: errorMessage(error),
        };
    }
}

function summarize(state) {
    return {
        refreshedAt: state.refreshedAt,
        username: state.username,
        counts: state.counts,
        categoryCounts: state.categoryCounts,
        notificationCount: state.notifications.length,
        error: state.error,
    };
}

async function refreshEntry(entry) {
    entry.state = { ...entry.state, loading: true, error: null };

    try {
        const [user, rawNotifications] = await Promise.all([
            runGhApi(["user"]),
            runGhApi(["notifications", "--paginate", "--slurp"]),
        ]);
        const username = user?.login;
        if (!username) {
            throw new Error("GitHub user response did not include a login.");
        }

        const notifications = await Promise.all(
            flattenPages(rawNotifications).map((notification) => enrichNotification(notification, username)),
        );
        notifications.sort((left, right) => {
            const priorityDifference = priorityRank.get(left.priority) - priorityRank.get(right.priority);
            return priorityDifference || String(right.updatedAt || "").localeCompare(String(left.updatedAt || ""));
        });

        const counts = Object.fromEntries(priorityOrder.map((value) => [value, 0]));
        const categoryCounts = {
            "my-prs": 0,
            "other-open-prs": 0,
            "other-draft-prs": 0,
            "stacked-prs": 0,
        };
        for (const notification of notifications) {
            counts[notification.priority] += 1;
            if (notification.isMine) {
                categoryCounts["my-prs"] += 1;
            }
            if (notification.isOtherOpen) {
                categoryCounts["other-open-prs"] += 1;
            }
            if (notification.isOtherDraft) {
                categoryCounts["other-draft-prs"] += 1;
            }
            if (notification.isStacked) {
                categoryCounts["stacked-prs"] += 1;
            }
        }

        entry.state = {
            refreshedAt: new Date().toISOString(),
            username,
            loading: false,
            error: null,
            counts,
            categoryCounts,
            notifications,
        };
        return entry.state;
    } catch (error) {
        entry.state = { ...entry.state, loading: false, error: errorMessage(error) };
        throw error;
    }
}

function sendJson(response, status, value) {
    const body = JSON.stringify(value);
    response.statusCode = status;
    response.setHeader("Content-Type", "application/json; charset=utf-8");
    response.setHeader("Cache-Control", "no-store");
    response.end(body);
}

async function readJson(request) {
    const chunks = [];
    let length = 0;
    for await (const chunk of request) {
        length += chunk.length;
        if (length > 1024 * 1024) {
            throw new Error("Request body is too large.");
        }
        chunks.push(chunk);
    }

    const body = Buffer.concat(chunks).toString("utf8");
    return body ? JSON.parse(body) : {};
}

function renderHtml(initialFilter) {
    const filters = [
        ["all", "All notifications"],
        ["my-prs", "My PRs"],
        ["other-open-prs", "Others' Open PRs"],
        ["other-draft-prs", "Others' Draft PRs"],
        ["stacked-prs", "Stacked PRs (not bottom)"],
        ["reviews", "PR review work"],
        ["assigned", "Assigned or mentioned"],
        ["high", "High priority"],
    ];
    const filterOptions = filters
        .map(([value, label]) => `<option value="${value}"${value === initialFilter ? " selected" : ""}>${label}</option>`)
        .join("");

    return `<!doctype html>
<html lang="en">
<head>
  <meta charset="utf-8">
  <meta name="viewport" content="width=device-width, initial-scale=1">
  <meta http-equiv="Content-Security-Policy" content="default-src 'self'; style-src 'unsafe-inline'; script-src 'unsafe-inline'">
  <title>GitHub notifications</title>
  <style>
    :root { color-scheme: light dark; }
    * { box-sizing: border-box; }
    body {
      margin: 0;
      padding: 24px;
      background: var(--background-color-default, #ffffff);
      color: var(--text-color-default, #1f2328);
      font-family: var(--font-sans, -apple-system, BlinkMacSystemFont, "Segoe UI", sans-serif);
      font-size: var(--text-body-medium, 14px);
      line-height: var(--leading-body-medium, 20px);
    }
    h1 { margin: 0; font-size: 24px; line-height: 32px; }
    a { color: var(--text-link-color, #0969da); }
    button, select {
      border: 1px solid var(--border-color-default, #d0d7de);
      border-radius: 6px;
      background: var(--background-color-default, #ffffff);
      color: inherit;
      font: inherit;
      padding: 6px 10px;
    }
    button { cursor: pointer; }
    button:hover { background: var(--background-color-neutral-muted, #f6f8fa); }
    button:disabled { cursor: wait; opacity: .6; }
    header, .toolbar, .summary, .card-header, .metadata, .actions { display: flex; align-items: center; gap: 10px; }
    header { justify-content: space-between; gap: 16px; margin-bottom: 18px; }
    .toolbar { flex-wrap: wrap; margin-bottom: 14px; }
    .toolbar label { display: inline-flex; align-items: center; gap: 6px; }
    .summary { flex-wrap: wrap; margin-bottom: 18px; color: var(--text-color-muted, #656d76); }
    .summary strong { color: var(--text-color-default, #1f2328); }
    .error { border: 1px solid var(--border-color-danger-muted, #ff818266); background: var(--background-color-danger-muted, #ffebe9); color: var(--text-color-danger, #d1242f); border-radius: 6px; padding: 10px 12px; margin-bottom: 14px; }
    #notifications { display: grid; gap: 12px; }
    .card { border: 1px solid var(--border-color-default, #d0d7de); border-radius: 8px; padding: 14px; }
    .card-header { align-items: flex-start; }
    .card-header > div:first-child { flex: 1; min-width: 0; }
    .title { font-weight: 600; overflow-wrap: anywhere; }
    .metadata { flex-wrap: wrap; color: var(--text-color-muted, #656d76); font-size: 12px; margin-top: 6px; }
    .badge { border-radius: 999px; padding: 2px 8px; font-size: 11px; font-weight: 600; white-space: nowrap; }
    .high { background: var(--true-color-red-muted, #ffebe9); color: var(--true-color-red, #cf222e); }
    .medium-high { background: #fff1e5; color: #9a6700; }
    .medium { background: var(--true-color-yellow-muted, #fff8c5); color: #7d4e00; }
    .medium-low { background: var(--true-color-blue-muted, #ddf4ff); color: #0969da; }
    .lowest { background: var(--background-color-neutral-muted, #f6f8fa); color: var(--text-color-muted, #656d76); }
    .review { margin-top: 10px; padding-top: 10px; border-top: 1px solid var(--border-color-muted, #d8dee4); }
    .actions { justify-content: flex-end; margin-top: 12px; }
    .empty { color: var(--text-color-muted, #656d76); padding: 28px 0; text-align: center; }
    .muted { color: var(--text-color-muted, #656d76); }
    @media (max-width: 640px) { body { padding: 16px; } header { align-items: flex-start; flex-direction: column; } }
  </style>
</head>
<body>
  <header>
    <div>
      <h1>GitHub notifications</h1>
      <div id="account" class="muted">Loading GitHub inbox...</div>
    </div>
    <div class="actions">
      <button id="cleanup" type="button">Run notification cleanup</button>
      <button id="refresh" type="button">Refresh</button>
    </div>
  </header>
  <div class="toolbar">
    <label for="filter">Show</label>
    <select id="filter">
      ${filterOptions}
    </select>
    <span class="muted">Dismissals are manual; stale cleanup rules remain in the notification-cleanup skill.</span>
  </div>
  <div id="cleanup-status" class="muted" role="status" aria-live="polite"></div>
  <div id="error" class="error" hidden></div>
  <div id="summary" class="summary"></div>
  <main id="notifications"></main>
  <script>
    const priorityClass = value => String(value || "LOWEST").toLowerCase().replaceAll("_", "-");
    const escapeHtml = value => String(value ?? "").replace(/[&<>"']/g, character => ({ "&": "&amp;", "<": "&lt;", ">": "&gt;", '"': "&quot;", "'": "&#39;" }[character]));
    const dateText = value => value ? new Date(value).toLocaleString([], { dateStyle: "medium", timeStyle: "short" }) : "unknown";
    let state = { notifications: [], counts: {}, categoryCounts: {}, username: null, refreshedAt: null };

    function visibleNotifications() {
      const filter = document.getElementById("filter").value;
      return state.notifications.filter(item => {
        if (filter === "my-prs") return item.isMine;
        if (filter === "other-open-prs") return item.isOtherOpen;
        if (filter === "other-draft-prs") return item.isOtherDraft;
        if (filter === "stacked-prs") return item.isStacked;
        if (filter === "reviews") return item.kind === "PullRequest";
        if (filter === "assigned") return item.reason === "assigned" || item.reason === "assign" || item.reason === "mention";
        if (filter === "high") return item.priority === "HIGH";
        return true;
      });
    }

    function render() {
      document.getElementById("account").textContent = state.username
        ? "@" + state.username + " - refreshed " + dateText(state.refreshedAt)
        : "GitHub inbox";
      const categorySummary = [
        ["my-prs", "My PRs"],
        ["other-open-prs", "Others' Open PRs"],
        ["other-draft-prs", "Others' Draft PRs"],
        ["stacked-prs", "Stacked (not bottom)"],
      ].filter(([category]) => state.categoryCounts[category])
        .map(([category, label]) => "<span><strong>" + label + "</strong> " + state.categoryCounts[category] + "</span>")
        .join(" · ");
      const prioritySummary = ["HIGH", "MEDIUM-HIGH", "MEDIUM", "MEDIUM-LOW", "LOWEST"]
        .filter(priority => state.counts[priority])
        .map(priority => "<span><strong>" + escapeHtml(priority) + "</strong> " + state.counts[priority] + "</span>")
        .join(" · ") || "<span>No notifications</span>";
      document.getElementById("summary").innerHTML = [categorySummary, prioritySummary].filter(Boolean).join(" · ");

      const items = visibleNotifications();
      document.getElementById("notifications").innerHTML = items.length
        ? items.map(renderCard).join("")
        : '<div class="empty">No notifications match this filter.</div>';
      document.querySelectorAll("[data-dismiss]").forEach(button => button.addEventListener("click", dismiss));
    }

    function renderCard(item) {
      const type = item.kind === "PullRequest" ? "PR" : escapeHtml(item.kind);
      const status = item.status && item.status !== "unknown" ? " · " + escapeHtml(item.status) : "";
      const stack = item.stackParent ? " · stacked on #" + escapeHtml(item.stackParent) : "";
      const review = item.kind === "PullRequest"
        ? '<div class="review"><strong>Review:</strong> ' + escapeHtml(item.reviewStatus || "not reviewed")
          + (item.reviewRequested ? " · review requested" : "")
          + (item.requestedReviewers?.length ? " · requested: " + escapeHtml(item.requestedReviewers.join(", ")) : "")
          + (item.approvedByUser ? " · approved by you" : "")
          + "</div>"
        : "";
      const category = item.kind === "PullRequest"
        ? '<div class="metadata"><span class="category">' + (item.isMine
          ? "My PR"
          : item.isOtherDraft
            ? "Other's Draft PR"
            : item.isOtherOpen
              ? "Other's Open PR"
              : "Other's PR")
          + (item.isStacked ? " · Stacked (not bottom)" : "") + "</span></div>"
        : "";
      const communityLabel = item.communityContribution ? " · community-contribution" : "";
      const detailError = item.error ? '<div class="muted">Details unavailable: ' + escapeHtml(item.error) + "</div>" : "";
      return '<article class="card">'
        + '<div class="card-header"><div><div class="title"><a href="' + escapeHtml(item.htmlUrl || "#") + '" target="_blank" rel="noreferrer">'
        + escapeHtml(item.title) + '</a></div><div class="metadata"><span>' + type + " " + escapeHtml(item.repository)
        + (item.number ? " #" + escapeHtml(item.number) : "") + '</span><span>reason: ' + escapeHtml(item.reason)
        + status + '</span><span>area: ' + escapeHtml(item.area?.label || "Other") + communityLabel + '</span><span>updated ' + dateText(item.updatedAt)
        + stack + '</span></div></div><span class="badge ' + priorityClass(item.priority) + '">' + escapeHtml(item.priority) + '</span></div>'
        + category + review + detailError
        + '<div class="actions"><button type="button" data-dismiss="' + escapeHtml(item.id) + '">Mark done</button></div></article>';
    }

    async function load(path, options) {
      const response = await fetch(path, options);
      const payload = await response.json();
      if (!response.ok) throw new Error(payload.error || "Request failed.");
      return payload;
    }

    async function refresh() {
      const button = document.getElementById("refresh");
      button.disabled = true;
      try {
        state = await load("/api/refresh", { method: "POST" });
        showError("");
        render();
      } catch (error) {
        showError(error.message);
      } finally {
        button.disabled = false;
      }
    }

    async function cleanup() {
      const button = document.getElementById("cleanup");
      const status = document.getElementById("cleanup-status");
      if (!window.confirm("Start the notification-cleanup skill? It will inspect stale notifications and ask before dismissing them.")) return;
      button.disabled = true;
      status.textContent = "Starting notification cleanup...";
      try {
        const payload = await load("/api/cleanup", { method: "POST" });
        showError("");
        status.textContent = payload.message;
      } catch (error) {
        status.textContent = "";
        showError(error.message);
      } finally {
        button.disabled = false;
      }
    }

    async function dismiss(event) {
      const id = event.currentTarget.dataset.dismiss;
      if (!window.confirm("Mark this GitHub notification as done?")) return;
      event.currentTarget.disabled = true;
      try {
        state = await load("/api/dismiss", { method: "POST", headers: { "Content-Type": "application/json" }, body: JSON.stringify({ id }) });
        showError("");
        render();
      } catch (error) {
        showError(error.message);
        event.currentTarget.disabled = false;
      }
    }

    function showError(message) {
      const element = document.getElementById("error");
      element.textContent = message || "";
      element.hidden = !message;
    }

    document.getElementById("refresh").addEventListener("click", refresh);
    document.getElementById("cleanup").addEventListener("click", cleanup);
    document.getElementById("filter").addEventListener("change", render);
    load("/api/state").then(payload => { state = payload; render(); }).catch(error => showError(error.message));
  </script>
</body>
</html>`;
}

async function handleRequest(entry, request, response) {
    const requestUrl = new URL(request.url || "/", "http://127.0.0.1");

    if (request.method === "GET" && requestUrl.pathname === "/") {
        response.setHeader("Content-Type", "text/html; charset=utf-8");
        response.end(renderHtml(entry.filter));
        return;
    }
    if (request.method === "GET" && requestUrl.pathname === "/api/state") {
        sendJson(response, 200, entry.state);
        return;
    }
    if (request.method === "POST" && requestUrl.pathname === "/api/refresh") {
        try {
            await refreshEntry(entry);
            sendJson(response, 200, entry.state);
        } catch (error) {
            sendJson(response, 500, { ...entry.state, error: errorMessage(error) });
        }
        return;
    }
    if (request.method === "POST" && requestUrl.pathname === "/api/cleanup") {
        try {
            await entry.triggerCleanup();
            sendJson(response, 202, {
                started: true,
                message: "Notification cleanup started in the chat. Follow its confirmation prompt before dismissing anything.",
            });
        } catch (error) {
            sendJson(response, 500, { error: errorMessage(error) });
        }
        return;
    }
    if (request.method === "POST" && requestUrl.pathname === "/api/dismiss") {
        const body = await readJson(request);
        const id = typeof body.id === "string" ? body.id : "";
        if (!id || !entry.state.notifications.some((item) => item.id === id)) {
            sendJson(response, 400, { error: "A notification id from the current inbox is required." });
            return;
        }

        try {
            await runGhApi(["-X", "DELETE", `notifications/threads/${encodeURIComponent(id)}`]);
            await refreshEntry(entry);
            sendJson(response, 200, entry.state);
        } catch (error) {
            sendJson(response, 500, { ...entry.state, error: errorMessage(error) });
        }
        return;
    }

    sendJson(response, 404, { error: "Not found." });
}

async function startServer(entry) {
    const server = createServer((request, response) => {
        handleRequest(entry, request, response).catch((error) => {
            if (!response.headersSent) {
                sendJson(response, 500, { error: errorMessage(error) });
            } else {
                response.destroy(error);
            }
        });
    });

    await new Promise((resolve, reject) => {
        server.once("error", reject);
        server.listen(0, "127.0.0.1", resolve);
    });
    const address = server.address();
    const port = typeof address === "object" && address ? address.port : 0;
    return { server, url: `http://127.0.0.1:${port}/` };
}

function requireEntry(instanceId) {
    const entry = servers.get(instanceId);
    if (!entry) {
        throw new CanvasError("canvas_instance_not_open", `Canvas instance ${instanceId} is not open.`);
    }
    return entry;
}

export function createNotificationCanvas({ triggerCleanup }) {
    if (typeof triggerCleanup !== "function") {
        throw new Error("A cleanup trigger is required.");
    }

    return {
        actions: [
            {
                name: "refresh",
                description: "Refresh GitHub notifications and calculate morning-triage priority.",
                handler: async (ctx) => {
                    const entry = requireEntry(ctx.instanceId);
                    await refreshEntry(entry);
                    return summarize(entry.state);
                },
            },
            {
                name: "get_state",
                description: "Return the current notification and pull request review queue.",
                handler: async (ctx) => requireEntry(ctx.instanceId).state,
            },
            {
                name: "run_cleanup",
                description: "Ask the active agent to run the notification-cleanup skill with its safety rules.",
                handler: async () => {
                    await triggerCleanup();
                    return {
                        started: true,
                        message: "Notification cleanup started in the chat.",
                    };
                },
            },
            {
                name: "dismiss_notification",
                description: "Mark one GitHub notification as done after the user explicitly chooses it.",
                inputSchema: {
                    type: "object",
                    properties: { notificationId: { type: "string" } },
                    required: ["notificationId"],
                    additionalProperties: false,
                },
                handler: async (ctx) => {
                    const entry = requireEntry(ctx.instanceId);
                    const notificationId = ctx.input?.notificationId;
                    if (typeof notificationId !== "string" || !entry.state.notifications.some((item) => item.id === notificationId)) {
                        throw new CanvasError("notification_not_found", "The notification is not present in the current queue.");
                    }
                    await runGhApi(["-X", "DELETE", `notifications/threads/${encodeURIComponent(notificationId)}`]);
                    await refreshEntry(entry);
                    return summarize(entry.state);
                },
            },
        ],
        open: async (ctx) => {
            let entry = servers.get(ctx.instanceId);
            if (!entry) {
                entry = { state: emptyState(), server: null, url: null, filter: "all", triggerCleanup };
                const server = await startServer(entry);
                entry.server = server.server;
                entry.url = server.url;
                servers.set(ctx.instanceId, entry);
            }
            if (ctx.input?.filter) {
                entry.filter = ctx.input.filter;
            }

            try {
                await refreshEntry(entry);
            } catch (error) {
                entry.state = { ...entry.state, error: errorMessage(error) };
            }

            return {
                title: "GitHub notifications",
                status: entry.state.error ? "Refresh failed" : "Ready",
                url: entry.url,
            };
        },
        onClose: async (ctx) => {
            const entry = servers.get(ctx.instanceId);
            if (!entry) {
                return;
            }

            servers.delete(ctx.instanceId);
            await new Promise((resolve, reject) => {
                entry.server.close((error) => error ? reject(error) : resolve());
            });
        },
    };
}
