# Session stacks

Copilot skills for setting up and maintaining session-owned layers of an existing
PR stack. Install from this repository's marketplace:

```text
copilot plugin marketplace add jkoritzinsky/machine-setup
copilot plugin install session-stacks@machine-setup
```

## Skills and authority

| Skill | Purpose |
| --- | --- |
| [create-session-stack](skills/create-session-stack/SKILL.md) | Bootstrap a fresh coordinator or spin out an implementation session into separate owners for every selected layer, including the top. |
| [rebase-session-stack](skills/rebase-session-stack/SKILL.md) | Coordinate checkout-sync, descendant-replay, or trunk-rebase for existing owners, with separately authorized feedback and publication. |

Only an explicit **session stack / separate layer sessions** request authorizes
session creation. A PR-stack, rebase, review, or skill-authoring request alone does
not. Setup preserves the original PRs, pins project/repository/runtime identity,
and transfers indexed layer context; it acquires no standing lease and grants no
rebase, push, or publication authority.

Owner-driven coordination is the fallback. Optional owner-light coordination
requires cooperative same-host/runtime owners, accessible local durable records,
and one executor. It works with shared or separate clones, but is not an
interceptor of arbitrary Git, editor, or automation actions. Windows and WSL are
different execution environments. Owners receive only their
[short checklist](skills/rebase-session-stack/owner-checklist.md), scoped request,
and indexed packet, not the full coordinator protocol.

## Resources and prerequisites

The plugin manifest discovers both `skills/<name>/SKILL.md` files. Each skill's
supporting Markdown remains beside that file; resolve its relative links from the
installed skill directory, not a personal skill-installation path.

The shared [PowerShell](skills/rebase-session-stack/scripts/git-handoff.ps1),
[Bash](skills/rebase-session-stack/scripts/git-handoff.sh), and
[owner-light Python](skills/rebase-session-stack/scripts/owner-light.py) helpers
are in `skills/rebase-session-stack/scripts/`. For `create-session-stack`, these
and the owner checklist are sibling resources under `../rebase-session-stack/`.
Use verified accessible paths in owner packets. Helpers do not themselves grant
checkout, replay, or publication authority.

- Git and authenticated `gh` are required for Git/GitHub work; published identity
  verification uses authenticated `gh`, not cached PR metadata.
- The setup skill needs the Copilot app's session/project tools and verified
  same-project local worktree provisioning. CLI-only availability of a skill is
  not evidence that these app capabilities exist.
- The guarded helpers need PowerShell 7 or Bash 3.2+ with standard Unix utilities.
  Use the appropriate native shell; shell handoff without owner-light metadata
  does not require Python.
- Owner-light requires Python 3.9+ and no third-party packages. The Bash fixtures
  also require Python 3 for JSON assertions.
- Load `gh-stack` separately when that tool is requested; these skills do not
  install it or substitute Git silently for an explicitly requested workflow.

## Local checks

From the repository root, run the packaging checks without installing the plugin:

```powershell
python -B -m unittest discover -s .\plugins\session-stacks\tests -p test_packaging.py -v
copilot --plugin-dir .\plugins\session-stacks plugin list --json
```

The packaging suite checks the manifest/catalog, installation surfaces, skill
inventory/frontmatter, supporting links, text hygiene, LF policy, and absence of
generated artifacts. It uses only Python's standard library.

Run the copied fixtures with an **existing scratch directory outside product
source**, such as this session's artifacts directory. Each suite allocates and
cleans up its own uniquely named disposable repositories:

```powershell
python -B .\plugins\session-stacks\skills\rebase-session-stack\tests\owner_light_tests.py --scratch-root "<existing-session-artifacts-directory>"
pwsh -NoProfile -File .\plugins\session-stacks\skills\rebase-session-stack\tests\git-handoff.Tests.ps1 -ScratchRoot "<existing-session-artifacts-directory>"
```

On a Unix host, from the repository root:

```bash
python3 -B -m unittest discover -s plugins/session-stacks/tests -p test_packaging.py -v
python3 -B plugins/session-stacks/skills/rebase-session-stack/tests/owner_light_tests.py --scratch-root "<existing-session-artifacts-directory>"
bash plugins/session-stacks/skills/rebase-session-stack/tests/git-handoff.Tests.sh "<existing-session-artifacts-directory>"
```

Fixtures test local Git and native OS locks; PR API responses are mocked and no
live publication occurs. Git Bash results on Windows do not validate native Unix
locking. Run Linux validation on a directly hosted Linux/WSL agent, not by invoking
`wsl.exe` from a Windows session.

The setup skill's [acceptance scenarios](skills/create-session-stack/verification.md)
are workflow checks, not a live app provisioning test. Packaging or fixture
validation does not authorize creating sessions or operating on a real stack.
