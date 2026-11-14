"""Public export boundary tests use only synthetic files in a temporary directory."""
import importlib.util
from pathlib import Path
import json
import shutil
import sys
import tempfile
import unittest
import uuid
from unittest.mock import patch

ROOT = Path(__file__).resolve().parent.parent
sys.path.insert(0, str(ROOT / "scripts"))
from public_source import public_files

spec = importlib.util.spec_from_file_location("release_check", ROOT / "scripts/check-release.py")
release_check = importlib.util.module_from_spec(spec)
spec.loader.exec_module(release_check)


class PublicSourceTests(unittest.TestCase):
    def setUp(self):
        self.temporary = tempfile.TemporaryDirectory(dir=ROOT / ".build")
        self.root = Path(self.temporary.name)
        for source in public_files(ROOT):
            target = self.root / source.relative_to(ROOT)
            target.parent.mkdir(parents=True, exist_ok=True)
            shutil.copyfile(source, target)

    def tearDown(self):
        self.temporary.cleanup()

    def test_private_artifacts_are_excluded(self):
        sentinel = "synthetic-private-" + uuid.uuid4().hex
        for name in ("qa/recording.wav", ".git/config", "dist/app.zip", ".build/preferences.plist", "personal-dictionary.json",
                     ".ios-signing.local.xcconfig", "iOS/VoiceSeed.xcodeproj/project.xcworkspace/xcuserdata/fixture.xcuserstate"):
            path = self.root / name
            path.parent.mkdir(parents=True, exist_ok=True)
            path.write_text(sentinel)
        files = public_files(self.root)
        self.assertFalse(any(sentinel.encode() in path.read_bytes() for path in files))
        self.assertEqual(release_check.check(self.root), [])

    def test_missing_destination_blocks_public_export(self):
        path = self.root / "Resources/PublicAppInfo.json"
        info = json.loads(path.read_text())
        next(link for link in info["links"] if link["id"] == "LINE")["url"] = ""
        path.write_text(json.dumps(info))
        self.assertTrue(any("LINE" in message for message in release_check.check(self.root)))

    def test_symlink_is_rejected_before_any_metadata_read(self):
        path = self.root / "Resources/PublicAppInfo.json"
        path.unlink()
        path.symlink_to(self.root / "synthetic-outside.plist")
        with patch.object(Path, "read_bytes", side_effect=AssertionError("Metadata must not be opened")):
            errors = release_check.check(self.root)
        self.assertTrue(any("Symlinks" in message for message in errors))

    def test_accidental_token_blocks_export(self):
        with (self.root / "README.md").open("a") as handle:
            handle.write("\n" + "ghp_" + "a" * 40)
        self.assertTrue(any("Possible credential" in message for message in release_check.check(self.root)))


if __name__ == "__main__":
    unittest.main()
