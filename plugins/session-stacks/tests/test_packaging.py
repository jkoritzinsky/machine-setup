import json
from pathlib import Path
import re
import unittest


PLUGIN_ROOT = Path(__file__).resolve().parent.parent
REPOSITORY_ROOT = PLUGIN_ROOT.parent.parent
SKILL_FILES = {
    "create-session-stack": {
        "SKILL.md", "handoff.md", "provisioning.md", "verification.md",
    },
    "rebase-session-stack": {
        "SKILL.md", "git-protocol.md", "handoffs.md", "operation-state.md",
        "owner-checklist.md", "owner-light.md",
        "scripts/git-handoff.ps1", "scripts/git-handoff.sh", "scripts/owner-light.py",
        "tests/git-handoff.Tests.ps1", "tests/git-handoff.Tests.sh",
        "tests/owner_light_tests.py",
    },
}


class PackagingTests(unittest.TestCase):
    def test_manifest_and_skill_discovery(self):
        manifest = json.loads((PLUGIN_ROOT / "plugin.json").read_text(encoding="utf-8"))
        self.assertEqual(manifest["name"], "session-stacks")
        self.assertRegex(manifest["version"], r"^\d+\.\d+\.\d+$")
        self.assertTrue(manifest["description"].strip())
        self.assertEqual(manifest["skills"], "skills/")
        skills_root = PLUGIN_ROOT / manifest["skills"]
        self.assertEqual({path.name for path in skills_root.iterdir()}, set(SKILL_FILES))
        for name in SKILL_FILES:
            with self.subTest(skill=name):
                text = (skills_root / name / "SKILL.md").read_text(encoding="utf-8")
                header, body = text.split("\n---\n", 1)
                self.assertTrue(header.startswith("---\n"))
                self.assertEqual(re.findall(r"(?m)^name: (\S+)$", header), [name])
                description = re.search(r"(?m)^description: (.+)$", header)
                self.assertIsNotNone(description)
                value = description.group(1)
                if value == ">":
                    folded = header.split("description: >\n", 1)[1].splitlines()
                    self.assertTrue(folded)
                    self.assertTrue(all(line.startswith("  ") for line in folded))
                    self.assertTrue(" ".join(line.strip() for line in folded).strip())
                else:
                    self.assertNotRegex(value, r":\s|\s#")
                    self.assertTrue(value.strip())
                self.assertTrue(body.strip())

    def test_marketplace_registration(self):
        catalog = json.loads(
            (REPOSITORY_ROOT / ".github" / "plugin" / "marketplace.json").read_text(
                encoding="utf-8"))
        self.assertEqual(catalog["name"], "machine-setup")
        names = [entry["name"] for entry in catalog["plugins"]]
        self.assertEqual(names.count("session-stacks"), 1)
        entry = next(entry for entry in catalog["plugins"] if entry["name"] == "session-stacks")
        self.assertEqual(entry["source"], "plugins/session-stacks")
        self.assertEqual((REPOSITORY_ROOT / entry["source"]).resolve(), PLUGIN_ROOT)
        manifest = json.loads((PLUGIN_ROOT / "plugin.json").read_text(encoding="utf-8"))
        self.assertEqual(entry["version"], manifest["version"])
        self.assertTrue(entry["description"].strip())

    def test_installation_surfaces(self):
        readme = (REPOSITORY_ROOT / "README.md").read_text(encoding="utf-8")
        self.assertIn("plugins/session-stacks/README.md", readme)
        command = "plugin install session-stacks@machine-setup"
        self.assertEqual(readme.count(command), 1)
        for name in ("setup-linux.sh", "setup-mac.sh", "setup-windows.ps1"):
            with self.subTest(script=name):
                script = (REPOSITORY_ROOT / name).read_text(encoding="utf-8")
                install = (
                    "'plugin', 'install', 'session-stacks@machine-setup'"
                    if name.endswith(".ps1") else command
                )
                self.assertEqual(script.count(install), 1)
                self.assertLess(
                    script.index("Added marketplace jkoritzinsky/machine-setup"),
                    script.index(install),
                )

    def test_skill_file_inventory(self):
        for name, expected in SKILL_FILES.items():
            with self.subTest(skill=name):
                root = PLUGIN_ROOT / "skills" / name
                actual = {path.relative_to(root).as_posix()
                          for path in root.rglob("*") if path.is_file()}
                self.assertEqual(actual, expected)

    def test_supporting_links_and_helper_locations(self):
        for document in PLUGIN_ROOT.rglob("*.md"):
            text = document.read_text(encoding="utf-8")
            for target in re.findall(r"\[[^\]]+\]\(([^)\s]+)\)", text):
                if "://" in target or target.startswith("#"):
                    continue
                with self.subTest(document=document.name, link=target):
                    path = (document.parent / target.split("#", 1)[0]).resolve()
                    self.assertIn(PLUGIN_ROOT, path.parents)
                    self.assertTrue(path.is_file(), str(path))
        create_root = PLUGIN_ROOT / "skills" / "create-session-stack"
        companion = (create_root / ".." / "rebase-session-stack").resolve()
        for resource in ("owner-checklist.md", "scripts/git-handoff.ps1",
                         "scripts/git-handoff.sh", "scripts/owner-light.py"):
            with self.subTest(resource=resource):
                self.assertTrue((companion / resource).is_file())

    def test_skill_text_hygiene(self):
        for document in PLUGIN_ROOT.rglob("*.md"):
            with self.subTest(document=document.relative_to(PLUGIN_ROOT)):
                text = document.read_bytes().decode("ascii")
                lines = text.splitlines()
                self.assertTrue(all(line == line.rstrip() for line in lines))
                self.assertEqual(sum(line.startswith("```") for line in lines) % 2, 0)
                self.assertNotRegex(text, r"[A-Za-z]:[\\/]|/Users/|/home/|~[\\/]\.copilot")

    def test_lf_attributes_and_sources(self):
        attributes = (PLUGIN_ROOT / ".gitattributes").read_text(encoding="ascii")
        self.assertIn("*.sh text eol=lf\n", attributes)
        self.assertIn("*.py text eol=lf\n", attributes)
        for path in PLUGIN_ROOT.rglob("*"):
            if path.is_file() and path.suffix in (".sh", ".py"):
                with self.subTest(file=path.relative_to(PLUGIN_ROOT)):
                    content = path.read_bytes()
                    self.assertNotIn(b"\r", content)
                    self.assertTrue(content.endswith(b"\n"))

    def test_no_generated_artifacts(self):
        for path in PLUGIN_ROOT.rglob("*"):
            with self.subTest(path=path.relative_to(PLUGIN_ROOT)):
                self.assertNotIn(path.name, {"__pycache__", ".git", "manifest.json"})
                self.assertNotIn(path.suffix, {".pyc", ".pyo", ".log"})
                self.assertFalse(path.name.startswith(
                    ("owner-light-fixture-", "git-handoff-fixture-", "git-handoff-sh-fixture.")))


if __name__ == "__main__":
    unittest.main(verbosity=2)
