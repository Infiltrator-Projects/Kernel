#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-3.0-or-later
"""Fail closed on mutable CI actions and an untested Kernel source change."""
from pathlib import Path
import re

ROOT = Path(__file__).resolve().parents[1]
WORKFLOWS = ROOT / ".github" / "workflows"
ACTION = re.compile(
    r"^\s*(?:-\s*)?uses:\s*"
    r"(?P<repository>[A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+)"
    r"(?:/[^@\s#]+)?@(?P<ref>[^\s#]+)"
)
SHA = re.compile(r"[0-9a-f]{40}\Z")


def main() -> None:
    workflows = sorted(WORKFLOWS.glob("*.yml"))
    assert workflows, "No GitHub workflows found"
    for workflow in workflows:
        for lineno, line in enumerate(workflow.read_text().splitlines(), 1):
            match = ACTION.match(line)
            if match and not SHA.fullmatch(match["ref"]):
                raise AssertionError(
                    f"{workflow.relative_to(ROOT)}:{lineno}: mutable action "
                    f"reference {match['ref']!r}"
                )

    integration = (WORKFLOWS / "native-ext4-driver-qualification.yml").read_text()
    try:
        push = integration.split("on:\n  push:\n", 1)[1].split(
            "  workflow_dispatch:", 1
        )[0]
    except IndexError as exc:
        raise AssertionError("Kernel integration workflow must run on push") from exc
    assert "branches: [main]" in push, "Kernel integration main trigger missing"
    assert "paths:" not in push and "paths-ignore:" not in push, (
        "The EXT4 boot and driver test must not silently skip ordinary Kernel changes"
    )
    assert "python3 tests/verify-ci-contracts.py" in integration
    for required in ("tests/boot-ext4-root.sh", "tests/native-driver-qemu.sh",
                     "tests/native-dell-driver-aliases.sh",
                     "tests/firmware-ext4.sh", "infiltrator-filesystem-ext4.deb",
                     "infiltrator-boot.deb"):
        assert required in integration, f"Native release qualification is missing {required}"
    release = (WORKFLOWS / "release-run.yml").read_text()
    assert '"Native EXT4 boot and driver qualification"' in release
    assert "--prerelease" in release, "Physical hardware has not yet been qualified"
    assert "Qualify independent EXT2 against InfiltratorOS Kernel" not in release
    assert "Three-way Boot + InfiltratorFS + Kernel VM qualification" not in release
    print("KERNEL_CI_CONTRACT_PASS: immutable actions, full main integration coverage")


if __name__ == "__main__":
    main()
