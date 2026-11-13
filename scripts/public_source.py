"""Explicit public-source inventory. Never read preferences, recordings or Git history."""
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
TOP_LEVEL = (
    ".gitignore", "README.md", "LICENSE", "PRIVACY.md", "THIRD_PARTY_NOTICES.md",
    "CONTRIBUTING.md", "SECURITY.md", "CHANGELOG.md", "起動.command",
)
RESOURCES = (
    "Info.plist", "PublicAppInfo.json", "SparkleLicense.txt", "Release.entitlements", "AppIcon.icns", "AppIcon1024.png",
)
FIXTURES = ("Tests/Fixtures/aqua-example.json", "Tests/Fixtures/atok-example.txt")


def public_files(root=ROOT):
    paths = [root / name for name in TOP_LEVEL]
    paths += [root / "Resources" / name for name in RESOURCES]
    paths += [root / name for name in FIXTURES]
    patterns = {
        "Sources": ("*.swift",), "Tests": ("*.swift", "*.py"),
        "scripts": ("*.sh", "*.py", "*.swift"), "docs": ("*.md",),
        ".github/workflows": ("*.yml",), ".github/ISSUE_TEMPLATE": ("*.yml", "*.md"),
    }
    for directory, globs in patterns.items():
        for glob in globs:
            paths.extend((root / directory).glob(glob))
    # Resolve neither symlinks nor outside paths: an archive must contain only reviewed source files.
    for path in paths:
        if any(part.is_symlink() for part in (path, *path.parents) if part != root.parent):
            raise ValueError(f"Symlinks are not allowed in public source: {path.name}")
        if not path.is_file():
            raise ValueError(f"Missing public source file: {path.relative_to(root)}")
    return sorted(set(paths), key=lambda p: p.relative_to(root).as_posix())
