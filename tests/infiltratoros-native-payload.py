#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-3.0-or-later
"""Populate an isolated Format 0.19 image with canonical InfiltratorOS resources.

Only files from an exact pinned InfiltratorOS source commit are accepted.
The source image is never installed on the runner, and no fonts/icon binaries
are uploaded in CI artifacts. Every binary is verified both before import
and from the running InfiltratorOS kernel on each of two independent boots.
"""
from __future__ import annotations

import argparse
import hashlib
import io
from pathlib import Path, PurePosixPath
import subprocess
import tarfile

ICON_ARCHIVE_SHA256 = "8d55ccbe5f1eefe3800ab12578a641524742b9482410d95757317434523b342c"
OS_ARTWORK_SHA256 = "4820891225675ed9bb0bb1bb82e3680df4bbdccc736ce5d092b80e95e5d05978"
FONT_COUNT = 23
ICON_COUNT = 1233

# Native layout is defined in InfiltratorOS/scripts/build-deb.sh.
# Images is an additional home for the existing Plymouth artwork.
DIRECTORIES = (
    "/System", "/System/Commands", "/System/Libraries",
    "/System/Devices", "/System/Filesystems",
    "/System/Kernel", "/System/Kernel/Images", "/System/Kernel/Modules",
    "/System/Kernel/Filesystems", "/System/Kernel/Firmware",
    "/System/Boot", "/System/Resources",
    "/System/Resources/Calendars", "/System/Resources/Clocks",
    "/System/Resources/Documentation", "/System/Resources/Fonts",
    "/System/Resources/Icons", "/System/Resources/Images",
    "/System/Resources/Locales", "/System/Resources/Themes",
    "/System/Preferences", "/Programs", "/Users", "/Volumes",
    "/Temporary", "/boot",
)


def run(*argv: object) -> None:
    subprocess.run([str(arg) for arg in argv], check=True)


def verify(payload: bytes, sha256: str, label: str) -> None:
    if len(sha256) != 64 or any(c not in "0123456789abcdef" for c in sha256):
        raise ValueError(f"Invalid SHA256 for {label}")
    if hashlib.sha256(payload).hexdigest() != sha256:
        raise ValueError(f"Source SHA256 mismatch: {label}")


def rows(data: bytes, label: str) -> list[tuple[str, str]]:
    result: list[tuple[str, str]] = []
    for line in data.decode("utf-8").splitlines():
        fields = line.split("  ", 1)
        if len(fields) != 2:
            raise ValueError(f"Bad SHA256 manifest row: {label}: {line!r}")
        result.append((fields[0], fields[1]))
    return result


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    for field in ("image", "fs-tool", "os-source", "work"):
        parser.add_argument("--" + field, type=Path, required=True)
    args = parser.parse_args()
    source = args.os_source.resolve(strict=True)
    image = args.image.resolve(strict=True)
    tool = args.fs_tool.resolve(strict=True)
    work = args.work.resolve(strict=True)
    assert source.is_dir() and work.is_dir()
    fonts_dir = source / "assets/fonts"
    icons_dir = source / "assets/icons"

    # Source manifests are checked *before* writing the guest filesystem.
    font_data = (fonts_dir / "SHA256SUMS").read_bytes()
    font_rows = rows(font_data, "fonts")
    if len(font_rows) != FONT_COUNT or len(set(name for _, name in font_rows)) != FONT_COUNT:
        raise ValueError("Canonical InfiltratorOS font set must contain 23 unique files")
    fonts: list[tuple[str, bytes, str]] = []
    for digest, name in font_rows:
        if Path(name).name != name or not name.endswith(".ttf"):
            raise ValueError(f"Unsafe font name: {name}")
        payload = (fonts_dir / name).read_bytes()
        verify(payload, digest, name)
        fonts.append((name, payload, digest))

    parts_manifest = rows((icons_dir / "PART_SHA256SUMS").read_bytes(), "icon parts")
    if len(parts_manifest) != 10:
        raise ValueError("Expected precisely ten canonical icon archive parts")
    chunks = []
    for index, (digest, name) in enumerate(parts_manifest):
        if name != f"mercedes-icons-v1.part{index:02d}":
            raise ValueError(f"Icon archive part order or name mismatch: {name}")
        part = (icons_dir / name).read_bytes()
        verify(part, digest, name)
        chunks.append(part)
    archive_bytes = b"".join(chunks)
    verify(archive_bytes, ICON_ARCHIVE_SHA256, "complete icon archive")

    icons: list[tuple[str, bytes, str]] = []
    with tarfile.open(fileobj=io.BytesIO(archive_bytes), mode="r:xz") as archive:
        icon_manifest = archive.extractfile("SHA256SUMS")
        if icon_manifest is None:
            raise ValueError("Icon archive SHA256SUMS absent")
        icon_rows = rows(icon_manifest.read(), "icons")
        if len(icon_rows) != ICON_COUNT:
            raise ValueError("Canonical icon inventory must contain 1,233 entries")
        for digest, name in icon_rows:
            parts = PurePosixPath(name).parts
            if (len(parts) != 3 or parts[0] not in (
                    "adapter", "connect", "eco-coach", "finance",
                    "logbook", "remote-parking") or
                    parts[1] not in ("default", "night") or
                    not name.endswith((".png", ".webp")) or
                    any(p in (".", "..") for p in parts)):
                raise ValueError(f"Unsafe icon source path: {name}")
            flat = "-".join(parts)
            if not all(c.isascii() and (c.isalnum() or c in "-._") for c in flat):
                raise ValueError(f"Unsafe icon target: {flat}")
            entry = archive.extractfile("mercedes/" + name)
            if entry is None:
                raise ValueError(f"Missing source icon: {name}")
            payload = entry.read()
            verify(payload, digest, name)
            icons.append((flat, payload, digest))
    if len(set(flat for flat, _, _ in icons)) != ICON_COUNT:
        raise ValueError("Flattened canonical icon names collide")

    artwork = (source / "assets/infiltratoros.png").read_bytes()
    verify(artwork, OS_ARTWORK_SHA256, "InfiltratorOS artwork")
    resource_rows: list[tuple[str, str]] = []
    stage = work / "OS-Resources-Import"
    stage.mkdir(exist_ok=False)
    for directory in DIRECTORIES:
        run(tool, image, "mkdir", directory)

    def put_data(directory: str, name: str, data: bytes, digest: str) -> None:
        # A local temporary file avoids modifying the source-controlled assets.
        host = stage / name
        host.write_bytes(data)
        dest = directory + "/" + name
        run(tool, image, "put", host, dest)
        resource_rows.append((digest, dest.lstrip("/")))
        host.unlink()

    for name, data, digest in fonts:
        put_data("/System/Resources/Fonts", name, data, digest)
    print(f"INFS_OS_FONTS_IMPORTED:{len(fonts)}", flush=True)

    icon_manifest_out = []
    for index, (name, data, digest) in enumerate(icons, 1):
        put_data("/System/Resources/Icons", name, data, digest)
        icon_manifest_out.append((digest, name))
        if index % 128 == 0:
            print(f"INFS_OS_ICONS_IMPORTED:{index}", flush=True)
    print(f"INFS_OS_ICONS_IMPORTED:{len(icons)}", flush=True)
    put_data("/System/Resources/Images", "infiltratoros.png", artwork,
             OS_ARTWORK_SHA256)

    for name, pairs in (
        ("InfiltratorOS-fonts.sha256", font_rows),
        ("InfiltratorOS-icons.sha256", icon_manifest_out),
        ("InfiltratorOS-boot-resources.sha256", resource_rows),
    ):
        host = stage / name
        host.write_text("".join(f"{digest}  {filename}\n" for digest, filename in pairs))
        run(tool, image, "put", host, "/System/Resources/Documentation/" + name)
        host.unlink()

    if len(resource_rows) != FONT_COUNT + ICON_COUNT + 1:
        raise ValueError("Incorrect resource payload size")
    summary = (
        f"InfiltratorOS Format 0.19 native directory tree\n"
        f"directories={len(DIRECTORIES)}\n"
        f"fonts={FONT_COUNT}\nicons={ICON_COUNT}\nimages=1\n"
        f"verified_files={len(resource_rows)}\n"
        "every file sha256 verified on source and independently in guest\n"
    )
    (work / "os-resource-summary.txt").write_text(summary)
    print(summary, flush=True)
    print("INFS_OS_LAYOUT_AND_RESOURCE_IMPORT_PASS", flush=True)


if __name__ == "__main__":
    main()
