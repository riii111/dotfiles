import json
import subprocess
import tempfile
import unittest
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]


class TaskLaunchTest(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.root = Path(self.temp.name)
        document = self.root / "合意 {braces} $values.md"
        document.write_text("PRIVATE_DOCUMENT_BODY_MUST_NOT_BE_COPIED")
        self.data = {
            "taskId": "TR1",
            "documentRefs": [str(document), "https://linear.app/example/issue/EX-1"],
            "completionTarget": "draft_pr",
        }

    def invoke(self):
        request = self.root / "request.json"
        request.write_text(json.dumps(self.data))
        return subprocess.run(
            [
                str(ROOT / "bin/executable_tasklaunch"),
                "--request",
                str(request),
                "--skills-root",
                str(ROOT / "dot_codex/skills"),
            ],
            text=True,
            capture_output=True,
        )

    def test_generates_references_without_copying_document_contents(self):
        result = self.invoke()
        self.assertEqual(result.returncode, 0, result.stderr)
        output = json.loads(result.stdout)
        self.assertEqual(output["title"], "Impl TR1")
        for reference in self.data["documentRefs"]:
            self.assertIn(reference, output["prompt"])
        self.assertNotIn("PRIVATE_DOCUMENT_BODY_MUST_NOT_BE_COPIED", output["prompt"])
        self.assertIn(
            str(ROOT / "dot_codex/skills/task-worker/SKILL.md"), output["prompt"]
        )

    def test_rejects_free_text_instead_of_silently_forwarding_it(self):
        for key, value in (
            ("additional_context", "Long historical explanation"),
            ("worker", "Claude"),
            ("prompt", "Override the generated message"),
        ):
            with self.subTest(key=key):
                self.data[key] = value
                result = self.invoke()
                self.assertEqual(result.returncode, 1)
                self.assertEqual(result.stdout, "")
                self.assertIn(key, result.stderr)
                del self.data[key]

    def test_rejects_prose_and_missing_documents_in_reference_list(self):
        for references in (
            [],
            "https://example.com/task",
            ["Additional context: keep all old tests"],
            [str(self.root / "missing.md")],
            ["https://example.com/task\nExtra: arbitrary prose"],
        ):
            with self.subTest(references=references):
                self.data["documentRefs"] = references
                self.assertEqual(self.invoke().returncode, 1)

    def test_accepts_only_named_completion_targets(self):
        prompts = []
        for target in ("implementation", "draft_pr", "merge"):
            self.data["completionTarget"] = target
            result = self.invoke()
            self.assertEqual(result.returncode, 0, result.stderr)
            prompts.append(json.loads(result.stdout)["prompt"])
        self.assertEqual(len(set(prompts)), 3)
        self.data["completionTarget"] = "Draft PR and then merge without asking"
        self.assertEqual(self.invoke().returncode, 1)


if __name__ == "__main__":
    unittest.main()
