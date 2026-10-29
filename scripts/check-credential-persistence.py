#!/usr/bin/env python3
# SPDX-License-Identifier: MPL-2.0
# Copyright (c) 2026 Matthew Williams

"""Opt-in synthetic Keychain regression; never reads real credentials or allows UI."""
from pathlib import Path
import platform
import shutil
import subprocess
import tempfile
import uuid

root = Path(__file__).resolve().parents[1]
subprocess.run(["swift", "build", "--product", "AntilleChecks"], cwd=root, check=True)
binary_dir = Path(subprocess.check_output(["swift", "build", "--show-bin-path"], cwd=root, text=True).strip())
service = "dev.upsided.antille.credential-migration-check." + str(uuid.uuid4())
with tempfile.TemporaryDirectory(prefix="antille-credential-check-") as directory:
    directory = Path(directory)
    first, second = directory / "first-build", directory / "second-build"
    subprocess.run([
        "swiftc", "-parse-as-library", "-swift-version", "6",
        "-target", f"{platform.machine()}-apple-macosx14.0",
        "-I", str(binary_dir / "Modules"),
        str(root / "Tests/NativeFixtures/CredentialPersistenceFixture.swift"),
        *map(str, (binary_dir / "Antille.build").glob("*.o")), "-o", str(first),
    ], check=True)
    shutil.copy2(first, second)
    for binary, suffix in ((first, "first"), (second, "second")):
        subprocess.run(["codesign", "--force", "--sign", "-", "--identifier",
                        "dev.upsided.credential-check." + suffix, str(binary)], check=True)
    try:
        for binary, operation in ((first, "write"), (first, "read"),
                                  (second, "write"), (second, "read"), (first, "read")):
            subprocess.run([str(binary), operation, service], check=True, timeout=10)
    finally:
        for binary in (first, second):
            subprocess.run([str(binary), "delete", service], check=True, timeout=10)
print("PASS: separately signed builds retain their own protected entries and restore across processes, with synthetic data and no UI.")
