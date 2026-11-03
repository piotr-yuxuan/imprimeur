# SPDX-License-Identifier: EUPL-1.2 OR GPL-3.0-or-later
"""Tests of scripts/release.py, from the requirements of plan 030.

The release runs as CD runs it, in a checkout of a local bare `origin`, with tests/bin/fake-gh
as `gh`, which records each call and acts on that `origin` as GitHub does.  Each test makes
its own repositories in a scratch home, with the identity tests@example.invalid.
"""

import base64
import importlib.util
import json
import os
import subprocess
import tempfile
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
SCRIPT = ROOT / "scripts" / "release.py"
FAKE_GH = ROOT / "tests" / "bin" / "fake-gh"
HEADER = ";; Version: 0.0.0\n"
MAIN_FILES = (
    "sommaire/sommaire.el",
    "imprimeur/imprimeur.el",
    "imprimeur-skin-xix/imprimeur-skin-xix.el",
    "imprimeur-skin-briefing/imprimeur-skin-briefing.el",
)
TREE = {
    **{path: f";;; {path} --- Écrit\n{HEADER};;; Code:\n" for path in MAIN_FILES},
    "imprimeur/imprimeur-sync.el": ";;; Not a main file, with no header.\n",
    "docs/page.md": "A page.\n",
}

spec = importlib.util.spec_from_file_location("release", SCRIPT)
release = importlib.util.module_from_spec(spec)
spec.loader.exec_module(release)


class NextVersion(unittest.TestCase):
    def test_table(self):
        for text, bump, expected in (
            (None, "patch", "0.0.0"),
            (None, "minor", "0.0.0"),
            (None, "major", "0.0.0"),
            ("0.0.0\n", "patch", "0.0.1"),
            ("1.2.3\n", "patch", "1.2.4"),
            ("1.2.3\n", "minor", "1.3.0"),
            ("1.2.3\n", "major", "2.0.0"),
            ("9.9.9\n", "patch", "9.9.10"),
        ):
            with self.subTest(text=text, bump=bump):
                self.assertEqual(release.next_version(text, ["0.0.0-other"], bump), expected)

    def test_refuses_what_is_not_a_version(self):
        for text in ("", "1.2\n", "1.2.3", "01.2.3\n", "v1.2.3\n", "1.2.3\n\n", "1.2.3-rc\n", "١.2.3\n"):
            with self.subTest(text=text), self.assertRaises(release.ReleaseError):
                release.next_version(text, [], "patch")

    def test_never_gives_a_version_with_a_tag(self):
        with self.assertRaises(release.ReleaseError):
            release.next_version("1.2.3\n", ["1.2.4"], "patch")
        with self.assertRaises(release.ReleaseError):
            release.next_version(None, ["0.0.0"], "patch")


class Notes(unittest.TestCase):
    def test_a_first_release_links_nothing(self):
        self.assertNotIn("http", release.release_notes([], None))

    def test_a_later_release_has_a_table_and_a_link(self):
        link = "https://example.invalid/compare/1.0.0...1.0.1"
        notes = release.release_notes([("A", "a.el"), ("M", "b|c.md"), ("D", "d.el")], link)
        self.assertIn("| Added | `a.el` |", notes)
        self.assertIn("| Changed | `b\\|c.md` |", notes)
        self.assertIn("| Removed | `d.el` |", notes)
        self.assertIn(link, notes)

    def test_nothing_changed_still_links(self):
        link = "https://example.invalid/compare/1.0.0...1.1.0"
        self.assertIn(link, release.release_notes([], link))


class Bounds(unittest.TestCase):
    def test_a_call_that_lasts_too_long_stops(self):
        before = release.COMMAND_TIMEOUT_SECONDS
        release.COMMAND_TIMEOUT_SECONDS = 0.05
        self.addCleanup(setattr, release, "COMMAND_TIMEOUT_SECONDS", before)
        with self.assertRaises(subprocess.TimeoutExpired):
            release.run("sleep", "5")


class Pipeline(unittest.TestCase):
    """A repository, its `origin`, and runs of the release against them."""

    def setUp(self):
        scratch = tempfile.TemporaryDirectory(prefix="release-test.")
        self.addCleanup(scratch.cleanup)
        self.scratch = Path(scratch.name)
        (self.scratch / "home").mkdir()
        (self.scratch / "bin").mkdir()
        (self.scratch / "gh").mkdir()
        (self.scratch / "bin" / "gh").symlink_to(FAKE_GH)
        self.origin = self.scratch / "origin.git"
        self.environment = {
            "PATH": f"{self.scratch / 'bin'}{os.pathsep}{os.environ['PATH']}",
            "HOME": str(self.scratch / "home"),
            "GIT_CONFIG_GLOBAL": os.devnull,
            "GIT_CONFIG_NOSYSTEM": "1",
            "GIT_AUTHOR_NAME": "tests",
            "GIT_AUTHOR_EMAIL": "tests@example.invalid",
            "GIT_COMMITTER_NAME": "tests",
            "GIT_COMMITTER_EMAIL": "tests@example.invalid",
            "PYTHONDONTWRITEBYTECODE": "1",
            "FAKE_GH_DIR": str(self.scratch / "gh"),
            "FAKE_GH_ORIGIN": str(self.origin),
            "GITHUB_REPOSITORY": "owner/name",
            "GITHUB_SERVER_URL": "https://github.example",
        }
        self.work = self.scratch / "work"
        self.runs = 0
        self.git(self.scratch, "init", "-q", "--bare", "-b", "main", str(self.origin))
        self.git(self.scratch, "init", "-q", "-b", "main", str(self.work))
        self.git(self.work, "remote", "add", "origin", str(self.origin))

    def git(self, directory, *arguments):
        done = subprocess.run(
            ["git", *arguments],
            cwd=directory,
            env=self.environment,
            capture_output=True,
            text=True,
            check=True,
        )
        return done.stdout.strip()

    def push(self, files, message="Add a thing"):
        """Commit `files` over main of origin and push them; return the commit."""
        if self.git(self.scratch, "--git-dir", str(self.origin), "for-each-ref", "refs/heads/main"):
            self.git(self.work, "fetch", "-q", "origin")
            self.git(self.work, "checkout", "-q", "-B", "main", "origin/main")
        for path, text in files.items():
            file = self.work / path
            file.parent.mkdir(parents=True, exist_ok=True)
            file.write_bytes(text.encode())
        self.git(self.work, "add", "-A")
        self.git(self.work, "commit", "-q", "--allow-empty", "-m", message)
        self.git(self.work, "push", "-q", "origin", "main")
        return self.git(self.work, "rev-parse", "HEAD")

    def release(self, commit, event="workflow_run", bump="patch", **settings):
        """Run the release as CD does, in a new checkout of `commit`."""
        self.runs += 1
        checkout = self.scratch / f"checkout-{self.runs}"
        self.git(self.scratch, "clone", "-q", str(self.origin), str(checkout))
        self.git(checkout, "checkout", "-q", commit)
        return subprocess.run(
            ["python3", str(SCRIPT)],
            cwd=checkout,
            env={
                **self.environment,
                "GITHUB_EVENT_NAME": event,
                "RELEASE_COMMIT": commit,
                "RELEASE_BUMP": bump,
                **settings,
            },
            capture_output=True,
            text=True,
            timeout=120,
            check=False,
        )

    def calls(self):
        file = self.scratch / "gh" / "calls.jsonl"
        if not file.exists():
            return []
        return [json.loads(line) for line in file.read_text().splitlines()]

    def writes(self):
        """The calls that change something on GitHub, oldest first, each named."""
        names = []
        for call in self.calls():
            if "createCommitOnBranch" in call["stdin"]:
                names.append("commit")
            elif call["arguments"][-3:-2] != ["GET"] and "/releases" in " ".join(call["arguments"]):
                names.append("release")
        return names

    def release_body(self):
        posted = [call for call in self.calls() if "/releases" in " ".join(call["arguments"])]
        return json.loads(posted[-1]["stdin"])

    def origin_file(self, path, reference="main"):
        return self.git(self.scratch, "--git-dir", str(self.origin), "show", f"{reference}:{path}") + "\n"

    def origin_head(self):
        return self.git(self.scratch, "--git-dir", str(self.origin), "rev-parse", "refs/heads/main")

    def origin_tag(self, tag):
        return self.git(self.scratch, "--git-dir", str(self.origin), "rev-parse", f"refs/tags/{tag}^{{commit}}")

    def origin_tags(self):
        return self.git(self.scratch, "--git-dir", str(self.origin), "tag", "--list").split()

    def set_state(self, name, text):
        (self.scratch / "gh" / name).write_text(text)

    def assert_nothing_written(self, done, head, tags=()):
        self.assertEqual(self.writes(), [], done.stderr)
        self.assertEqual(self.origin_head(), head)
        self.assertEqual(self.origin_tags(), list(tags))


class FirstAndNext(Pipeline):
    def test_the_first_release_is_0_0_0_with_no_compare_link(self):
        commit = self.push(TREE)
        done = self.release(commit)
        self.assertEqual(done.returncode, 0, done.stderr)
        self.assertEqual(self.writes(), ["commit", "release"])
        self.assertEqual(self.origin_file(".version"), "0.0.0\n")
        self.assertEqual(
            self.git(self.scratch, "--git-dir", str(self.origin), "log", "-n", "1", "--format=%B", "main"),
            "Version 0.0.0\n\n[skip ci]",
        )
        self.assertEqual(self.git(self.scratch, "--git-dir", str(self.origin), "rev-parse", "main^"), commit)
        self.assertEqual(self.origin_tag("0.0.0"), self.origin_head())
        body = self.release_body()
        self.assertEqual(body["tag_name"], "0.0.0")
        self.assertEqual(body["target_commitish"], self.origin_head())
        self.assertNotIn("compare", body["body"])

    def test_the_next_is_a_patch_with_a_table_and_a_compare_link(self):
        self.release(self.push(TREE))
        commit = self.push({"docs/page.md": "Changed.\n", "docs/new.md": "New.\n"})
        done = self.release(commit)
        self.assertEqual(done.returncode, 0, done.stderr)
        self.assertEqual(self.origin_file(".version"), "0.0.1\n")
        notes = self.release_body()["body"]
        self.assertIn("| Changed | `docs/page.md` |", notes)
        self.assertIn("| Added | `docs/new.md` |", notes)
        # The version commit is the pipeline's, not a change to tell of.
        self.assertNotIn(".version", notes)
        self.assertNotIn("sommaire", notes)
        self.assertIn("https://github.example/owner/name/compare/0.0.0...0.0.1", notes)

    def test_a_second_run_finds_nothing_to_do(self):
        commit = self.push(TREE)
        self.release(commit)
        head = self.origin_head()
        calls = len(self.writes())
        done = self.release(commit)
        self.assertEqual(done.returncode, 0, done.stderr)
        self.assertEqual(len(self.writes()), calls)
        self.assertEqual(self.origin_head(), head)


class Bumps(Pipeline):
    def released(self, version):
        self.push({**TREE, ".version": f"{version}\n"})
        return self.push({"docs/page.md": "Changed.\n"})

    def test_a_manual_run_raises_the_part_it_names(self):
        for bump, expected in (("patch", "1.2.4"), ("minor", "1.3.0"), ("major", "2.0.0")):
            with self.subTest(bump=bump):
                self.setUp()
                commit = self.released("1.2.3")
                self.set_state("ci.json", json.dumps([commit]))
                done = self.release(commit, event="workflow_dispatch", bump=bump)
                self.assertEqual(done.returncode, 0, done.stderr)
                self.assertEqual(self.origin_file(".version"), f"{expected}\n")
                self.assertEqual(self.origin_tag(expected), self.origin_head())

    def test_a_manual_run_on_a_released_version_commit_reads_ci_of_its_parent(self):
        commit = self.push(TREE)
        self.release(commit)
        self.set_state("ci.json", json.dumps([commit]))
        done = self.release(self.origin_head(), event="workflow_dispatch", bump="minor")
        self.assertEqual(done.returncode, 0, done.stderr)
        self.assertEqual(self.origin_file(".version"), "0.1.0\n")

    def test_a_version_commit_with_no_success_on_its_parent_writes_nothing(self):
        self.release(self.push(TREE))
        head, before = self.origin_head(), len(self.writes())
        done = self.release(head, event="workflow_dispatch", bump="minor")
        self.assertNotEqual(done.returncode, 0)
        self.assertEqual(len(self.writes()), before)
        self.assertEqual(self.origin_head(), head)


class Refusals(Pipeline):
    def test_a_bad_version_file_writes_nothing(self):
        for text in ("1.2\n", "1.2.3", "banana\n"):
            with self.subTest(text=text):
                self.setUp()
                commit = self.push({**TREE, ".version": text})
                done = self.release(commit)
                self.assertEqual(done.returncode, 2)
                self.assertIn(".version", done.stderr)
                self.assert_nothing_written(done, commit)

    def test_a_tag_on_the_next_version_writes_nothing(self):
        commit = self.push({**TREE, ".version": "1.2.3\n"})
        self.git(self.work, "tag", "1.2.4")
        self.git(self.work, "push", "-q", "origin", "1.2.4")
        done = self.release(commit)
        self.assertEqual(done.returncode, 2)
        self.assert_nothing_written(done, commit, ["1.2.4"])

    def test_a_moved_main_writes_nothing(self):
        commit = self.push(TREE)
        newer = self.push({"docs/page.md": "Newer.\n"})
        done = self.release(commit)
        self.assertEqual(done.returncode, 0, done.stderr)
        self.assert_nothing_written(done, newer)

    def test_a_commit_that_only_looks_like_a_version_commit_is_a_moved_main(self):
        commit = self.push(TREE)
        for files, message in (
            ({"docs/page.md": "Other.\n", ".version": "0.0.0\n"}, "Version 0.0.0\n\n[skip ci]"),
            ({".version": "0.0.0\n"}, "Version 0.0.0"),
            ({"docs/page.md": "Another.\n"}, "Version 0.0.0\n\n[skip ci]"),
        ):
            with self.subTest(message=message):
                newer = self.push(files, message)
                done = self.release(commit)
                self.assertEqual(done.returncode, 0, done.stderr)
                self.assert_nothing_written(done, newer)
                commit = newer

    def test_a_manual_run_without_a_successful_ci_writes_nothing(self):
        commit = self.push(TREE)
        done = self.release(commit, event="workflow_dispatch", bump="minor")
        self.assertNotEqual(done.returncode, 0)
        self.assertIn(commit, done.stderr)
        self.assert_nothing_written(done, commit)

    def test_a_success_on_another_commit_does_not_count(self):
        older = self.push(TREE)
        commit = self.push({"docs/page.md": "Newer.\n"})
        self.set_state("ci.json", json.dumps([older]))
        done = self.release(commit, event="workflow_dispatch")
        self.assertNotEqual(done.returncode, 0)
        self.assert_nothing_written(done, commit)

    def test_a_package_with_no_header_stops_it(self):
        for text in (";;; No header.\n", f"{HEADER}{HEADER}"):
            with self.subTest(text=text):
                self.setUp()
                commit = self.push({**TREE, "imprimeur-skin-xix/imprimeur-skin-xix.el": text})
                done = self.release(commit)
                self.assertEqual(done.returncode, 2)
                self.assertIn("imprimeur-skin-xix", done.stderr)
                self.assert_nothing_written(done, commit)

    def test_a_package_with_no_main_file_stops_it(self):
        commit = self.push({**TREE, "imprimeur-skin-new/other.el": HEADER})
        done = self.release(commit)
        self.assertEqual(done.returncode, 2)
        self.assert_nothing_written(done, commit)

    def test_malformed_settings_write_nothing(self):
        commit = self.push(TREE)
        for settings in (
            {"RELEASE_COMMIT": "main"},
            {"RELEASE_BUMP": "huge"},
            {"GITHUB_EVENT_NAME": "push"},
            {"GITHUB_REPOSITORY": "no-slash"},
            {"GITHUB_SERVER_URL": "http://insecure.example"},
        ):
            with self.subTest(settings=settings):
                done = self.release(commit, **settings)
                self.assertEqual(done.returncode, 2)
                self.assertIn(next(iter(settings)), done.stderr)
                self.assertEqual(self.calls(), [])
                self.assertEqual(self.origin_head(), commit)

    def test_an_answer_that_is_no_commit_stops_before_the_release(self):
        commit = self.push(TREE)
        self.set_state("garbage", "createCommitOnBranch")
        done = self.release(commit)
        self.assertEqual(done.returncode, 2)
        self.assertEqual(self.writes(), ["commit"])

    def test_a_commit_refused_on_a_branch_that_moved_stops_before_the_release(self):
        commit = self.push(TREE)
        self.set_state("fail", "createCommitOnBranch")
        done = self.release(commit)
        self.assertEqual(done.returncode, 2)
        self.assertEqual(self.writes(), ["commit"])
        self.assertEqual(self.origin_tags(), [])


class CutShort(Pipeline):
    def cut_short(self):
        commit = self.push(TREE)
        self.set_state("fail", "/releases")
        self.assertEqual(self.release(commit).returncode, 2)
        self.assertEqual(self.writes(), ["commit", "release"])
        self.assertEqual(self.origin_tags(), [])
        (self.scratch / "gh" / "fail").unlink()
        (self.scratch / "gh" / "calls.jsonl").unlink()
        return commit

    def test_a_run_cut_short_after_the_commit_makes_only_the_release(self):
        commit = self.cut_short()
        made = self.origin_head()
        done = self.release(commit)
        self.assertEqual(done.returncode, 0, done.stderr)
        self.assertEqual(self.writes(), ["release"])
        self.assertEqual(self.origin_head(), made)
        self.assertEqual(self.origin_tag("0.0.0"), made)

    def test_a_manual_run_finishes_it_too_and_does_not_raise_anything(self):
        commit = self.cut_short()
        made = self.origin_head()
        self.set_state("ci.json", json.dumps([commit]))
        done = self.release(made, event="workflow_dispatch", bump="major")
        self.assertEqual(done.returncode, 0, done.stderr)
        self.assertEqual(self.writes(), ["release"])
        self.assertEqual(self.origin_head(), made)
        self.assertEqual(self.origin_tag("0.0.0"), made)

    def test_it_finishes_even_if_main_moved_again(self):
        commit = self.cut_short()
        made = self.origin_head()
        self.push({"docs/page.md": "Newer.\n"})
        done = self.release(commit)
        self.assertEqual(done.returncode, 0, done.stderr)
        self.assertEqual(self.writes(), ["release"])
        self.assertEqual(self.origin_tag("0.0.0"), made)

    def test_a_tag_on_another_commit_stops_it(self):
        commit = self.cut_short()
        self.git(self.work, "tag", "0.0.0", commit)
        self.git(self.work, "push", "-q", "origin", "0.0.0")
        done = self.release(commit)
        self.assertEqual(done.returncode, 2)
        self.assertEqual(self.writes(), [])


class Headers(Pipeline):
    def test_every_header_is_rewritten_and_nothing_else(self):
        self.release(self.push(TREE))
        self.set_state("ci.json", json.dumps([self.push({"docs/page.md": "Changed.\n"})]))
        before = self.origin_head()
        done = self.release(before, event="workflow_dispatch", bump="minor")
        self.assertEqual(done.returncode, 0, done.stderr)
        self.assertEqual(self.origin_file(".version"), "0.1.0\n")
        for path in MAIN_FILES:
            with self.subTest(path=path):
                self.assertEqual(self.origin_file(path), TREE[path].replace("0.0.0", "0.1.0"))
        changed = self.git(self.scratch, "--git-dir", str(self.origin), "diff", "--name-only", before, "main")
        self.assertEqual(set(changed.split("\n")), {".version", *MAIN_FILES})

    def test_the_commit_sends_the_contents_in_base64(self):
        self.release(self.push(TREE))
        commit = next(call for call in self.calls() if "createCommitOnBranch" in call["stdin"])
        change = json.loads(commit["stdin"])["variables"]["input"]
        sent = {
            addition["path"]: base64.b64decode(addition["contents"]).decode()
            for addition in change["fileChanges"]["additions"]
        }
        self.assertEqual(sent, {".version": "0.0.0\n", **{path: TREE[path] for path in MAIN_FILES}})
        self.assertEqual(change["branch"], {"repositoryNameWithOwner": "owner/name", "branchName": "main"})
        self.assertEqual(change["message"], {"headline": "Version 0.0.0", "body": "[skip ci]"})


if __name__ == "__main__":
    unittest.main()
