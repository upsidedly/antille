#!/usr/bin/env python3
# SPDX-License-Identifier: MPL-2.0
# Copyright (c) 2026 Matthew Williams

"""Focused native utility checks; no player transport, T3, or permission prompts."""
from pathlib import Path
import platform
import subprocess

root=Path(__file__).resolve().parents[1]
subprocess.run(["swift","build"],cwd=root,check=True)
binary_dir=Path(subprocess.check_output(["swift","build","--show-bin-path"],cwd=root,text=True).strip())
objects=[*binary_dir.joinpath("Antille.build").glob("*.o"),
         *(p for p in binary_dir.joinpath("AntilleApp.build").glob("*.o") if p.name!="AntilleApplication.swift.o")]
executable=root/"dist/.utility-checks"
executable.parent.mkdir(parents=True,exist_ok=True)
subprocess.run(["swiftc","-parse-as-library","-swift-version","6","-target",f"{platform.machine()}-apple-macosx14.0",
                "-I",str(binary_dir/"Modules"),str(root/"Tests/UtilityChecks/UtilityChecks.swift"),
                *map(str,objects),"-o",str(executable)],check=True)
subprocess.run([str(executable)],check=True)
