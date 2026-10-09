#!/usr/bin/env python3
"""Cooperative same-host leases and mechanical handback receipts."""

import argparse
import contextlib
import datetime
import json
import os
from pathlib import Path
import re
import socket
import subprocess
import sys
import tempfile
import uuid


class ProtocolError(Exception):
    pass


def require(condition, message):
    if not condition:
        raise ProtocolError(message)


def canonical(path):
    return os.path.normcase(os.path.realpath(path))


def environment():
    return {"host": socket.gethostname(), "platform": sys.platform, "os": os.name}


def timestamp():
    return datetime.datetime.now(datetime.timezone.utc).isoformat()


def read_json(path):
    with open(path, encoding="utf-8-sig") as stream:
        value = json.load(stream)
    require(isinstance(value, dict), f"Expected a JSON object: {path}")
    return value


def atomic_json(path, value):
    path = Path(path)
    path.parent.mkdir(parents=True, exist_ok=True)
    descriptor, temporary = tempfile.mkstemp(prefix=".write-", dir=path.parent)
    try:
        with os.fdopen(descriptor, "w", encoding="utf-8", newline="\n") as stream:
            json.dump(value, stream, ensure_ascii=True, sort_keys=True, separators=(",", ":"))
            stream.write("\n")
            stream.flush()
            os.fsync(stream.fileno())
        os.replace(temporary, path)
        if os.name != "nt":
            descriptor = os.open(path.parent, os.O_RDONLY)
            try:
                os.fsync(descriptor)
            finally:
                os.close(descriptor)
    finally:
        if os.path.exists(temporary):
            os.unlink(temporary)


@contextlib.contextmanager
def exclusive_lock(path):
    path.parent.mkdir(parents=True, exist_ok=True)
    with open(path, "a+b") as stream:
        stream.seek(0, os.SEEK_END)
        if stream.tell() == 0:
            stream.write(b"\0")
            stream.flush()
        stream.seek(0)
        try:
            if os.name == "nt":
                import msvcrt
                msvcrt.locking(stream.fileno(), msvcrt.LK_NBLCK, 1)
            else:
                import fcntl
                fcntl.flock(stream.fileno(), fcntl.LOCK_EX | fcntl.LOCK_NB)
        except OSError as error:
            raise ProtocolError("Another participating writer holds this Git common-directory lock.") from error
        try:
            yield
        finally:
            stream.seek(0)
            if os.name == "nt":
                msvcrt.locking(stream.fileno(), msvcrt.LK_UNLCK, 1)
            else:
                fcntl.flock(stream.fileno(), fcntl.LOCK_UN)


def git(worktree, *arguments, allowed=(0,)):
    result = subprocess.run(
        ["git", "--no-optional-locks", "-C", worktree, "-c", "core.longpaths=true", *arguments],
        stdout=subprocess.PIPE, stderr=subprocess.PIPE, encoding="utf-8", errors="strict",
    )
    require(result.returncode in allowed,
            f"Git failed ({result.returncode}): {arguments!r}\n{result.stderr}{result.stdout}")
    if result.stderr:
        print(result.stderr.rstrip(), file=sys.stderr)
    text = result.stdout[:-1] if result.stdout.endswith("\n") else result.stdout
    return result.returncode, text


def oid(worktree, value):
    object_format = git(worktree, "rev-parse", "--show-object-format")[1]
    length = {"sha1": 40, "sha256": 64}.get(object_format)
    require(length is not None and re.fullmatch(f"[0-9a-f]{{{length}}}", value or ""),
            "Expected a full lowercase object ID for this repository.")
    return value


def snapshot(worktree, branch):
    worktree = canonical(worktree)
    root = canonical(git(worktree, "rev-parse", "--show-toplevel")[1])
    require(root == worktree, "Worktree must be its exact root, not a subdirectory.")
    require(branch.startswith("refs/heads/"), "Branch must be a full refs/heads/ ref.")
    git(worktree, "check-ref-format", branch)
    require(git(worktree, "symbolic-ref", "--quiet", branch, allowed=(0, 1))[0] == 1,
            "Owned branch must be a direct ref, not a symbolic alias.")
    status = git(worktree, "status", "--porcelain=v1", "--untracked-files=all")[1]
    symbolic = git(worktree, "symbolic-ref", "--quiet", "HEAD", allowed=(0, 1))
    common = canonical(git(worktree, "rev-parse", "--path-format=absolute", "--git-common-dir")[1])
    occupants = []
    current_path = None
    for field in git(worktree, "worktree", "list", "--porcelain", "-z")[1].split("\0"):
        if field.startswith("worktree "):
            current_path = canonical(field[9:])
        elif field == f"branch {branch}":
            require(current_path is not None, "Malformed worktree record.")
            occupants.append(current_path)
    operations = []
    for marker in ("rebase-merge", "rebase-apply", "MERGE_HEAD", "CHERRY_PICK_HEAD",
                   "REVERT_HEAD", "BISECT_START", "sequencer"):
        path = git(worktree, "rev-parse", "--path-format=absolute", "--git-path", marker)[1]
        if os.path.lexists(path):
            operations.append(marker)
    return {
        "worktree": worktree, "commonDir": common, "branch": branch,
        "head": git(worktree, "rev-parse", "--verify", "HEAD^{commit}")[1],
        "branchHead": git(worktree, "rev-parse", "--verify", f"{branch}^{{commit}}")[1],
        "symbolicHead": symbolic[1] if symbolic[0] == 0 else None,
        "clean": not status, "gitOperations": operations, "branchOccupants": occupants,
    }


def clean(value):
    require(value["clean"], "Worktree is dirty; preserve user work.")
    require(not value["gitOperations"], f"Unfinished Git operation: {value['gitOperations']}")


def attached(value, target):
    clean(value)
    require(value["symbolicHead"] == value["branch"] and
            value["head"] == value["branchHead"] == target and
            value["branchOccupants"] == [value["worktree"]],
            "Final attached checkout/branch/occupancy does not match the target.")


def detached(value, expected_head, expected_old, target=None):
    clean(value)
    require(value["symbolicHead"] is None and not value["branchOccupants"],
            "Expected a detached, unoccupied owner worktree.")
    require(value["head"] == expected_head, "Detached HEAD drifted.")
    require(value["branchHead"] == expected_old or
            (target is not None and value["branchHead"] == target), "Unexpected branch SHA.")


class Store:
    def __init__(self, worktree):
        self.worktree = canonical(worktree)
        root = canonical(git(self.worktree, "rev-parse", "--show-toplevel")[1])
        require(root == self.worktree, "Worktree must be its exact root.")
        self.common = canonical(git(self.worktree, "rev-parse", "--path-format=absolute", "--git-common-dir")[1])
        self.directory = Path(self.common) / "copilot-owner-light"
        self.path = self.directory / "lease.json"
        self.lock_path = self.directory / "writer.lock"

    def load(self):
        if not self.path.exists():
            return None
        value = read_json(self.path)
        require(value.get("schema") == 1 and value.get("commonDir") == self.common and
                value.get("environment") == environment(), "Lease schema, clone or execution host changed.")
        return value

    def save(self, value):
        value["revision"] += 1
        value["updated"] = timestamp()
        atomic_json(self.path, value)

    def authorize(self, arguments):
        value = self.load()
        require(value is not None, "No durable lease exists.")
        require(value["leaseId"] == arguments.lease_id, "Stale or mismatched lease token.")
        require(value["executor"] == arguments.actor, "Actor is not the designated executor.")
        require(value["status"] == "active" and value["pending"] is None,
                "Lease is interrupted or terminal; reconcile before further mutation.")
        require(arguments.generation == value["generation"], "Stale or unannounced generation.")
        scope = value["scopes"].get(self.worktree)
        require(scope is not None and scope["phase"] not in ("released", "resumed", "correction"),
                "This worktree has no active executor scope.")
        return value, scope

    def receipt(self, value, scope, action, evidence):
        receipt = {
            "schema": 1, "leaseId": value["leaseId"], "operation": value["operation"],
            "generation": value["generation"], "actor": value["executor"], "action": action,
            "worktree": scope["request"]["worktree"], "branch": scope["request"]["branch"],
            "evidence": evidence, "created": timestamp(),
        }
        path = self.directory / "receipts" / value["leaseId"] / f"{uuid.uuid4().hex}.json"
        atomic_json(path, receipt)
        scope["receipt"] = str(path)
        return str(path)

    def begin(self, value, action, plan):
        value["pending"] = {"action": action, "plan": plan, "worktree": self.worktree,
                            "parentPid": os.getpid(), "started": timestamp()}
        self.save(value)

    def commit(self, value):
        value["pending"] = None
        self.save(value)


def request_identity(request, worktree):
    required = ("operation", "leaseId", "executor", "owner", "branch", "preparedHead",
                "completion", "actions", "source", "sourceRef")
    require(all(key in request for key in required), "Lease request is incomplete.")
    require(re.fullmatch(r"[A-Za-z0-9][A-Za-z0-9._-]{0,79}", request["operation"]),
            "Invalid operation ID.")
    require(re.fullmatch(r"[0-9a-f]{32}", request["leaseId"]), "Use a fresh uuid4().hex lease token.")
    require(request["completion"] in ("local-only", "published", "checkout-sync"),
            "Invalid completion policy.")
    actions = request["actions"]
    require(isinstance(actions, list) and len(set(actions)) == len(actions) and
            set(actions) <= {"attach", "sync", "replay", "publish"} and "attach" in actions,
            "Invalid scoped actions.")
    require(request["completion"] == "local-only" or "sync" in actions,
            "Published/checkout-sync completion requires tracking synchronization.")
    require("publish" not in actions or request.get("publicationAuthorized") is True,
            "Publication action lacks separately recorded user authorization.")
    require(all(isinstance(request[key], str) and request[key] for key in ("executor", "owner", "branch")),
            "Invalid actor/branch identity.")
    require(not any(c in request["source"] for c in "\r\n\0") and
            not request["source"].startswith("-"), "Invalid transfer source.")
    request = dict(request)
    request["worktree"] = worktree
    oid(worktree, request["preparedHead"])
    git(worktree, "check-ref-format", request["sourceRef"])
    require(request["sourceRef"].startswith("refs/"), "Transfer source must be a full ref.")
    if os.path.isdir(request["source"]):
        request["source"] = canonical(request["source"])
        request["sourceIdentity"] = request["source"]
    else:
        request["sourceIdentity"] = git(worktree, "remote", "get-url", request["source"])[1]
    if request["completion"] != "local-only":
        remote = request.get("remote", "")
        require(remote and not remote.startswith("-") and not any(c.isspace() for c in remote),
                "Named remote required for tracking sync.")
        request["remoteUrl"] = git(worktree, "remote", "get-url", remote)[1]
        request["trackingRef"] = f"refs/remotes/{remote}/{request['branch'][len('refs/heads/'):]}"
        git(worktree, "check-ref-format", request["trackingRef"])
        require(re.fullmatch(r"[A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+", request.get("repository", "")) and
                isinstance(request.get("pr"), int) and request["pr"] > 0 and request.get("prBase"),
                "Live PR verification needs repository, PR number and expected base.")
    return request


def acquire(arguments, store):
    require(arguments.mutation_authorized and arguments.quiesced,
            "Owner must acknowledge mutation authority, quiescence and the exact request.")
    request = request_identity(read_json(arguments.request), store.worktree)
    require(request["owner"] == arguments.owner, "Only the named owner may acknowledge this scope.")
    current = snapshot(store.worktree, request["branch"])
    detached(current, request["preparedHead"], request["preparedHead"])
    value = store.load()
    if value is not None and value["status"] == "released":
        require(request["leaseId"] != value["leaseId"], "Released lease tokens cannot be reused.")
        archive = store.directory / "history" / f"{value['leaseId']}.json"
        require(not archive.exists(), "History token collision.")
        atomic_json(archive, value)
        value = None
    if value is None:
        require(not (store.directory / "history" / f"{request['leaseId']}.json").exists(),
                "A prior operation already used this lease token.")
        value = {
            "schema": 1, "leaseId": request["leaseId"], "operation": request["operation"],
            "executor": request["executor"], "environment": environment(), "commonDir": store.common,
            "generation": arguments.generation, "revision": 0, "status": "active",
            "pending": None, "scopes": {}, "created": timestamp(),
        }
    require(value["leaseId"] == request["leaseId"] and value["operation"] == request["operation"] and
            value["executor"] == request["executor"] and value["status"] == "active" and
            value["pending"] is None and value["generation"] == arguments.generation,
            "Another operation owns this clone, or its generation is not ready.")
    previous = value["scopes"].get(store.worktree)
    if previous is not None:
        require(previous["request"] == request and previous["last"] == current and
                previous["phase"] == "prepared", "Scope changed; a new owner handoff is required.")
        return {"phase": "PREPARED_DETACHED", "lease": str(store.path), "leaseId": value["leaseId"],
                "generation": value["generation"], "receipt": previous["receipt"], "alreadyAcquired": True}
    require(all(item["request"]["branch"] != request["branch"] for item in value["scopes"].values()),
            "Branch already has an owner scope in this clone.")
    scope = {"request": request, "last": current, "phase": "prepared", "target": None,
             "parent": None, "sync": None, "receipt": None}
    value["scopes"][store.worktree] = scope
    receipt = store.receipt(value, scope, "acquire", {"snapshot": current, "owner": arguments.owner})
    store.save(value)
    return {"phase": "PREPARED_DETACHED", "lease": str(store.path), "leaseId": value["leaseId"],
            "generation": value["generation"], "head": current["head"], "receipt": receipt}


def ancestry(worktree, parent, target):
    oid(worktree, parent)
    require(git(worktree, "merge-base", "--is-ancestor", parent, target, allowed=(0, 1))[0] == 0,
            "Final parent is not an ancestor of the target.")


def attach_scope(arguments, store):
    value, scope = store.authorize(arguments)
    require("attach" in scope["request"]["actions"], "Checkout is not authorized.")
    plan = read_json(arguments.plan)
    target = oid(store.worktree, plan.get("target"))
    parent = oid(store.worktree, plan.get("parent"))
    require(plan.get("expectedHead") == scope["last"]["head"] and
            plan.get("expectedOld") == scope["last"]["branchHead"], "Plan does not match the durable checkpoint.")
    current = snapshot(store.worktree, scope["request"]["branch"])
    if scope["phase"] in ("attached", "synced"):
        require(scope["target"] == target and scope["parent"] == parent, "Attached target changed; reopen explicitly.")
        attached(current, target)
        require(current == scope["last"], "Attached worktree drifted.")
        return {"phase": "ATTACHED_FROZEN", "receipt": scope["receipt"], "alreadyAttached": True}
    detached(current, plan["expectedHead"], plan["expectedOld"], target)
    request = scope["request"]
    if os.path.isdir(request["source"]):
        require(canonical(request["source"]) == request["sourceIdentity"], "Transfer source changed.")
    else:
        require(git(store.worktree, "remote", "get-url", request["source"])[1] == request["sourceIdentity"],
                "Transfer remote URL changed since the handoff.")
    store.begin(value, "attach", plan)
    backup = transfer = None
    if current["branchHead"] != target:
        zero = "0" * len(target)
        namespace = f"refs/copilot/{value['operation']}/g{value['generation']}/{uuid.uuid4().hex}"
        backup, transfer = f"{namespace}/backup", f"{namespace}/transfer"
        git(store.worktree, "update-ref", "--no-deref", backup, plan["expectedOld"], zero)
        require(git(store.worktree, "rev-parse", "--verify", backup)[1] == plan["expectedOld"],
                "Recovery backup does not match the expected old tip.")
        value["pending"]["backupRef"], value["pending"]["transferRef"] = backup, transfer
        store.save(value)
        git(store.worktree, "fetch", "--quiet", "--no-tags", "--no-write-fetch-head",
            "--no-recurse-submodules", "--no-prune", "--no-prune-tags", "--no-auto-maintenance",
            "--no-write-commit-graph", "--refmap=", "--",
            scope["request"]["source"], f"{scope['request']['sourceRef']}:{transfer}")
        require(git(store.worktree, "rev-parse", "--verify", f"{transfer}^{{commit}}")[1] == target,
                "Transferred commit differs from the intended target; recovery refs retained.")
        ancestry(store.worktree, parent, target)
        detached(snapshot(store.worktree, scope["request"]["branch"]),
                 plan["expectedHead"], plan["expectedOld"], target)
        git(store.worktree, "update-ref", "--no-deref", scope["request"]["branch"], target, plan["expectedOld"])
    ancestry(store.worktree, parent, target)
    detached(snapshot(store.worktree, scope["request"]["branch"]), plan["expectedHead"], target)
    git(store.worktree, "switch", "--quiet", "--", scope["request"]["branch"][len("refs/heads/"):])
    final = snapshot(store.worktree, scope["request"]["branch"])
    attached(final, target)
    scope.update(last=final, phase="attached", target=target, parent=parent, sync=None)
    receipt = store.receipt(value, scope, "attach", {
        "snapshot": final, "parent": parent, "backupRef": backup, "transferRef": transfer,
    })
    store.commit(value)
    return {"phase": "ATTACHED_FROZEN", "head": target, "receipt": receipt, "leaseId": value["leaseId"]}


def published_identity(worktree, request, target):
    require(git(worktree, "remote", "get-url", request["remote"])[1] == request["remoteUrl"],
            "Remote URL changed since the owner handoff.")
    lines = git(worktree, "ls-remote", "--refs", request["remote"], request["branch"])[1].splitlines()
    require(len(lines) == 1 and lines[0].split() == [target, request["branch"]],
            "Published branch no longer matches the intended target.")
    response = subprocess.run(
        ["gh", "api", f"repos/{request['repository']}/pulls/{request['pr']}"],
        stdout=subprocess.PIPE, stderr=subprocess.PIPE, encoding="utf-8",
    )
    require(response.returncode == 0, f"PR identity lookup failed: {response.stderr}")
    pr = json.loads(response.stdout)
    require(pr["state"] == "open" and pr["head"]["sha"] == target and
            pr["head"]["ref"] == request["branch"][len("refs/heads/"):] and
            pr["base"]["ref"] == request["prBase"], "PR head/base/state does not match the handback.")
    return {"remote": request["remote"], "remoteUrl": request["remoteUrl"],
            "remoteHead": target, "pr": request["pr"], "prBase": request["prBase"],
            "prHead": pr["head"]["sha"], "prState": pr["state"]}


def sync_scope(arguments, store):
    value, scope = store.authorize(arguments)
    request = scope["request"]
    require("sync" in request["actions"] and scope["phase"] in ("attached", "synced"),
            "Tracking sync is not authorized or attachment is not verified.")
    current = snapshot(store.worktree, request["branch"])
    attached(current, scope["target"])
    require(current == scope["last"], "Checkout changed since attachment.")
    require(git(store.worktree, "symbolic-ref", "--quiet", request["trackingRef"], allowed=(0, 1))[0] == 1,
            "Owned tracking ref must be direct, not a symbolic alias.")
    ancestry(store.worktree, scope["parent"], scope["target"])
    identity = published_identity(store.worktree, request, scope["target"])
    store.begin(value, "sync", {"target": scope["target"], "parent": scope["parent"]})
    git(store.worktree, "fetch", "--quiet", "--no-tags", "--no-write-fetch-head",
        "--no-recurse-submodules", "--no-prune", "--no-prune-tags", "--no-auto-maintenance",
        "--no-write-commit-graph", "--refmap=", "--",
        request["remote"], f"+{request['branch']}:{request['trackingRef']}")
    require(git(store.worktree, "rev-parse", "--verify", request["trackingRef"])[1] == scope["target"],
            "Tracking tip drifted during fetch.")
    require(git(store.worktree, "rev-list", "--left-right", "--count",
                f"HEAD...{request['trackingRef']}")[1].split() == ["0", "0"], "Tracking divergence is not 0/0.")
    final = snapshot(store.worktree, request["branch"])
    attached(final, scope["target"])
    identity = published_identity(store.worktree, request, scope["target"])
    scope.update(last=final, phase="synced", sync=identity)
    receipt = store.receipt(value, scope, "sync", {
        "snapshot": final, "publication": identity, "trackingRef": request["trackingRef"], "aheadBehind": [0, 0],
    })
    store.commit(value)
    return {"phase": "TRACKING_SYNCED", "head": scope["target"], "receipt": receipt}


def complete_scope(arguments, store):
    value, scope = store.authorize(arguments)
    require(arguments.quiesced, "Release requires finished owned processes and checked stack-tool state.")
    require(arguments.global_gates_verified and arguments.evidence,
            "Release requires recorded operation-wide gate verification before any clone is completed.")
    request = scope["request"]
    require(scope["phase"] in ("attached", "synced"), "No verified final handback.")
    final = snapshot(store.worktree, request["branch"])
    attached(final, scope["target"])
    require(final == scope["last"], "Final worktree changed before release.")
    ancestry(store.worktree, scope["parent"], scope["target"])
    identity = None
    if request["completion"] != "local-only":
        require(scope["phase"] == "synced", "Tracking sync must precede release.")
        identity = published_identity(store.worktree, request, scope["target"])
        require(git(store.worktree, "rev-parse", "--verify", request["trackingRef"])[1] == scope["target"],
                "Tracking tip changed before release.")
    scope["phase"] = "released"
    receipt = store.receipt(value, scope, "complete", {
        "snapshot": final, "parent": scope["parent"], "completion": request["completion"], "publication": identity,
        "globalGateEvidence": arguments.evidence,
    })
    if all(item["phase"] in ("released", "resumed") for item in value["scopes"].values()):
        value["status"] = "released"
    store.save(value)
    return {"phase": "RELEASED", "leaseId": value["leaseId"], "generation": value["generation"],
            "head": scope["target"], "receipt": receipt, "completion": request["completion"]}


def resume_owner(arguments, store):
    value = store.load()
    require(value is not None and value["leaseId"] == arguments.lease_id, "Stale or absent release token.")
    scope = value["scopes"].get(store.worktree)
    require(scope is not None and scope["request"]["owner"] == arguments.owner, "Owner is outside this scope.")
    require(arguments.generation == value["generation"] and arguments.head == scope["target"],
            "Release generation/head does not match the terminal record.")
    if value["status"] == "released" and value["pending"] is None and scope["phase"] == "resumed":
        return {"phase": "RESUMED", "leaseId": value["leaseId"], "head": scope["target"], "alreadyResumed": True}
    require(value["pending"] is None and scope["phase"] == "released",
            "Owner remains frozen; the matching scope has not been released.")
    # Do not let an owner write shared refs while another participant in that clone is still frozen.
    require(value["status"] == "released", "Other scopes in this clone are still active.")
    current = snapshot(store.worktree, scope["request"]["branch"])
    attached(current, scope["target"])
    require(current == scope["last"], "Checkout changed before owner resume.")
    scope["phase"] = "resumed"
    store.save(value)
    return {"phase": "RESUMED", "leaseId": value["leaseId"], "head": scope["target"]}


def advance(arguments, store):
    value = store.load()
    require(value is not None and value["leaseId"] == arguments.lease_id and
            value["executor"] == arguments.actor and value["status"] == "active" and value["pending"] is None,
            "Lease cannot advance while interrupted, terminal or owned by another actor.")
    require(arguments.generation > value["generation"], "New generation must increase.")
    for scope in value["scopes"].values():
        require(scope["phase"] not in ("released", "resumed", "correction"), "Scope is released or with its owner.")
        current = snapshot(scope["request"]["worktree"], scope["request"]["branch"])
        clean(current)
        require(current == scope["last"], "Unannounced worktree/ref drift during generation advance.")
        scope["sync"] = None
        if scope["phase"] == "synced":
            scope["phase"] = "attached"
    value["generation"] = arguments.generation
    store.save(value)
    return {"generation": value["generation"], "leaseId": value["leaseId"], "revision": value["revision"]}


def correction(arguments, store):
    value, scope = store.authorize(arguments)
    require(arguments.owner == scope["request"]["owner"], "Correction must return to the existing owner.")
    require(arguments.evidence and all(item["phase"] not in ("released", "resumed", "correction")
                                      for item in value["scopes"].values()),
            "Correction needs evidence and fully frozen clone scopes.")
    current = snapshot(store.worktree, scope["request"]["branch"])
    clean(current)
    require(current == scope["last"], "Worktree changed before the correction handoff.")
    scope["phase"] = "correction"
    scope["sync"] = None
    scope["correctionEvidence"] = arguments.evidence
    store.save(value)
    return {"phase": "OWNER_CORRECTION", "leaseId": value["leaseId"], "owner": arguments.owner}


def reprepare(arguments, store):
    require(arguments.quiesced and arguments.mutation_authorized, "New owner preparation attestations required.")
    value = store.load()
    require(value is not None and value["leaseId"] == arguments.lease_id and value["status"] == "active" and
            value["pending"] is None, "Lease cannot accept an owner correction.")
    scope = value["scopes"].get(store.worktree)
    require(scope is not None and scope["phase"] == "correction" and
            scope["request"]["owner"] == arguments.owner, "No correction lease for this owner.")
    require(arguments.generation > value["generation"], "Correction requires a new generation.")
    current = snapshot(store.worktree, scope["request"]["branch"])
    head = oid(store.worktree, arguments.head)
    detached(current, head, head)
    for path, item in value["scopes"].items():
        if path != store.worktree:
            require(item["phase"] not in ("released", "resumed", "correction"),
                    "Another participant is released or making a correction.")
            require(snapshot(path, item["request"]["branch"]) == item["last"],
                    "Another participant changed during owner correction.")
            item["sync"] = None
            if item["phase"] == "synced":
                item["phase"] = "attached"
    scope.update(last=current, phase="prepared", target=None, parent=None, sync=None)
    value["generation"] = arguments.generation
    receipt = store.receipt(value, scope, "reprepare", {"snapshot": current, "owner": arguments.owner})
    store.save(value)
    return {"phase": "PREPARED_DETACHED", "generation": value["generation"], "head": head, "receipt": receipt}


def run_scoped(arguments, store):
    value, _ = store.authorize(arguments)
    require(arguments.action in ("replay", "publish"), "Only scoped replay/publication commands are accepted.")
    require(arguments.command and arguments.command[0] == "--" and len(arguments.command) > 1,
            "Pass the reviewed executable and arguments after --; no shell interpolation.")
    for item in value["scopes"].values():
        require(arguments.action in item["request"]["actions"] and
                item["phase"] not in ("released", "resumed", "correction"),
                "Every affected clone scope must authorize this action and remain frozen.")
        current = snapshot(item["request"]["worktree"], item["request"]["branch"])
        clean(current)
        require(current == item["last"], "Worktree changed before executor command.")
        if arguments.action == "publish":
            require(item["phase"] in ("attached", "synced"), "Publication requires final attachment receipts.")
    store.begin(value, arguments.action, {"command": arguments.command[1:]})
    log = store.directory / "logs" / value["leaseId"] / f"{uuid.uuid4().hex}.log"
    log.parent.mkdir(parents=True, exist_ok=True)
    with open(log, "wb") as stream:
        child = subprocess.Popen(arguments.command[1:], cwd=store.worktree, stdout=stream, stderr=subprocess.STDOUT)
        value["pending"].update(childPid=child.pid, log=str(log))
        store.save(value)
        code = child.wait()
    require(code == 0, f"Executor command failed ({code}); lease remains interrupted. Log: {log}")
    for item in value["scopes"].values():
        final = snapshot(item["request"]["worktree"], item["request"]["branch"])
        clean(final)
        item["last"] = final
        if arguments.action == "replay":
            item.update(phase="prepared", target=None, parent=None, sync=None)
    store.commit(value)
    return {"phase": "COMMAND_COMPLETED", "exit": code, "log": str(log), "revision": value["revision"],
            "note": "Command success is not validation or publication identity verification."}


def verify_executor(arguments, store):
    value, scope = store.authorize(arguments)
    plan = read_json(arguments.plan)
    target = oid(store.worktree, plan.get("target"))
    parent = oid(store.worktree, plan.get("parent"))
    final = snapshot(store.worktree, scope["request"]["branch"])
    attached(final, target)
    require(final == scope["last"], "Durable attachment checkpoint changed.")
    ancestry(store.worktree, parent, target)
    scope.update(phase="attached", target=target, parent=parent, sync=None)
    receipt = store.receipt(value, scope, "verify-attached", {"snapshot": final, "parent": parent})
    store.save(value)
    return {"phase": "ATTACHED_FROZEN", "head": target, "receipt": receipt}


def recover(arguments, store):
    require(arguments.executor_stopped and arguments.evidence, "Recovery needs old executor/children stopped evidence.")
    value = store.load()
    require(value is not None and value["leaseId"] == arguments.lease_id and
            value["executor"] == arguments.actor and value["revision"] == arguments.expected_revision and
            value["pending"] is not None and value["status"] == "active",
            "Stale recovery, wrong actor, or no interrupted action.")
    plan = read_json(arguments.plan)
    expected = plan.get("checkpoints")
    require(isinstance(expected, dict) and set(expected) == set(value["scopes"]),
            "Recovery must reconcile every participant in this clone.")
    for path, item in value["scopes"].items():
        current = snapshot(path, item["request"]["branch"])
        clean(current)
        require(current == expected[path], "Recovery snapshot does not match reviewed current state.")
        require(current["symbolicHead"] in (None, item["request"]["branch"]), "Unexpected recovery checkout.")
        item.update(last=current, phase="prepared", target=None, parent=None, sync=None)
    receipt = store.directory / "recovery" / value["leaseId"] / f"{uuid.uuid4().hex}.json"
    atomic_json(receipt, {"interrupted": value["pending"], "evidence": arguments.evidence,
                         "checkpoints": expected, "created": timestamp()})
    value["pending"] = None
    store.save(value)
    return {"phase": "RECONCILED", "receipt": str(receipt), "revision": value["revision"]}


def inspect(arguments, store):
    value = store.load()
    if value is None:
        return {"phase": "NO_LEASE", "environment": environment(), "commonDir": store.common}
    scope = value["scopes"].get(store.worktree)
    return {"lease": str(store.path), "leaseId": value["leaseId"], "operation": value["operation"],
            "generation": value["generation"], "revision": value["revision"],
            "executor": value["executor"], "status": value["status"],
            "pending": value["pending"], "scope": scope}


def guard_helper(arguments, store):
    value = store.load()
    require(value is None or (value["status"] == "released" and value["pending"] is None),
            "Active owner-light lease: use its executor commands, not the owner-driven Attach helper.")
    return {"phase": "OWNER_DRIVEN_ALLOWED"}


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("action", choices=("inspect", "acquire", "attach", "verify-executor", "sync",
                                         "complete", "resume", "advance", "correction", "reprepare", "run", "recover",
                                         "guard-helper", "verify-attached"))
    parser.add_argument("--worktree", required=True)
    parser.add_argument("--request")
    parser.add_argument("--plan")
    parser.add_argument("--lease-id")
    parser.add_argument("--owner")
    parser.add_argument("--actor")
    parser.add_argument("--generation", type=int, default=1)
    parser.add_argument("--head")
    parser.add_argument("--expected-revision", type=int)
    parser.add_argument("--evidence")
    parser.add_argument("--mutation-authorized", action="store_true")
    parser.add_argument("--quiesced", action="store_true")
    parser.add_argument("--executor-stopped", action="store_true")
    parser.add_argument("--global-gates-verified", action="store_true")
    parser.add_argument("--command-action", dest="command_action", choices=("replay", "publish"))
    command = []
    command_line = sys.argv[1:]
    if "--" in command_line:
        separator = command_line.index("--")
        command = command_line[separator:]
        command_line = command_line[:separator]
    arguments = parser.parse_args(command_line)
    arguments.command = command
    require(1 <= arguments.generation <= 2147483647, "Invalid generation.")
    store = Store(arguments.worktree)
    if arguments.action == "run":
        arguments.action = arguments.command_action
        require(arguments.action is not None, "--command-action is required for run.")
        function = run_scoped
    else:
        function = {
            "inspect": inspect, "acquire": acquire, "attach": attach_scope,
            "verify-executor": verify_executor, "verify-attached": verify_executor,
            "sync": sync_scope, "complete": complete_scope,
            "resume": resume_owner, "advance": advance, "correction": correction,
            "reprepare": reprepare, "recover": recover, "guard-helper": guard_helper,
        }[arguments.action]
    with exclusive_lock(store.lock_path):
        output = function(arguments, store)
    print(json.dumps(output, ensure_ascii=True, separators=(",", ":")))


if __name__ == "__main__":
    try:
        require(sys.version_info >= (3, 9), "Python 3.9+ is required.")
        main()
    except (ProtocolError, OSError, ValueError, KeyError, TypeError) as error:
        print(f"owner-light: {error}", file=sys.stderr)
        sys.exit(1)
