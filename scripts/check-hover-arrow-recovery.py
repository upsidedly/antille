#!/usr/bin/env python3
# SPDX-License-Identifier: MPL-2.0
# Copyright (c) 2026 Matthew Williams

"""Focused native registration recovery, using an unused key rather than Down."""
from pathlib import Path
import platform
import subprocess
root=Path(__file__).resolve().parents[1]
subprocess.run(["swift","build"],cwd=root,check=True)
binary=Path(subprocess.check_output(["swift","build","--show-bin-path"],cwd=root,text=True).strip())
output=root/"dist/.hover-arrow-recovery-checks"
output.parent.mkdir(parents=True,exist_ok=True)
subprocess.run(["swiftc","-parse-as-library","-swift-version","6","-target",f"{platform.machine()}-apple-macosx14.0","-I",str(binary/"Modules"),str(root/"Tests/NativeFixtures/HoverArrowRecoveryChecks.swift"),*map(str,binary.joinpath("Antille.build").glob("*.o")),"-o",str(output)],check=True)
subprocess.run([str(output)],check=True,timeout=5)
