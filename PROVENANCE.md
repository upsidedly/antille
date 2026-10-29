# Implementation and reference provenance

Antille's Swift library, host app, command-line client, icon and test fixtures were authored for this project. The runtime includes no extracted island-app code, assets or binaries.

Reference investigation used independently observed behavior and public source to understand macOS overlay placement, native window lifetimes, compact layout, direct manipulation and media controls. References included [Boring Notch](https://github.com/TheBoredTeam/boring.notch), [DynamicNotchKit](https://github.com/MrKai77/DynamicNotchKit), [NotchDrop](https://github.com/Lakr233/NotchDrop) and shipped NotchNook/Alcove apps. Their names identify references, not dependencies or endorsements. Raw decompiler output and local investigation logs are excluded from the repository.

System integration uses public AppKit, SwiftUI, Carbon hotkeys, IOKit and Apple Events. Opening at login uses the user's macOS Login Items setting; no launch agent is bundled. Optional media artwork is obtained from permitted Spotify image hosts at runtime; it is not bundled. The app does not use a private MediaRemote framework.

Original code and contributions are released under the [Mozilla Public License 2.0](LICENSE). Copyright © 2026 Matthew Williams. Reference-app names and third-party trademarks remain their owners' property.
