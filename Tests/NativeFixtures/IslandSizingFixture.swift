// SPDX-License-Identifier: MPL-2.0
// Copyright (c) 2026 Matthew Williams

import Antille
import AppKit
import Foundation

/// Real AppKit/SwiftUI sizing regression, with only synthetic local content.
/// No host socket, credentials, conversations or saved profile changes.
@main enum IslandSizingFixture {
    @MainActor static func main() {
        _=NSApplication.shared
        NSApp.setActivationPolicy(.accessory)
        Task { @MainActor in
            let store=IslandStore(profile:IslandProfile.presets[0])
            store.profile.openOnHover=false
            let controller=IslandController(store:store)
            defer {controller.close()}
            do {
                controller.show()
                try await Task.sleep(for:.milliseconds(100))
                for revision in 1...16 {
                    let count=revision%6+1
                    for index in 0..<count {
                        let blocks=[
                            IslandBlock(id:"heading",kind:.text,text:"A sample agent needs your answer"),
                            IslandBlock(id:"output",kind:.text,text:String(repeating:"Sample streamed output. ",count:revision*3),lineLimit:9,markdown:true,textIdentity:"sample"),
                            IslandBlock(id:"answer",kind:.textInput,text:"Reply…"),
                            IslandBlock(id:"send",kind:.button,text:"Send",actionID:"send")
                        ]
                        try store.upsert(IslandActivity(producerID:"sizing-fixture",activityID:String(index),revision:revision,title:"Sample \(index)",actions:[IslandAction(id:"send",title:"Send")],content:blocks,actionsInMenu:true,requiresClickToExpand:true,preferredExpandedHeight:520))
                    }
                    controller.refresh()
                    if revision%2==0 {controller.expand()} else {controller.collapse()}
                    try await Task.sleep(for:.milliseconds(120))
                    guard let window=NSApp.windows.first(where:{$0.title=="Antille island"}),let content=window.contentView else {throw FixtureFailure.missingWindow}
                    content.layoutSubtreeIfNeeded()
                    guard window.frame.width.isFinite,window.frame.height.isFinite,content.bounds.size==window.contentLayoutRect.size else {throw FixtureFailure.invalidLayout}
                }
                controller.close()
                print("PASS: native island survives streamed content, new heads, expansion and collapse with a window-owned content size.")
                exit(0)
            } catch {
                controller.close()
                FileHandle.standardError.write(Data("FAIL: island sizing fixture: \(error)\n".utf8))
                exit(1)
            }
        }
        NSApp.run()
    }
    enum FixtureFailure:Error {case missingWindow,invalidLayout}
}
