#!/usr/bin/env python3
# SPDX-License-Identifier: MPL-2.0
# Copyright (c) 2026 Matthew Williams

from pathlib import Path
import argparse, plistlib, shutil, subprocess
root=Path(__file__).resolve().parents[1]
parser=argparse.ArgumentParser()
parser.add_argument("--release",action="store_true")
parser.add_argument("--fixture",action="store_true")
args=parser.parse_args()
configuration="release" if args.release else "debug"
subprocess.run(["swift","build","-c",configuration],cwd=root,check=True)
binary_dir=Path(subprocess.check_output(["swift","build","-c",configuration,"--show-bin-path"],cwd=root,text=True).strip())
bundle=root/("dist/AntilleFixture.app" if args.fixture else "dist/Antille.app")
(bundle/"Contents/MacOS").mkdir(parents=True,exist_ok=True)
(bundle/"Contents/Resources").mkdir(parents=True,exist_ok=True)
icon_tool=root/"dist/.make-icon"
subprocess.run(["swiftc","-parse-as-library",str(root/"scripts/make-icon.swift"),"-o",str(icon_tool)],cwd=root,check=True)
subprocess.run([str(icon_tool),str(root/"dist")],check=True)
shutil.copy2(root/"dist/AppIcon.icns",bundle/"Contents/Resources/AppIcon.icns")
docs_assets=root/"docs/assets";docs_assets.mkdir(parents=True,exist_ok=True)
shutil.copy2(root/"dist/Antille.iconset/icon_512x512@2x.png",docs_assets/"antille-icon.png")
temporary=bundle/"Contents/MacOS/Antille.new"
shutil.copy2(binary_dir/"AntilleApp",temporary)
temporary.replace(bundle/"Contents/MacOS/Antille")
info={"CFBundleIdentifier":"dev.upsided.antille","CFBundleName":"Antille","CFBundleDisplayName":"Antille","CFBundleExecutable":"Antille","CFBundleIconFile":"AppIcon","CFBundlePackageType":"APPL","CFBundleShortVersionString":"1.0.0","CFBundleVersion":"1","LSMinimumSystemVersion":"14.0","LSUIElement":True,"NSHighResolutionCapable":True}
info["NSAppleEventsUsageDescription"]="Antille displays playback and controls Spotify or Music when you use its music controls."
if args.fixture:
    info["CFBundleIdentifier"]+=".fixture"
    info["CFBundleName"]="Antille Fixture"
    info["CFBundleDisplayName"]="Antille Fixture"
with (bundle/"Contents/Info.plist").open("wb") as f: plistlib.dump(info,f)
cli=root/("dist/antille-fixture" if args.fixture else "dist/antille")
shutil.copy2(binary_dir/"antille",cli)
subprocess.run(["codesign","--force","--sign","-",str(bundle)],check=True)
print(bundle)
print(cli)
