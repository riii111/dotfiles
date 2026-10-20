import importlib.machinery
import importlib.util
import io
import json
import subprocess
import tempfile
import unittest
from contextlib import redirect_stderr, redirect_stdout
from pathlib import Path
from unittest import mock
from urllib.parse import parse_qs, urlsplit


ROOT = Path(__file__).resolve().parents[1]
SCRIPT = (
    ROOT
    / "dot_codex"
    / "skills"
    / "suggested-issue"
    / "scripts"
    / "executable_issue-url.py"
)

TRICKY_BODY = """## 背景

検索APIで `a=1&b=2#frag` を渡すと 100% 失敗する。
+記号・スペース  2つ・タブ\tも保持する。

## 期待する状態

- 日本語・絵文字🎉・改行を含めても壊れない
"""


def load_module():
    loader = importlib.machinery.SourceFileLoader("issue_url", str(SCRIPT))
    spec = importlib.util.spec_from_loader(loader.name, loader)
    assert spec is not None and spec.loader is not None
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


def decode(url):
    parts = urlsplit(url)
    query = parse_qs(parts.query, keep_blank_values=True, strict_parsing=True)
    return parts, {key: values[0] for key, values in query.items()}


class ParseRemoteTest(unittest.TestCase):
    def setUp(self):
        self.mod = load_module()

    def test_supported_forms(self):
        for url in (
            "https://github.com/riii111/dotfiles",
            "https://github.com/riii111/dotfiles.git\n",
            "https://token@github.com/riii111/dotfiles.git",
            "git@github.com:riii111/dotfiles.git",
            "ssh://git@github.com/riii111/dotfiles.git",
            "ssh://git@github.com:443/riii111/dotfiles",
        ):
            with self.subTest(url=url):
                self.assertEqual(self.mod.parse_remote(url), "riii111/dotfiles")

    def test_non_github_remote(self):
        self.assertIsNone(self.mod.parse_remote("https://gitlab.com/a/b.git"))


class MainTest(unittest.TestCase):
    def setUp(self):
        self.mod = load_module()
        self.tmp = tempfile.TemporaryDirectory()
        self.addCleanup(self.tmp.cleanup)
        self.body_path = Path(self.tmp.name) / "body.md"
        self.body_path.write_text(TRICKY_BODY, encoding="utf-8")

    def run_main(self, *args):
        stdout, stderr = io.StringIO(), io.StringIO()
        with redirect_stdout(stdout), redirect_stderr(stderr):
            code = self.mod.main(["--body-file", str(self.body_path), *args])
        return code, stdout.getvalue(), stderr.getvalue()

    def test_url_round_trips_final_title_and_body(self):
        title = "検索で a=1&b=2 と #frag を含むと失敗する"
        code, out, _ = self.run_main("--title", title, "--repo", "owner/repo")
        self.assertEqual(code, 0)
        result = json.loads(out)
        self.assertEqual(result["repo"], "owner/repo")
        self.assertFalse(result["too_long"])
        parts, query = decode(result["url"])
        self.assertEqual((parts.scheme, parts.netloc), ("https", "github.com"))
        self.assertEqual(parts.path, "/owner/repo/issues/new")
        self.assertEqual(parts.fragment, "")
        self.assertEqual(
            query,
            {"title": title, "body": self.body_path.read_text(encoding="utf-8")},
        )

    def test_too_long_withholds_url(self):
        code, out, _ = self.run_main(
            "--title", "題名", "--repo", "owner/repo", "--max-length", "100"
        )
        self.assertEqual(code, 3)
        result = json.loads(out)
        self.assertTrue(result["too_long"])
        self.assertIsNone(result["url"])
        self.assertGreater(result["length"], 100)

    def test_invalid_repo(self):
        code, _, err = self.run_main("--title", "t", "--repo", "owner/repo?x=1")
        self.assertEqual(code, 2)
        self.assertIn("invalid repository", err)

    def test_empty_title(self):
        code, _, err = self.run_main("--title", "  ", "--repo", "owner/repo")
        self.assertEqual(code, 2)
        self.assertIn("title is empty", err)

    def test_ambiguous_remotes_require_repo(self):
        repos = {"me/fork": ["origin"], "up/repo": ["upstream"]}
        with mock.patch.object(self.mod, "git_remote_repos", return_value=repos):
            code, _, err = self.run_main("--title", "t")
        self.assertEqual(code, 2)
        self.assertIn("me/fork (origin)", err)
        self.assertIn("up/repo (upstream)", err)

    def test_remote_from_git_repository(self):
        repo_dir = Path(self.tmp.name) / "repo"
        repo_dir.mkdir()
        subprocess.run(["git", "init", "-q"], cwd=repo_dir, check=True)
        subprocess.run(
            ["git", "remote", "add", "origin", "git@github.com:me/proj.git"],
            cwd=repo_dir,
            check=True,
        )
        subprocess.run(
            ["git", "remote", "add", "mirror", "https://github.com/me/proj"],
            cwd=repo_dir,
            check=True,
        )
        self.assertEqual(self.mod.resolve_repo(None, repo_dir), "me/proj")


if __name__ == "__main__":
    unittest.main()
