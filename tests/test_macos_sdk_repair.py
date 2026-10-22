import importlib.util
import json
import tempfile
import unittest
from pathlib import Path


SPEC = importlib.util.spec_from_file_location(
    "sdk_repair", Path(__file__).resolve().parents[1] / "scripts/repair-macos-sdk.py"
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

    def test_mismatched_installer_sdk_is_rejected(self):
        with self.assertRaisesRegex(RuntimeError, "does not match"):
            repair.repair_plan(self.sdks, 27, self.newer)

    def test_current_sdk_cannot_be_quarantined(self):
        with self.assertRaisesRegex(RuntimeError, "not a newer leftover"):
            repair.repair_plan(self.sdks, 26, self.preferred)

    def test_external_sdk_is_rejected(self):
        external = self.root / "external.sdk"
        external.mkdir()
        with self.assertRaisesRegex(RuntimeError, "direct children"):
            repair.repair_plan(self.sdks, 26, external)

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

    def test_failed_verification_restores_sdk_and_alias(self):
        _, paths = repair.repair_plan(self.sdks, 26, self.newer)

        def failure():
            raise RuntimeError("probe failed")

        with self.assertRaisesRegex(RuntimeError, "probe failed"):
            repair.quarantine(paths, self.backup, failure)
        self.assertTrue(self.newer.is_dir())
        self.assertEqual((self.sdks / "MacOSX27.sdk").resolve(), self.newer)
        self.assertTrue(self.preferred.is_dir())

    def test_failed_move_restores_already_moved_sdk(self):
        _, paths = repair.repair_plan(self.sdks, 26, self.newer)
        paths.append(self.sdks / "missing.sdk")
        with self.assertRaises(FileNotFoundError):
            repair.quarantine(paths, self.backup, lambda: None)
        self.assertTrue(self.newer.is_dir())
        self.assertEqual((self.sdks / "MacOSX27.sdk").resolve(), self.newer)

    def test_interrupted_verification_restores_sdk_and_alias(self):
        _, paths = repair.repair_plan(self.sdks, 26, self.newer)

        def interrupted():
            raise KeyboardInterrupt()

        with self.assertRaises(KeyboardInterrupt):
            repair.quarantine(paths, self.backup, interrupted)
        self.assertTrue(self.newer.is_dir())
        self.assertEqual((self.sdks / "MacOSX27.sdk").resolve(), self.newer)
