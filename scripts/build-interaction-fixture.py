#!/usr/bin/env python3
# SPDX-License-Identifier: MPL-2.0
# Copyright (c) 2026 Matthew Williams

"""Build the isolated real-island interaction/design fixture for native QA."""
from pathlib import Path
import platform
import plistlib
import subprocess

root=Path(__file__).resolve().parents[1]
subprocess.run(["swift","build"],cwd=root,check=True)
binary_dir=Path(subprocess.check_output(["swift","build","--show-bin-path"],cwd=root,text=True).strip())
objects=[*binary_dir.joinpath("Antille.build").glob("*.o"),
         *(p for p in binary_dir.joinpath("AntilleApp.build").glob("*.o") if p.name!="AntilleApplication.swift.o")]
bundle=root/"dist/AntilleInteractionFixture.app"
executable=bundle/"Contents/MacOS/InteractionFixture"
executable.parent.mkdir(parents=True,exist_ok=True)
subprocess.run(["swiftc","-parse-as-library","-swift-version","6","-target",f"{platform.machine()}-apple-macosx14.0",
                "-I",str(binary_dir/"Modules"),str(root/"Tests/NativeFixtures/IslandInteractionFixture.swift"),
                *map(str,objects),"-o",str(executable)],check=True)
info={"CFBundleIdentifier":"dev.upsided.antille.interaction.fixture","CFBundleName":"Antille Interaction Fixture",
      "CFBundleExecutable":"InteractionFixture","CFBundlePackageType":"APPL","LSMinimumSystemVersion":"14.0","NSHighResolutionCapable":True}
with (bundle/"Contents/Info.plist").open("wb") as output:plistlib.dump(info,output)
subprocess.run(["codesign","--force","--sign","-",str(bundle)],check=True)
print(bundle)
