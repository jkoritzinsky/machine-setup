import argparse
import contextlib
import importlib.util
import json
import os
from pathlib import Path
import subprocess
import signal
import shutil
import sys
import tempfile
import types
import time
import unittest
from unittest import mock
import uuid


SPEC = importlib.util.spec_from_file_location(
    "owner_light", Path(__file__).resolve().parent.parent / "scripts" / "owner-light.py")
protocol = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(protocol)


class LeaseTests(unittest.TestCase):
    scratch = None

    def setUp(self):
        self.temporary = tempfile.TemporaryDirectory(prefix="owner-light-fixture-", dir=self.scratch)
        self.root = Path(self.temporary.name)
        self.source = self.root / "source repo"
        self.receiver = self.root / "owner repo"
        self.source.mkdir()
        self.g(self.source, "init", "--quiet", "--initial-branch=main")
        self.g(self.source, "config", "user.name", "Fixture")
        self.g(self.source, "config", "user.email", "fixture@example.invalid")
        self.g(self.source, "config", "commit.gpgsign", "false")
        (self.source / "sample.txt").write_text("base\n", encoding="utf-8")
        self.g(self.source, "add", "--", "sample.txt")
        self.g(self.source, "commit", "--quiet", "-m", "Fixture base")
        self.old = self.g(self.source, "rev-parse", "HEAD")
        self.g(self.source, "branch", "owned", self.old)
        (self.source / "sample.txt").write_text("candidate\n", encoding="utf-8")
        self.g(self.source, "add", "--", "sample.txt")
        self.g(self.source, "commit", "--quiet", "-m", "Fixture candidate")
        self.target = self.g(self.source, "rev-parse", "HEAD")
        self.g(self.source, "branch", "target", self.target)
        self.g(self.root, "clone", "--quiet", "--no-hardlinks", str(self.source), str(self.receiver))
        self.g(self.receiver, "branch", "owned", "refs/remotes/origin/owned")
        self.g(self.receiver, "branch", "unrelated", self.target)
        self.g(self.receiver, "switch", "--quiet", "--detach", self.old)
        self.store = protocol.Store(str(self.receiver))
        self.token = uuid.uuid4().hex
        self.request = {
            "operation": "fixture", "leaseId": self.token, "executor": "coordinator",
            "owner": "owner", "branch": "refs/heads/owned", "preparedHead": self.old,
            "completion": "local-only", "actions": ["attach", "replay"],
            "source": "origin", "sourceRef": "refs/heads/target",
        }
        self.request_path = self.write("request.json", self.request)
        self.plan_path = self.write("plan.json", {
            "expectedHead": self.old, "expectedOld": self.old, "target": self.target, "parent": self.old,
        })

    def tearDown(self):
        self.temporary.cleanup()

    def g(self, directory, *arguments):
        result = subprocess.run(
            ["git", "-C", str(directory), "-c", "core.longpaths=true", "-c", "core.autocrlf=false",
             "-c", f"core.hooksPath={self.root / 'no-hooks'}", *arguments],
            stdout=subprocess.PIPE, stderr=subprocess.PIPE, encoding="utf-8",
        )
        self.assertEqual(result.returncode, 0, result.stderr + result.stdout)
        return result.stdout.strip()

    def write(self, name, value):
        path = self.root / name
        path.write_text(json.dumps(value), encoding="utf-8")
        return str(path)

    def args(self, **changes):
        value = dict(
            worktree=str(self.receiver), request=self.request_path, plan=self.plan_path,
            lease_id=self.token, actor="coordinator", owner="owner", generation=1,
            mutation_authorized=True, quiesced=True, executor_stopped=False,
            head=self.target, expected_revision=None, evidence="fixture operation-wide gates", command=[],
            global_gates_verified=True,
        )
        value.update(changes)
        return types.SimpleNamespace(**value)

    def call(self, function, store=None, **changes):
        store = store or self.store
        with protocol.exclusive_lock(store.lock_path):
            return function(self.args(**changes), store)

    def acquire(self):
        self.request_path = self.write("request.json", self.request)
        return self.call(protocol.acquire)

    def attach(self):
        return self.call(protocol.attach_scope)

    def local_complete(self):
        self.acquire()
        self.attach()
        return self.call(protocol.complete_scope)

    def publication_request(self):
        self.request.update(
            completion="published", actions=["attach", "sync", "replay"],
            remote="origin", repository="fixture/repo", pr=1, prBase="main",
        )

    @contextlib.contextmanager
    def fake_pr(self, **changes):
        real_run = subprocess.run
        pr = {"state": "open", "head": {"sha": self.target, "ref": "owned"}, "base": {"ref": "main"}}
        pr.update(changes)

        def run(command, **kwargs):
            if command[0] == "gh":
                return subprocess.CompletedProcess(command, 0, json.dumps(pr), "")
            return real_run(command, **kwargs)

        with mock.patch.object(protocol.subprocess, "run", side_effect=run):
            yield

    def test_scoped_acquire_idempotent_and_full_receipt(self):
        result = self.acquire()
        self.assertEqual(result["phase"], "PREPARED_DETACHED")
        self.assertTrue(Path(result["receipt"]).is_file())
        self.assertTrue(self.acquire()["alreadyAcquired"])
        stored = self.store.load()
        self.assertEqual(stored["environment"], protocol.environment())
        self.assertEqual(stored["scopes"][protocol.canonical(self.receiver)]["last"]["head"], self.old)

    def test_read_only_inspect_does_not_grant_authority(self):
        self.assertEqual(self.call(protocol.inspect)["phase"], "NO_LEASE")
        self.assertFalse(self.store.path.exists())

    def test_acquire_requires_actual_detachment_and_exact_owner(self):
        self.g(self.receiver, "switch", "--quiet", "owned")
        with self.assertRaisesRegex(protocol.ProtocolError, "detached"):
            self.acquire()
        self.g(self.receiver, "switch", "--quiet", "--detach", self.old)
        with self.assertRaisesRegex(protocol.ProtocolError, "named owner"):
            self.call(protocol.acquire, owner="another-owner")

    def test_missing_attestations_refused(self):
        with self.assertRaisesRegex(protocol.ProtocolError, "acknowledge"):
            self.call(protocol.acquire, quiesced=False)

    def test_conflicting_operation_and_broadened_scope_refused(self):
        self.acquire()
        request = dict(self.request, leaseId=uuid.uuid4().hex)
        with self.assertRaisesRegex(protocol.ProtocolError, "Another operation"):
            self.call(protocol.acquire, request=self.write("conflict.json", request))
        request = dict(self.request, actions=["attach", "replay", "publish"], publicationAuthorized=True)
        with self.assertRaisesRegex(protocol.ProtocolError, "Scope changed"):
            self.call(protocol.acquire, request=self.write("broadened.json", request))

    def test_dirty_owner_and_active_git_operation_refused(self):
        (self.receiver / "untracked.txt").write_text("preserve", encoding="utf-8")
        with self.assertRaisesRegex(protocol.ProtocolError, "dirty"):
            self.acquire()
        self.assertEqual((self.receiver / "untracked.txt").read_text(encoding="utf-8"), "preserve")
        (self.receiver / "untracked.txt").unlink()
        marker = self.receiver / ".git" / "MERGE_HEAD"
        marker.write_text(self.old, encoding="utf-8")
        with self.assertRaisesRegex(protocol.ProtocolError, "Unfinished"):
            self.acquire()

    def test_wrong_actor_token_and_generation_refused(self):
        self.acquire()
        for changes, pattern in (
            ({"actor": "owner"}, "designated executor"),
            ({"lease_id": uuid.uuid4().hex}, "token"),
            ({"generation": 2}, "generation"),
        ):
            with self.assertRaisesRegex(protocol.ProtocolError, pattern):
                self.call(protocol.attach_scope, **changes)

    def test_ref_drift_cannot_be_hidden_by_plan(self):
        self.acquire()
        wrong = {"expectedHead": self.old, "expectedOld": self.target, "target": self.target, "parent": self.old}
        with self.assertRaisesRegex(protocol.ProtocolError, "durable checkpoint"):
            self.call(protocol.attach_scope, plan=self.write("wrong-plan.json", wrong))

    def test_attach_receipt_and_idempotent_retry(self):
        self.acquire()
        result = self.attach()
        self.assertEqual(result["phase"], "ATTACHED_FROZEN")
        receipt = protocol.read_json(result["receipt"])
        self.assertEqual(receipt["evidence"]["snapshot"]["head"], self.target)
        self.assertEqual(self.g(self.receiver, "rev-parse", receipt["evidence"]["backupRef"]), self.old)
        current_plan = {"expectedHead": self.target, "expectedOld": self.target,
                        "target": self.target, "parent": self.old}
        self.assertTrue(self.call(protocol.attach_scope, plan=self.write("retry.json", current_plan))["alreadyAttached"])

    def test_detached_shared_target_needs_no_transfer(self):
        self.acquire()
        self.g(self.receiver, "update-ref", "--no-deref", "refs/heads/owned", self.target, self.old)
        result = self.attach()
        evidence = protocol.read_json(result["receipt"])["evidence"]
        self.assertIsNone(evidence["backupRef"])
        self.assertIsNone(evidence["transferRef"])

    def test_remote_url_drift_refused_before_owner_ref_write(self):
        self.acquire()
        self.g(self.receiver, "remote", "set-url", "origin", str(self.root / "other"))
        with self.assertRaisesRegex(protocol.ProtocolError, "remote URL changed"):
            self.attach()
        self.assertEqual(self.g(self.receiver, "rev-parse", "refs/heads/owned"), self.old)

    def test_wrong_transfer_leaves_durable_interruption_and_backup(self):
        self.request["sourceRef"] = "refs/heads/owned"
        self.acquire()
        with self.assertRaisesRegex(protocol.ProtocolError, "Transferred"):
            self.attach()
        value = self.store.load()
        self.assertEqual(value["pending"]["action"], "attach")
        self.assertTrue(value["pending"]["backupRef"])
        self.assertEqual(self.g(self.receiver, "rev-parse", "refs/heads/owned"), self.old)
        with self.assertRaisesRegex(protocol.ProtocolError, "interrupted"):
            self.attach()

    def test_invalid_parent_is_rejected_before_branch_update(self):
        self.acquire()
        # An unrelated root commit provides a real object without the claimed ancestry.
        result = subprocess.run(
            ["git", "-C", str(self.source), "-c", "user.name=Fixture", "-c",
             "user.email=fixture@example.invalid", "commit-tree", self.g(self.source, "rev-parse", "HEAD^{tree}")],
            input="Unrelated root\n", stdout=subprocess.PIPE, stderr=subprocess.PIPE, encoding="utf-8",
        )
        self.assertEqual(result.returncode, 0, result.stderr)
        other = result.stdout.strip()
        self.g(self.source, "update-ref", "refs/heads/unrelated-root", other)
        self.g(self.receiver, "fetch", "--quiet", "origin", "refs/heads/unrelated-root")
        plan = {"expectedHead": self.old, "expectedOld": self.old, "target": self.target, "parent": other}
        with self.assertRaisesRegex(protocol.ProtocolError, "not an ancestor"):
            self.call(protocol.attach_scope, plan=self.write("bad-parent.json", plan))
        self.assertEqual(self.g(self.receiver, "rev-parse", "refs/heads/owned"), self.old)

    def test_owner_cannot_resume_on_timeout_or_before_matching_release(self):
        self.acquire()
        with self.assertRaisesRegex(protocol.ProtocolError, "terminal record"):
            self.call(protocol.resume_owner)
        self.attach()
        with self.assertRaisesRegex(protocol.ProtocolError, "remains frozen"):
            self.call(protocol.resume_owner)
        self.call(protocol.complete_scope)
        self.assertEqual(self.call(protocol.resume_owner)["phase"], "RESUMED")
        self.assertTrue(self.call(protocol.resume_owner)["alreadyResumed"])

    def test_release_requires_matching_generation_and_head(self):
        self.acquire()
        self.call(protocol.advance, generation=2)
        self.call(protocol.attach_scope, generation=2)
        self.call(protocol.complete_scope, generation=2)
        for changes in ({"generation": 1}, {"generation": 2, "head": self.old}):
            with self.assertRaisesRegex(protocol.ProtocolError, "generation/head"):
                self.call(protocol.resume_owner, **changes)
        self.assertEqual(self.call(protocol.resume_owner, generation=2)["phase"], "RESUMED")

    def test_new_operation_rejects_old_release_notice(self):
        self.local_complete()
        self.g(self.receiver, "switch", "--quiet", "--detach", self.target)
        new_request = dict(self.request, leaseId=uuid.uuid4().hex, preparedHead=self.target)
        self.call(protocol.acquire, request=self.write("new-request.json", new_request))
        with self.assertRaisesRegex(protocol.ProtocolError, "Stale"):
            self.call(protocol.resume_owner)
        self.assertTrue((self.store.directory / "history" / f"{self.token}.json").is_file())

    def test_released_operation_token_cannot_be_reused(self):
        self.local_complete()
        self.g(self.receiver, "switch", "--quiet", "--detach", self.target)
        reused = dict(self.request, preparedHead=self.target)
        with self.assertRaisesRegex(protocol.ProtocolError, "cannot be reused"):
            self.call(protocol.acquire, request=self.write("reused.json", reused))

    def test_completion_requires_operation_wide_gate_attestation(self):
        self.acquire()
        self.attach()
        with self.assertRaisesRegex(protocol.ProtocolError, "operation-wide gate"):
            self.call(protocol.complete_scope, global_gates_verified=False)
        self.assertEqual(self.store.load()["scopes"][protocol.canonical(self.receiver)]["phase"], "attached")

    def test_legacy_helper_guard_refuses_active_clone_lease(self):
        self.acquire()
        with self.assertRaisesRegex(protocol.ProtocolError, "Active owner-light"):
            self.call(protocol.guard_helper)
        self.attach()
        self.call(protocol.complete_scope)
        self.assertEqual(self.call(protocol.guard_helper)["phase"], "OWNER_DRIVEN_ALLOWED")

    def test_shell_and_powershell_helpers_cannot_bypass_active_lease(self):
        self.acquire()
        scripts = Path(SPEC.origin).parent
        commands = []
        bash = shutil.which("bash")
        pwsh = shutil.which("pwsh")
        if bash:
            commands.append([
                bash, str(scripts / "git-handoff.sh"), "--mode", "attach",
                "--worktree", str(self.receiver), "--branch", "refs/heads/owned",
                "--expected-head", self.old, "--expected-old", self.old, "--target", self.target,
                "--operation", "fixture", "--generation", "1", "--mutation-authorized", "--quiesced",
            ])
        if pwsh:
            commands.append([
                pwsh, "-NoProfile", "-NonInteractive", "-File", str(scripts / "git-handoff.ps1"),
                "-Mode", "Attach", "-Worktree", str(self.receiver), "-Branch", "refs/heads/owned",
                "-ExpectedHead", self.old, "-ExpectedOld", self.old, "-Target", self.target,
                "-Operation", "fixture", "-Generation", "1", "-MutationAuthorized", "-Quiesced",
            ])
        if not commands:
            self.skipTest("Neither companion shell is available.")
        for command in commands:
            with self.subTest(shell=command[0]):
                result = subprocess.run(command, stdout=subprocess.PIPE, stderr=subprocess.PIPE, encoding="utf-8")
                self.assertNotEqual(result.returncode, 0)
                self.assertIn("owner-light lease", result.stderr + result.stdout)
                self.assertEqual(self.g(self.receiver, "rev-parse", "refs/heads/owned"), self.old)

    def test_same_host_separate_clones_have_independent_locks(self):
        self.acquire()
        second = protocol.Store(str(self.source))
        self.assertNotEqual(second.common, self.store.common)
        with protocol.exclusive_lock(self.store.lock_path):
            with protocol.exclusive_lock(second.lock_path):
                self.assertTrue(second.lock_path.exists())

    def test_shared_clone_mutual_exclusion_is_cross_process(self):
        self.acquire()
        with protocol.exclusive_lock(self.store.lock_path):
            result = subprocess.run(
                [sys.executable, str(SPEC.origin), "inspect", "--worktree", str(self.receiver)],
                stdout=subprocess.PIPE, stderr=subprocess.PIPE, encoding="utf-8",
            )
        self.assertNotEqual(result.returncode, 0)
        self.assertIn("Another participating writer", result.stderr)
        self.assertFalse(result.stdout)

    def test_cli_parses_operation_flags_and_emits_compact_receipt(self):
        result = subprocess.run(
            [sys.executable, str(SPEC.origin), "acquire", "--worktree", str(self.receiver),
             "--request", self.request_path, "--owner", "owner", "--generation", "1",
             "--mutation-authorized", "--quiesced"],
            stdout=subprocess.PIPE, stderr=subprocess.PIPE, encoding="utf-8",
        )
        self.assertEqual(result.returncode, 0, result.stderr)
        receipt = json.loads(result.stdout)
        self.assertEqual(receipt["leaseId"], self.token)
        self.assertEqual(receipt["phase"], "PREPARED_DETACHED")
        self.assertLess(len(result.stdout), 1500)

    def test_shared_clone_release_waits_for_all_participants(self):
        self.acquire()
        second = self.root / "second owner"
        self.g(self.receiver, "branch", "second-owned", self.old)
        self.g(self.receiver, "worktree", "add", "--quiet", "--detach", str(second), self.old)
        second_store = protocol.Store(str(second))
        request = dict(self.request, owner="second-owner", branch="refs/heads/second-owned")
        self.call(protocol.acquire, store=second_store, owner="second-owner",
                  request=self.write("second.json", request))
        self.assertEqual(second_store.common, self.store.common)
        self.attach()
        self.call(protocol.complete_scope)
        with self.assertRaisesRegex(protocol.ProtocolError, "Other scopes"):
            self.call(protocol.resume_owner)
        self.call(protocol.attach_scope, store=second_store)
        self.call(protocol.complete_scope, store=second_store)
        self.assertEqual(self.call(protocol.resume_owner)["phase"], "RESUMED")
        self.assertEqual(self.call(protocol.resume_owner, store=second_store, owner="second-owner")["phase"], "RESUMED")

    def test_generation_advances_without_owner_messages_and_rejects_old_receipts(self):
        self.acquire()
        self.call(protocol.advance, generation=2)
        with self.assertRaisesRegex(protocol.ProtocolError, "generation"):
            self.attach()
        self.assertEqual(self.call(protocol.attach_scope, generation=2)["phase"], "ATTACHED_FROZEN")

    def test_correction_is_owner_scoped_and_requires_new_preparation(self):
        self.acquire()
        self.call(protocol.correction, evidence="fixture correction")
        with self.assertRaisesRegex(protocol.ProtocolError, "active executor scope"):
            self.attach()
        self.g(self.receiver, "update-ref", "--no-deref", "refs/heads/owned", self.target, self.old)
        self.g(self.receiver, "switch", "--quiet", "--detach", self.target)
        with self.assertRaisesRegex(protocol.ProtocolError, "owner"):
            self.call(protocol.reprepare, owner="other", head=self.target, generation=2)
        self.assertEqual(self.call(protocol.reprepare, head=self.target, generation=2)["head"], self.target)

    def test_command_journal_failure_never_automatically_releases(self):
        self.acquire()
        with self.assertRaisesRegex(protocol.ProtocolError, "remains interrupted"):
            self.call(protocol.run_scoped, action="replay",
                      command=["--", sys.executable, "-c", "import sys; sys.exit(7)"])
        value = self.store.load()
        self.assertEqual(value["pending"]["action"], "replay")
        self.assertTrue(Path(value["pending"]["log"]).is_file())
        with self.assertRaisesRegex(protocol.ProtocolError, "interrupted"):
            self.attach()

    def test_executor_process_death_releases_os_lock_but_not_durable_lease(self):
        self.acquire()
        command = ["--", sys.executable, "-c",
                   "import pathlib,time; pathlib.Path('child-started').write_text('started'); time.sleep(60)"]
        # The child's working directory is the leased owner root, not the fixture parent.
        marker = self.receiver / "child-started"
        parent = subprocess.Popen(
            [sys.executable, str(SPEC.origin), "run", "--worktree", str(self.receiver),
             "--lease-id", self.token, "--actor", "coordinator", "--generation", "1",
             "--command-action", "replay", *command],
            stdout=subprocess.PIPE, stderr=subprocess.PIPE,
        )
        child_pid = None
        try:
            deadline = time.monotonic() + 20
            while not marker.exists() and time.monotonic() < deadline:
                if parent.poll() is not None:
                    output = parent.communicate()
                    self.fail(f"Wrapper exited prematurely: {output}")
                time.sleep(0.05)
            self.assertTrue(marker.exists(), "Test child did not start.")
            value = protocol.read_json(self.store.path)
            child_pid = value["pending"]["childPid"]
            parent.terminate()
            parent.communicate(timeout=10)
            with protocol.exclusive_lock(self.store.lock_path):
                self.assertIsNotNone(self.store.load()["pending"])
            with self.assertRaisesRegex(protocol.ProtocolError, "interrupted"):
                self.attach()
        finally:
            if parent.poll() is None:
                parent.terminate()
                parent.communicate(timeout=10)
            if child_pid is not None:
                if os.name == "nt":
                    import ctypes
                    from ctypes import wintypes
                    kernel = ctypes.WinDLL("kernel32", use_last_error=True)
                    kernel.OpenProcess.argtypes = [wintypes.DWORD, wintypes.BOOL, wintypes.DWORD]
                    kernel.OpenProcess.restype = wintypes.HANDLE
                    kernel.TerminateProcess.argtypes = [wintypes.HANDLE, wintypes.UINT]
                    kernel.WaitForSingleObject.argtypes = [wintypes.HANDLE, wintypes.DWORD]
                    kernel.CloseHandle.argtypes = [wintypes.HANDLE]
                    handle = kernel.OpenProcess(0x00100001, False, child_pid)
                    self.assertTrue(handle, "Could not open the known fixture child.")
                    try:
                        self.assertTrue(kernel.TerminateProcess(handle, 1))
                        self.assertEqual(kernel.WaitForSingleObject(handle, 10000), 0)
                    finally:
                        kernel.CloseHandle(handle)
                else:
                    os.kill(child_pid, signal.SIGTERM)
            if marker.exists():
                marker.unlink()

    def test_recovery_requires_stopped_evidence_exact_revision_and_complete_checkpoints(self):
        self.acquire()
        with self.assertRaises(protocol.ProtocolError):
            self.call(protocol.run_scoped, action="replay",
                      command=["--", sys.executable, "-c", "import sys; sys.exit(3)"])
        value = self.store.load()
        checkpoint = protocol.snapshot(str(self.receiver), "refs/heads/owned")
        plan = self.write("recover.json", {"checkpoints": {protocol.canonical(self.receiver): checkpoint}})
        with self.assertRaisesRegex(protocol.ProtocolError, "stopped evidence"):
            self.call(protocol.recover, plan=plan, expected_revision=value["revision"])
        with self.assertRaisesRegex(protocol.ProtocolError, "Stale recovery"):
            self.call(protocol.recover, plan=plan, expected_revision=value["revision"] - 1,
                      executor_stopped=True, evidence="fixture child exited")
        result = self.call(protocol.recover, plan=plan, expected_revision=value["revision"],
                           executor_stopped=True, evidence="fixture child exited")
        self.assertEqual(result["phase"], "RECONCILED")
        self.assertIsNone(self.store.load()["pending"])
        self.assertEqual(self.attach()["phase"], "ATTACHED_FROZEN")

    def test_recovered_post_checkout_crash_uses_verification_without_rewriting(self):
        self.acquire()
        with protocol.exclusive_lock(self.store.lock_path):
            value = self.store.load()
            self.store.begin(value, "attach", protocol.read_json(self.plan_path))
        self.g(self.receiver, "update-ref", "refs/heads/owned", self.target, self.old)
        self.g(self.receiver, "switch", "--quiet", "owned")
        current = protocol.snapshot(str(self.receiver), "refs/heads/owned")
        plan = self.write("recover-attached.json", {"checkpoints": {protocol.canonical(self.receiver): current}})
        self.call(protocol.recover, plan=plan, expected_revision=self.store.load()["revision"],
                  executor_stopped=True, evidence="fixture executor stopped after checkout")
        final_plan = self.write("verified-attached.json", {"target": self.target, "parent": self.old})
        self.assertEqual(self.call(protocol.verify_executor, plan=final_plan)["phase"], "ATTACHED_FROZEN")
        self.assertEqual(self.call(protocol.complete_scope)["phase"], "RELEASED")

    def test_host_or_runtime_change_blocks_mutation(self):
        self.acquire()
        value = self.store.load()
        value["environment"]["platform"] = "different-runtime"
        protocol.atomic_json(self.store.path, value)
        with self.assertRaisesRegex(protocol.ProtocolError, "host changed"):
            self.attach()

    def test_owner_executor_uses_existing_registered_checkout_receipt(self):
        self.request["owner"] = "coordinator"
        self.request_path = self.write("request.json", self.request)
        self.call(protocol.acquire, owner="coordinator")
        self.call(protocol.run_scoped, action="replay",
                  command=["--", "git", "-c", "core.longpaths=true", "switch", "--quiet", "owned"])
        plan = self.write("executor-plan.json", {"target": self.old, "parent": self.old})
        result = self.call(protocol.verify_executor, plan=plan)
        self.assertEqual(result["phase"], "ATTACHED_FROZEN")
        self.assertEqual(self.g(self.receiver, "symbolic-ref", "HEAD"), "refs/heads/owned")

    def test_publication_is_not_granted_by_handoff(self):
        self.request.update(actions=["attach", "publish"])
        with self.assertRaisesRegex(protocol.ProtocolError, "authorization"):
            self.acquire()

    def test_tracking_sync_and_live_pr_release_keep_other_refs_untouched(self):
        self.publication_request()
        self.acquire()
        self.attach()
        self.g(self.source, "update-ref", "refs/heads/owned", self.target, self.old)
        self.g(self.receiver, "config", "fetch.prune", "true")
        self.g(self.receiver, "config", "fetch.pruneTags", "true")
        self.g(self.receiver, "config", "fetch.writeCommitGraph", "true")
        self.g(self.receiver, "tag", "local-only", self.old)
        self.g(self.source, "tag", "remote-only", self.target)
        fetch = self.receiver / ".git" / "FETCH_HEAD"
        fetch.write_text("unchanged\n", encoding="utf-8")
        with self.fake_pr():
            self.assertEqual(self.call(protocol.sync_scope)["phase"], "TRACKING_SYNCED")
            self.assertEqual(self.call(protocol.complete_scope)["phase"], "RELEASED")
        self.assertEqual(fetch.read_text(encoding="utf-8"), "unchanged\n")
        self.assertEqual(self.g(self.receiver, "rev-parse", "refs/heads/unrelated"), self.target)
        self.assertEqual(self.g(self.receiver, "rev-parse", "refs/tags/local-only"), self.old)
        self.assertEqual(self.g(self.receiver, "tag", "--list", "remote-only"), "")
        self.assertEqual(self.g(self.receiver, "rev-parse", "refs/remotes/origin/owned"), self.target)
        self.assertFalse((self.receiver / ".git" / "objects" / "info" / "commit-graph").exists())

    def test_tracking_release_rejects_remote_or_pr_drift(self):
        self.publication_request()
        self.acquire()
        self.attach()
        with self.assertRaisesRegex(protocol.ProtocolError, "Published branch"):
            self.call(protocol.sync_scope)
        self.g(self.source, "update-ref", "refs/heads/owned", self.target, self.old)
        with self.fake_pr(state="closed"):
            with self.assertRaisesRegex(protocol.ProtocolError, "PR head/base/state"):
                self.call(protocol.sync_scope)
        with self.assertRaisesRegex(protocol.ProtocolError, "Tracking sync"):
            self.call(protocol.complete_scope)

    def test_symbolic_tracking_alias_cannot_update_a_sibling(self):
        self.publication_request()
        self.acquire()
        self.attach()
        self.g(self.receiver, "symbolic-ref", "refs/remotes/origin/owned", "refs/heads/unrelated")
        with self.assertRaisesRegex(protocol.ProtocolError, "tracking ref must be direct"):
            self.call(protocol.sync_scope)
        self.assertEqual(self.g(self.receiver, "rev-parse", "refs/heads/unrelated"), self.target)


if __name__ == "__main__":
    parser = argparse.ArgumentParser()
    parser.add_argument("--scratch-root", required=True)
    arguments = parser.parse_args()
    LeaseTests.scratch = str(Path(arguments.scratch_root).resolve(strict=True))
    unittest.main(argv=[sys.argv[0]], verbosity=2)
