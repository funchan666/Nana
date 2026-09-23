#!/usr/bin/env python3
"""Read-only Nana resource audit. Never builds, runs, extracts or changes an app."""
import argparse
import json
import os
from pathlib import Path, PurePosixPath
import plistlib
import re
import stat
import subprocess
import sys
import zipfile

ROOT = Path(__file__).resolve().parents[1]
CATEGORY = "public.app-category.lifestyle"
LOCAL_PATH = re.compile(
    rb"/(?:Users|home)/[^/\x00\s]{1,128}/|/var/folders/[A-Za-z0-9_/.-]+|"
    rb"[A-Za-z]:\\Users\\[^\\\x00\s]{1,128}\\"
)
DEVELOPMENT_SUFFIXES = {
    ".md", ".markdown", ".py", ".pyc", ".sh", ".yml", ".yaml", ".log",
    ".swift", ".m", ".mm", ".h", ".storekit", ".xcscheme", ".xcconfig",
    ".xcuserstate", ".pbxproj", ".xcworkspacedata", ".bak", ".tmp", ".orig",
}
DEVELOPMENT_DIRECTORIES = {
    ".git", ".build", "docs", "scripts", "xcuserdata", "deriveddata",
    "garden-gpt-image-2", "__pycache__",
}
DEVELOPMENT_NAMES = {
    ".ds_store", ".gitignore", "readme", "agents.md", "brand-spec.md",
    "release-image-inventory.json", "release-video-inventory.json",
}


class Audit:
    def __init__(self):
        self.findings = set()
        self.files = 0
        self.bytes = 0

    def flag(self, path, reason):
        # Do not print a matched local path or the contents of a suspect file.
        self.findings.add((str(path), reason))

    def inspect(self, name, stream, size, source_catalog=False):
        self.files += 1
        self.bytes += size
        parts = PurePosixPath(name).parts
        lower = [p.lower() for p in parts]
        if (any(p in DEVELOPMENT_DIRECTORIES for p in lower)
                or any(p.endswith((".xcodeproj", ".xcworkspace", ".dsym")) for p in lower)
                or lower[-1] in DEVELOPMENT_NAMES or lower[-1].startswith((".env", "._"))
                or PurePosixPath(name).suffix.lower() in DEVELOPMENT_SUFFIXES):
            self.flag(name, "Development document, script, configuration or temporary file")
        if not source_catalog and any(p.endswith(".xcassets") for p in lower):
            self.flag(name, "Uncompiled asset catalog in the exported app")
        tail = b""
        while chunk := stream.read(1024 * 1024):
            if LOCAL_PATH.search(tail + chunk):
                self.flag(name, "Embedded local filesystem path; inspect before distribution")
                break
            tail = chunk[-1024:]

    def info(self, data, label):
        info = plistlib.loads(data)
        if info.get("LSApplicationCategoryType") != CATEGORY:
            self.flag(label, "Main application category is not Lifestyle")
        if (info.get("DTPlatformName") == "iphonesimulator"
                or "iPhoneSimulator" in info.get("CFBundleSupportedPlatforms", [])):
            self.flag(label, "Simulator build supplied instead of a device distribution build")
        if not info.get("CFBundleExecutable") or not info.get("CFBundleIdentifier"):
            self.flag(label, "Missing main application identity or executable")

    def provision(self, data, label):
        # Read the embedded plist only; this is not cryptographic signature validation.
        start, end = data.find(b"<plist"), data.find(b"</plist>")
        if start < 0 or end < start:
            self.flag(label, "Provisioning profile could not be inspected")
            return
        info = plistlib.loads(data[start:end + len(b"</plist>")])
        if info.get("Entitlements", {}).get("get-task-allow") is True:
            self.flag(label, "Development provisioning allows debugger attachment")

    def directory(self, folder, base, source_catalog=False):
        candidates = [folder] if folder.is_file() else []
        for current, dirs, files in os.walk(folder, followlinks=False):
            for name in list(dirs):
                path = Path(current) / name
                if path.is_symlink():
                    self.flag(path.relative_to(base), "Symbolic link requires manual inspection")
                    dirs.remove(name)
            candidates.extend(Path(current) / name for name in files)
        for path in sorted(candidates):
            label = path.relative_to(base).as_posix()
            if path.is_symlink():
                self.flag(label, "Symbolic link requires manual inspection")
                continue
            with path.open("rb") as stream:
                self.inspect(label, stream, path.stat().st_size, source_catalog)

    def project(self):
        # Resolve the real Xcode resource build phase instead of assuming a fixed folder list.
        raw = subprocess.check_output([
            "plutil", "-convert", "json", "-o", "-", str(ROOT / "Nana.xcodeproj/project.pbxproj")
        ], stderr=subprocess.DEVNULL)
        project = json.loads(raw)
        objects = project["objects"]
        paths = {}

        def visit(identifier, parent):
            item = objects[identifier]
            tree = item.get("sourceTree", "<group>")
            if tree not in {"<group>", "SOURCE_ROOT"}:
                return
            path = (ROOT if tree == "SOURCE_ROOT" else parent) / item.get("path", "")
            paths[identifier] = path
            for child in item.get("children", []):
                visit(child, path)

        visit(objects[project["rootObject"]]["mainGroup"], ROOT)
        resources = set()
        for item in objects.values():
            kind = item.get("isa")
            if kind in {"PBXShellScriptBuildPhase", "PBXCopyFilesBuildPhase"}:
                self.flag("project.pbxproj", "Additional script/copy phase requires a separate packaging review")
            if kind == "PBXResourcesBuildPhase":
                for identifier in item.get("files", []):
                    reference = objects[identifier].get("fileRef")
                    path = paths.get(reference)
                    if path is None:
                        self.flag("project.pbxproj", "Unresolved resource reference")
                    else:
                        resources.add(path)
            settings = item.get("buildSettings", {})
            category = settings.get("INFOPLIST_KEY_LSApplicationCategoryType")
            if category is not None and category != CATEGORY:
                self.flag("project.pbxproj", "Target category differs from Lifestyle")
        if not resources:
            self.flag("project.pbxproj", "No resource build phase found")
        for path in sorted(resources):
            if not path.resolve().is_relative_to(ROOT):
                self.flag("project.pbxproj", "Resource points outside the project")
            elif not path.exists():
                self.flag(path.relative_to(ROOT), "Missing resource")
            else:
                self.directory(path, ROOT, source_catalog=True)
        self.info((ROOT / "NanaHarbor/Support/AppInfo.plist").read_bytes(), "AppInfo.plist")
        config = (ROOT / "project.yml").read_text()
        categories = re.findall(r"(?:INFOPLIST_KEY_)?LSApplicationCategoryType:\s*(\S+)", config)
        if not categories or any(value != CATEGORY for value in categories):
            self.flag("project.yml", "XcodeGen category differs from Lifestyle")

    def artifact(self, path):
        if path.is_dir() and path.suffix.lower() == ".app":
            self.directory(path, path)
            main_info = path / "Info.plist"
            if not main_info.is_symlink():
                self.info(main_info.read_bytes(), "Info.plist")
            profile = path / "embedded.mobileprovision"
            if profile.is_file() and not profile.is_symlink():
                self.provision(profile.read_bytes(), profile.name)
        elif path.is_file() and path.suffix.lower() == ".ipa":
            with zipfile.ZipFile(path) as archive:
                mains = [i for i in archive.infolist() if re.fullmatch(r"Payload/[^/]+\.app/Info\.plist", i.filename)]
                if len(mains) != 1:
                    raise ValueError("Expected one main app")
                seen = set()
                for item in archive.infolist():
                    name = item.filename
                    if item.is_dir():
                        continue
                    if name in seen:
                        self.flag(name, "Duplicate ZIP entry")
                    seen.add(name)
                    if name.startswith("/") or ".." in PurePosixPath(name).parts:
                        self.flag("IPA", "Unsafe archive path")
                        continue
                    if stat.S_ISLNK(item.external_attr >> 16):
                        self.flag(name, "Symbolic link requires manual inspection")
                        continue
                    with archive.open(item) as stream:
                        self.inspect(name, stream, item.file_size)
                    if name == mains[0].filename:
                        self.info(archive.read(item), name)
                    elif name.endswith("/embedded.mobileprovision"):
                        self.provision(archive.read(item), name)
            print(f"IPA file size: {path.stat().st_size / 1_000_000:.2f} MB")
        else:
            raise ValueError("Supply an exported .app directory or .ipa file")


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("artifact", nargs="?", type=Path, help="Exported .app or .ipa")
    parser.add_argument("--project", action="store_true", help="Inspect source resources and project configuration only")
    args = parser.parse_args()
    if args.project == (args.artifact is not None):
        parser.error("Choose either --project or an exported artifact")
    audit = Audit()
    try:
        if args.project:
            audit.project()
        else:
            audit.artifact(args.artifact)
    except (OSError, ValueError, KeyError, plistlib.InvalidFileException,
            zipfile.BadZipFile, subprocess.CalledProcessError) as error:
        print(f"Audit incomplete: {type(error).__name__}. Check the supplied artifact and configuration.", file=sys.stderr)
        return 2
    scope = "Source resources" if args.project else "Exported artifact contents"
    print(f"{scope}: {audit.files} files, {audit.bytes / 1_000_000:.2f} MB uncompressed")
    for name, reason in sorted(audit.findings):
        print(f"REVIEW {name}: {reason}")
    if audit.findings:
        print(f"{len(audit.findings)} finding(s). No files were changed.")
        return 1
    print("PASS: no findings within the resource audit scope. No files were changed.")
    return 0


if __name__ == "__main__":
    sys.exit(main())
