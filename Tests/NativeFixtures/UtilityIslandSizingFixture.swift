// SPDX-License-Identifier: MPL-2.0
// Copyright (c) 2026 Matthew Williams

import Antille
import AppKit
import SwiftUI
@testable import AntilleApp

/// Exercise the real panel's animated consumer-height changes. This is an
/// isolated producer; it does not start a host, read credentials or contact T3.
@main struct UtilityIslandSizingFixture:App {
    var body:some Scene {
        Window("Isolated utility sizing check",id:"sizing") {
            Text("Sample utility sizing check").padding(20).task {await Self.runChecks()}
        }.defaultSize(width:280,height:90)
    }
    @MainActor static func runChecks() async {
            let name="dev.upsided.antille.sizing.\(UUID().uuidString)",prefs=UserDefaults(suiteName:name)!
            defer {prefs.removePersistentDomain(forName:name)}
            let utilities=UtilityController(fixture:true,defaults:prefs),store=IslandStore(profile:IslandProfile.presets[0])
            utilities.updated={try? store.replace(producerID:UtilityController.producer,with:$0)}
            utilities.setNote("CARPE DIEM!!!");utilities.start();defer{utilities.stop()}
            let icon:(IslandActivity)->AnyView={activity in
                activity.producerID==UtilityController.producer ? AnyView(UtilityCompactIcon(activity:activity,utilities:utilities)):AnyView(IslandActivityIcon(activity))
            }
            let controller=IslandController(store:store,compact:icon,expanded:{AnyView(IslandDefaultExpanded(store:store,icon:icon,content:{activity in
                activity.producerID==UtilityController.producer ? AnyView(UtilityIslandContent(activityID:activity.activityID,utilities:utilities)):nil
            }))})
            defer {controller.close()}
            do {
                for index in 0..<7 {
                    try store.upsert(IslandActivity(producerID:"sample",activityID:String(index),title:"Sample agent \(index)",attention:index==0 ? .needsAttention:.none,symbol:"leaf",actions:[IslandAction(id:"detach",title:"To desktop")],content:[
                        IslandBlock(id:"output",kind:.text,text:String(repeating:"Sample streamed output. ",count:30),lineLimit:8,markdown:true),
                        IslandBlock(id:"question",kind:.text,text:"Which sample approach should this agent use?"),
                        IslandBlock(id:"answer",kind:.textInput,text:"Reply…"),
                        IslandBlock(id:"submit",kind:.button,text:"Send answer",actionID:"send")
                    ],actionsInMenu:true,requiresClickToExpand:true,preferredExpandedHeight:520,showsInCompact:index<4))
                }
                controller.show()
                for width in [380.0,300.0] {
                    store.profile.expandedWidth=width
                    for cycle in 0..<3 {
                        for selected in ["sample::0","local.utilities::note","local.utilities::power","local.utilities::timer","local.utilities::music"] {
                            store.selectedID=selected;controller.expand();controller.refresh()
                            try await Task.sleep(for:.milliseconds(220))
                            guard let window=NSApp.windows.first(where:{$0.title=="Antille island"}),let content=window.contentView,
                                  window.frame.height<850,window.frame.width<900,content.bounds.size==window.contentLayoutRect.size else {throw SizingFailure.invalidLayout}
                            content.layoutSubtreeIfNeeded()
                            if selected.hasSuffix("timer") {utilities.startTimer(seconds:90);utilities.pauseTimer();utilities.cancelTimer()}
                        }
                        controller.collapse();try await Task.sleep(for:.milliseconds(120))
                        print("PASS: utility island width \(Int(width)), selection cycle \(cycle+1)")
                    }
                }
                controller.close();print("PASS: real floating panel retains bounded window-owned sizing across questions and all utility cards.");exit(0)
            } catch {controller.close();FileHandle.standardError.write(Data("FAIL: \(error)\n".utf8));exit(1)}
    }
    enum SizingFailure:Error {case invalidLayout}
}
