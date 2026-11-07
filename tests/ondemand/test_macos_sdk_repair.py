import importlib.util
import json
import tempfile
import unittest
from pathlib import Path


SPEC = importlib.util.spec_from_file_location(
    "sdk_repair", Path(__file__).resolve().parents[2] / "scripts/repair-macos-sdk.py"
)
repair = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(repair)


class MacosSdkRepairTest(unittest.TestCase):
    def setUp(self):
        temporary = tempfile.TemporaryDirectory()
        self.addCleanup(temporary.cleanup)
        self.root = Path(temporary.name).resolve()
        self.sdks = self.root / "SDKs"
        self.sdks.mkdir()
        self.preferred = self.make_sdk("26.5")
        self.newer = self.make_sdk("27.0")
        (self.sdks / "MacOSX.sdk").symlink_to(self.preferred.name)
        (self.sdks / "MacOSX27.sdk").symlink_to(self.newer.name)
        self.backup = self.root / "SDKs-disabled/backup"

    def make_sdk(self, version):
        sdk = self.sdks / f"MacOSX{version}.sdk"
        sdk.mkdir()
        (sdk / "SDKSettings.json").write_text(json.dumps({"Version": version}))
        return sdk

    def test_only_selected_newer_sdk_and_its_aliases_are_planned(self):
        older = self.make_sdk("15.4")
        preferred, paths = repair.repair_plan(self.sdks, 26, self.newer)
        self.assertEqual(preferred, self.preferred)
        self.assertEqual(paths, [self.newer, self.sdks / "MacOSX27.sdk"])
        self.assertTrue(older.exists())
        self.assertTrue(self.newer.exists())

    def test_unsafe_targets_are_rejected(self):
        external = self.root / "external.sdk"
        external.mkdir()
        for name, major, target, message in (
            ("mismatched installer", 27, self.newer, "does not match"),
            ("current sdk", 26, self.preferred, "not a newer leftover"),
            ("outside SDKs", 26, external, "direct children"),
        ):
            with self.subTest(name):
                with self.assertRaisesRegex(RuntimeError, message):
                    repair.repair_plan(self.sdks, major, target)

    def test_quarantine_preserves_contents_alias_and_preferred_sdk(self):
        _, paths = repair.repair_plan(self.sdks, 26, self.newer)
        expected = (self.newer / "SDKSettings.json").read_bytes()
        repair.quarantine(paths, self.backup, lambda: None)
        self.assertEqual(
            (self.backup / self.newer.name / "SDKSettings.json").read_bytes(), expected
        )
        self.assertEqual(
            (self.backup / "MacOSX27.sdk").readlink(), Path(self.newer.name)
        )
        self.assertTrue((self.sdks / "MacOSX.sdk").resolve().is_dir())
        self.assertFalse(self.newer.exists())

    def test_failed_or_interrupted_quarantine_restores_sdk_and_alias(self):
        def raise_(error):
            def verify():
                raise error

            return verify

        for name, extra, verify, error in (
            ("failed probe", [], raise_(RuntimeError("probe failed")), RuntimeError),
            ("interrupted probe", [], raise_(KeyboardInterrupt()), KeyboardInterrupt),
            ("failed move", ["missing.sdk"], lambda: None, FileNotFoundError),
        ):
            with self.subTest(name):
                _, paths = repair.repair_plan(self.sdks, 26, self.newer)
                paths += [self.sdks / path for path in extra]
                with self.assertRaises(error):
                    repair.quarantine(paths, self.backup / name, verify)
                self.assertTrue(self.newer.is_dir())
                self.assertEqual((self.sdks / "MacOSX27.sdk").resolve(), self.newer)
                self.assertTrue(self.preferred.is_dir())
