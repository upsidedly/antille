// SPDX-License-Identifier: MPL-2.0
// Copyright (c) 2026 Matthew Williams

import AppKit
import Carbon
@testable import Antille

/// Inject transient native registration contention, retain the same hover,
/// then register an unused test key. No cursor movement or typed-key monitor.
@main enum HoverArrowRecoveryChecks {
    @MainActor static func main() {
        _=NSApplication.shared
        let shortcut=IslandHoverArrowShortcut(key:.down) {}
        defer {shortcut.close()}
        var now=100.0,attempts=0
        shortcut.uptime={now}
        shortcut.registerKey={_,id,reference in
            attempts+=1
            if attempts<=4 {return OSStatus(eventHotKeyExistsErr)}
            return RegisterEventHotKey(UInt32(kVK_F18),0,id,GetApplicationEventTarget(),0,&reference)
        }
        for _ in 0..<10 {shortcut.setEnabled(true);now+=0.5}
        guard shortcut.isRegistered,attempts>=5 else {
            FileHandle.standardError.write(Data("FAIL: Down stayed unavailable on the same hover after transient registration contention ended (attempts: \(attempts)).\n".utf8));exit(1)
        }
        shortcut.setEnabled(false)
        guard !shortcut.isRegistered else {exit(1)}
        print("PASS: same-hover arrow registration recovers from four transient failures and releases on leave.")
    }
}
