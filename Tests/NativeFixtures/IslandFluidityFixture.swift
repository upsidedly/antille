// SPDX-License-Identifier: MPL-2.0
// Copyright (c) 2026 Matthew Williams

@testable import Antille
import AppKit
import SwiftUI
@testable import AntilleApp

/// Drives the real floating surface with local samples. No host, credentials,
/// players, T3 connection or change to the user's system preferences.
@main struct IslandFluidityFixture:App {
    var body:some Scene {
        Window("Isolated island fluidity check",id:"fluidity") {
            Text("Sample section transitions").padding(20).task {await Self.runChecks()}
        }.defaultSize(width:280,height:90)
    }
    @MainActor static func runChecks() async {
        let name="dev.upsided.antille.fluidity.\(UUID().uuidString)",prefs=UserDefaults(suiteName:name)!
        defer {prefs.removePersistentDomain(forName:name)}
        let utilities=UtilityController(fixture:true,defaults:prefs),store=IslandStore(profile:IslandProfile.presets[0])
        utilities.setNote("CARPE DIEM!!!")
        utilities.updated={try? store.replace(producerID:UtilityController.producer,with:$0)}
        utilities.start();defer{utilities.stop()}
        let icon:(IslandActivity)->AnyView={activity in
            activity.producerID==UtilityController.producer ? AnyView(UtilityCompactIcon(activity:activity,utilities:utilities)):AnyView(IslandActivityIcon(activity))
        }
        let controller=IslandController(store:store,compact:icon,expanded:{AnyView(IslandDefaultExpanded(store:store,icon:icon,content:{activity in
            activity.producerID==UtilityController.producer ? AnyView(UtilityIslandContent(activityID:activity.activityID,utilities:utilities)):nil
        }))})
        defer {controller.close()}
        do {
            let hitViolations=try await compactHitViolations()
            if !hitViolations.isEmpty {throw Failure.violations(hitViolations)}
            let menuViolations=try await compactMenuViolations()
            if !menuViolations.isEmpty {throw Failure.violations(menuViolations)}
            for index in 0..<16 {
                try store.upsert(IslandActivity(producerID:"sample",activityID:String(index),title:"Sample agent \(index)",attention:index==0 ? .needsAttention:.none,symbol:"leaf",content:[
                    IslandBlock(id:"output",kind:.text,text:String(repeating:"**Sample output.** This is an isolated transition check.\n\n",count:30),lineLimit:8,markdown:true),
                    IslandBlock(id:"question",kind:.text,text:"Which sample approach should this agent use?"),
                    IslandBlock(id:"answer",kind:.textInput,text:"Reply…"),
                    IslandBlock(id:"submit",kind:.button,text:"Send answer",actionID:"send")
                ],actionsInMenu:true,requiresClickToExpand:true,preferredExpandedHeight:520,showsInCompact:index<4))
            }
            controller.show()
            let selections=["sample::0","local.utilities::note","local.utilities::music","local.utilities::timer","sample::1","local.utilities::note"]
            for selected in selections {store.selectedID=selected;controller.expand();controller.refresh();try await Task.sleep(for:.milliseconds(350))}
            var hitPasses=0,refreshes=0,measurements=0,resizes=0
            var resizeDifferences=Set<String>()
            controller.diagnostics={event in switch event {
                case .hitTest:hitPasses+=1;case .refresh:refreshes+=1;case .measuredContent:measurements+=1
                case let .containerResize(from,to):resizes+=1;if resizeDifferences.count<3 {resizeDifferences.insert("\(from) → \(to)")}
            }}
            var exposed=Set<String>(),samples=0,gaps:[Double]=[],previous=ProcessInfo.processInfo.systemUptime,maxScrollViews=0
            var violations:[String]=[],canvas:CGRect?,changedCanvas=Set<String>(),reflowing=Set<String>()
            var historicalKey:IslandContentKey?
            for selected in selections {
                store.selectedID=selected;controller.expand();controller.refresh()
                if historicalKey==nil {historicalKey=controller.expandedContentKey}
                var viewportSizes=Set<String>()
                for _ in 0..<18 {
                    try await Task.sleep(for:.milliseconds(16))
                    let now=ProcessInfo.processInfo.systemUptime;gaps.append(now-previous);previous=now
                    guard let window=NSApp.windows.first(where:{$0.title=="Antille island"}),let root=window.contentView,
                          window.frame.height<850,window.frame.width<1000 else {throw Failure.invalidWindow}
                    let scrolls=descendants(root).compactMap{$0 as? NSScrollView};maxScrollViews=max(maxScrollViews,scrolls.count)
                    if canvas==nil {canvas=window.frame}
                    else if canvas != window.frame {changedCanvas.insert(selected)}
                    if let outer=scrolls.first {
                        viewportSizes.insert("\(Int(outer.contentView.bounds.width.rounded()))×\(Int(outer.contentView.bounds.height.rounded()))")
                    }
                    for scroll in scrolls {
                        for (axis,scroller) in [("horizontal",scroll.horizontalScroller),("vertical",scroll.verticalScroller)] {
                            if let scroller,!scroller.isHiddenOrHasHiddenAncestor,scroller.alphaValue>0.01,!scroller.visibleRect.isEmpty {
                                exposed.insert(axis+" (style \(scroller.scrollerStyle.rawValue))")
                            }
                        }
                    }
                    samples+=1
                }
                if viewportSizes.count>3 {reflowing.insert("\(selected) (\(viewportSizes.count) viewport sizes)")}
            }
            controller.diagnostics=nil
            if let window=NSApp.windows.first(where:{$0.title=="Antille island"}) {
                let inside=CGPoint(x:window.frame.width/2,y:window.frame.height-80),outside=CGPoint(x:1,y:window.frame.height-80)
                if let click=NSEvent.mouseEvent(with:.leftMouseDown,location:inside,modifierFlags:[],timestamp:ProcessInfo.processInfo.systemUptime,windowNumber:window.windowNumber,context:nil,eventNumber:1,clickCount:1,pressure:1) {
                    controller.dismissOutsideClick(click)
                    if !store.presentation.isExpanded {violations.append("a valid local input click was dismissed using stale cursor coordinates")}
                }
                controller.expand()
                if let click=NSEvent.mouseEvent(with:.leftMouseDown,location:outside,modifierFlags:[],timestamp:ProcessInfo.processInfo.systemUptime,windowNumber:window.windowNumber,context:nil,eventNumber:2,clickCount:1,pressure:1) {
                    controller.dismissOutsideClick(click)
                    if store.presentation != .collapsed {violations.append("a transparent-canvas outside click did not dismiss using its actual event coordinates")}
                }
                controller.expand()
                if let activation=NSEvent.mouseEvent(with:.leftMouseDown,location:CGPoint(x:-100,y:-100),modifierFlags:[],timestamp:ProcessInfo.processInfo.systemUptime,windowNumber:window.windowNumber,context:nil,eventNumber:4,clickCount:1,pressure:1) {
                    controller.dismissOutsideClick(activation)
                    if !store.presentation.isExpanded {violations.append("an out-of-window local activation event dismissed keyboard input")}
                }
                controller.expand()
                let screenInside=window.convertPoint(toScreen:inside)
                if let click=NSEvent.mouseEvent(with:.leftMouseDown,location:screenInside,modifierFlags:[],timestamp:ProcessInfo.processInfo.systemUptime,windowNumber:0,context:nil,eventNumber:3,clickCount:1,pressure:1) {
                    if IslandPointerLocation.screenPoint(for:click) != screenInside {violations.append("windowless mouse coordinates did not remain in screen space")}
                    controller.dismissOutsideClick(click)
                    if !store.presentation.isExpanded {violations.append("a windowless inside click was dismissed")}
                }
                if let click=NSEvent.mouseEvent(with:.leftMouseDown,location:CGPoint(x:-100,y:-100),modifierFlags:[],timestamp:ProcessInfo.processInfo.systemUptime,windowNumber:0,context:nil,eventNumber:5,clickCount:1,pressure:1) {
                    controller.dismissOutsideClick(click)
                    if store.presentation != .collapsed {violations.append("a real windowless outside click was mistaken for a local activation artifact")}
                }
                controller.expand()
                if let panel=window as? NSPanel {violations+=try extractionViolations(store:store,controller:controller,panel:panel)}
            }
            let heightBefore=controller.visualHeight
            if let historicalKey {controller.measureContent(IslandContentMeasurement(key:historicalKey,height:900))}
            var wrongWidth=controller.expandedContentKey;wrongWidth.width+=1
            controller.measureContent(IslandContentMeasurement(key:wrongWidth,height:900))
            controller.measureContent(IslandContentMeasurement(key:controller.expandedContentKey,height:.nan))
            if controller.visualHeight != heightBefore {violations.append("a stale/invalid measurement resized the selected section")}
            for _ in 0..<12 {controller.dismiss();controller.expand();try await Task.sleep(for:.milliseconds(5))}
            controller.dismiss();try await Task.sleep(for:.milliseconds(90))
            if controller.contentPhase != .hidden || store.presentation != .collapsed {violations.append("a stale reveal reopened collapsed content")}
            controller.expand();try await Task.sleep(for:.milliseconds(90))
            if controller.contentPhase != .visible {violations.append("latest reveal did not become visible")}
            controller.setDropInteraction(sessionID:"sample-drop",active:true,revision:3)
            if let item=store.visibleActivities.first {controller.activateCompact(item)}
            if !controller.dropMode || store.presentation.isExpanded {violations.append("incoming drop opened ordinary content")}
            controller.setDropInteraction(sessionID:"sample-drop",active:false,revision:4)
            controller.setDropInteraction(sessionID:"sample-drop",active:true,revision:3)
            if controller.dropMode {violations.append("stale drop revision revived the drop target")}
            controller.dismiss();controller.reduceMotionOverride=true;controller.expand();controller.pulse();controller.setMagnet(1)
            if controller.contentPhase != .visible || controller.liquidImpulse != 0 {violations.append("reduced-motion policy did not reveal immediately without deformation")}
            controller.reduceMotionOverride=nil
            controller.togglePin()
            NSApp.windows.first(where:{$0.title=="Antille island"})?.cancelOperation(nil)
            try await Task.sleep(for:.milliseconds(30))
            if store.presentation != .collapsed {violations.append("Escape did not dismiss a pinned island")}
            controller.close();controller.show()
            try await Task.sleep(for:.milliseconds(50))
            if NSApp.windows.filter({$0.title=="Antille island" && $0.isVisible}).count != 1 {violations.append("recreated island has a missing or duplicate native window")}
            let ordered=gaps.sorted(),gap=String(format:"%.1f",(ordered.last ?? 0)*1000),p95=String(format:"%.1f",ordered[min(ordered.count-1,Int(Double(ordered.count)*0.95))]*1000)
            print("SAMPLES: \(samples), native scroll views: \(maxScrollViews), warm main-run-loop sample gap p95 \(p95) ms, max \(gap) ms")
            print("WORK: hit-test passes \(hitPasses), refreshes \(refreshes), accepted measurements \(measurements), native resizes \(resizes)")
            if !resizeDifferences.isEmpty {print("RESIZES: \(resizeDifferences.sorted())")}
            guard maxScrollViews>0 else {throw Failure.noNativeScrollViews}
            if !exposed.isEmpty {violations.append("exposed native scrollers: \(exposed.sorted())")}
            if !changedCanvas.isEmpty {violations.append("native canvas resizes between sections: \(changedCanvas.sorted())")}
            if !reflowing.isEmpty {violations.append("content reflows through animated viewport sizes: \(reflowing.sorted())")}
            try store.upsert(IslandActivity(producerID:"sample",activityID:"short",title:"Short question",symbol:"leaf",content:[
                IslandBlock(id:"output",kind:.text,text:"**Sample output.** This is a short sample.",markdown:true),
                IslandBlock(id:"answer",kind:.textInput,text:"Reply…")
            ],actionsInMenu:true,requiresClickToExpand:true,preferredExpandedHeight:520))
            store.selectedID="sample::short";controller.expand()
            try await Task.sleep(for:.milliseconds(350))
            for width in [300.0,600.0,380.0] {
                store.profile.expandedWidth=width;store.profile.compactLimit=1;store.profile.wingWidth=36
                utilities.showNoteInCompact(false);controller.refresh()
                try await Task.sleep(for:.milliseconds(400))
                if controller.visualHeight>360 {violations.append("short content retains maximum height after changing width to \(width): \(controller.visualHeight)")}
            }
            if resizes>0 {violations.append("redundant native frame writes during stable section switches: \(resizes)")}
            if hitPasses>samples*4+60 {violations.append("unbatched region updates overrun the hit-testing work budget: \(hitPasses)")}
            guard violations.isEmpty else {throw Failure.violations(violations)}
            print("PASS: no scrollbar flashes or viewport reflow; stable native canvas; bounded hit-testing work; stale measurement/reveal/drop rejection; reduced-motion policy; pinned Escape; single-window recreation and short-content sizing after width changes.")
            exit(0)
        } catch {FileHandle.standardError.write(Data("FAIL: \(error)\n".utf8));exit(1)}
    }
    @MainActor static func descendants(_ view:NSView)->[NSView] {[view]+view.subviews.flatMap{descendants($0)}}
    @MainActor static func compactMenuViolations() async throws ->[String] {
        let store=IslandStore();store.profile.openOnHover=false
        let source=IslandActivity(producerID:"menu-sample",activityID:"head",title:"Menu source",actions:[IslandAction(id:"detach",title:"To desktop")])
        try store.upsert(source)
        let controller=IslandController(store:store);defer{controller.close()}
        controller.show();try await Task.sleep(for:.milliseconds(300))
        guard let window=NSApp.windows.first(where:{$0.title=="Antille island"}),let root=window.contentView,
              let anchor=descendants(root).compactMap({$0 as? IslandContextMenuView}).first else{return ["compact context-menu anchor unavailable"]}
        if anchor.hitTest(CGPoint(x:1,y:1)) != nil {return ["context-menu overlay captures normal pointer/left-click events"]}
        let probe=CompactMenuProbe(store:store,controller:controller,window:window,source:source)
        probe.start();anchor.showMenu();probe.stop()
        try await Task.sleep(for:.milliseconds(100))
        var violations=probe.violations
        if !probe.completed {violations.append("compact context menu closed before background-update checks finished")}
        if controller.layoutActivities.map(\.id) != ["menu-sample::replacement"] {violations.append("compact roster did not apply the deferred refresh after menu close")}
        if violations.isEmpty {print("PASS: real compact menu retains item/source identity through hover, motion and roster replacement; action resolves the latest source; pending roster applies on close; overlay passes ordinary events through.")}
        return violations
    }
    @MainActor static func compactHitViolations() async throws ->[String] {
        let store=IslandStore();store.profile.compactLimit=6;store.profile.openOnHover=false
        try store.upsert(IslandActivity(producerID:"hit-sample",activityID:"0",title:"Head 0",actions:[IslandAction(id:"detach",title:"Move to desktop")]))
        try store.upsert(IslandActivity(producerID:"hit-sample",activityID:"note",title:"Note",priority:60,compactLabel:"CARPE DIEM!!!"))
        let controller=IslandController(store:store);defer{controller.close()}
        controller.show()
        var violations:[String]=[]
        for (step,count) in [1,2,3,4,5,6,5,4,3,2,1].enumerated() {
            var items=(0..<count).map {index in IslandActivity(producerID:"hit-sample",activityID:String(index),revision:step+1,title:"Head \(index)",priority:index,actions:[IslandAction(id:"detach",title:"Move to desktop")])}
            items.append(IslandActivity(producerID:"hit-sample",activityID:"note",revision:step+1,title:"Note",priority:60,compactLabel:"CARPE DIEM!!!"))
            try store.replace(producerID:"hit-sample",with:items);controller.refresh()
            try await Task.sleep(for:.milliseconds(300))
            let compact=controller.compactSlots,leading=min((compact.count+1)/2,compact.filter{$0.compactLabel==nil}.count)
            let widths=controller.geometry.compactSlotWidths(profile:store.profile,activityCount:controller.layoutActivities.count,preferred:compact.map(\.preferredCompactWidth),leadingSlotCount:leading)
            for (index,item) in compact.enumerated() where item.compactLabel==nil {
                guard let point=controller.geometry.landingSlot(index:index,profile:store.profile,activityCount:controller.layoutActivities.count,slotWidths:widths,leadingSlotCount:leading) else{continue}
                if controller.extractableActivity(at:point)?.id != item.id {violations.append("\(index<leading ? "left":"right") head \(item.activityID) is not extractable after compact membership changes to \(count)")}
            }
        }
        if violations.isEmpty {print("PASS: actual left/right compact hit areas survive initial layout and 11 membership/wing changes beside the saved note.")}
        return violations
    }
    @MainActor static func extractionViolations(store:IslandStore,controller:IslandController,panel:NSPanel) throws ->[String] {
        let activity=IslandActivity(producerID:"drag-sample",activityID:"head",title:"Sample extraction",actions:[IslandAction(id:"detach",title:"To desktop")])
        try store.upsert(activity)
        let extraction=IslandExtractionController(store:store,controller:controller,panel:panel)
        let previous=store.actionHandler
        var moves:[IslandAction]=[]
        store.actionHandler={item,action in if item.id==activity.id,action.id=="detach" {moves.append(action)}}
        defer {extraction.cancelAll();store.actionHandler=previous;store.remove(producerID:activity.producerID,activityID:activity.activityID)}
        let region=CGRect(x:200,y:8,width:28,height:28)
        extraction.register(activity.id,region:region,regionID:"compact")
        let start=CGPoint(x:region.midX,y:panel.frame.height-region.midY)
        let end=panel.convertPoint(toScreen:CGPoint(x:panel.frame.width+80,y:panel.frame.height-220))
        guard let down=NSEvent.mouseEvent(with:.leftMouseDown,location:start,modifierFlags:[],timestamp:ProcessInfo.processInfo.systemUptime,windowNumber:panel.windowNumber,context:nil,eventNumber:10,clickCount:1,pressure:1),
              let drag=NSEvent.mouseEvent(with:.leftMouseDragged,location:end,modifierFlags:[],timestamp:ProcessInfo.processInfo.systemUptime,windowNumber:0,context:nil,eventNumber:11,clickCount:1,pressure:1),
              let up=NSEvent.mouseEvent(with:.leftMouseUp,location:end,modifierFlags:[],timestamp:ProcessInfo.processInfo.systemUptime,windowNumber:0,context:nil,eventNumber:12,clickCount:1,pressure:0) else {return ["native extraction events could not be constructed"]}
        extraction.handle(down,panel:panel);extraction.handle(drag,panel:panel)
        guard extraction.isDragging else{return ["a local grab followed by windowless drag failed to start extraction"]}
        extraction.handle(up,panel:panel)
        guard moves.count==1,let position=moves.first?.position,abs(position.x-end.x)<100,abs(position.y-end.y)<120 else {return ["windowless release did not hand off the head once at its actual release point"]}
        extraction.complete(activity.id)
        return []
    }
    enum Failure:Error {case invalidWindow,noNativeScrollViews,violations([String])}
}

@MainActor private final class CompactMenuProbe:NSObject {
    let store:IslandStore
    let controller:IslandController
    let window:NSWindow
    let source:IslandActivity
    var violations:[String]=[]
    var completed=false
    private var menu:NSMenu?
    private var timers:[Timer]=[]
    init(store:IslandStore,controller:IslandController,window:NSWindow,source:IslandActivity) {
        self.store=store;self.controller=controller;self.window=window;self.source=source
    }
    func start() {
        NotificationCenter.default.addObserver(self,selector:#selector(began(_:)),name:NSMenu.didBeginTrackingNotification,object:nil)
    }
    func stop() {
        NotificationCenter.default.removeObserver(self)
        for timer in timers {timer.invalidate()}
        store.actionHandler=nil
    }
    private func after(_ delay:Double,_ action:@escaping @MainActor ()->Void) {
        let timer=Timer(timeInterval:delay,repeats:false) {_ in MainActor.assumeIsolated {action()}}
        timers.append(timer);RunLoop.main.add(timer,forMode:.common);RunLoop.main.add(timer,forMode:.eventTracking)
    }
    @objc private func began(_ notice:Notification) {
        guard menu==nil,let menu=notice.object as? NSMenu else{return};self.menu=menu
        let originalItems=menu.items,originalFrame=window.frame
        after(0.2) { [self] in
            do {
                var latest=source;latest.revision=2;latest.title="Updated source";latest.actions=[IslandAction(id:"detach",title:"Latest desktop action")]
                try store.upsert(latest)
                var chosen:String?
                store.actionHandler={_,action in chosen=action.title}
                menu.performActionForItem(at:0)
                if chosen != "Latest desktop action" {violations.append("compact menu action used a stale source action")}
                try store.replace(producerID:source.producerID,with:[IslandActivity(producerID:source.producerID,activityID:"replacement",title:"New head")])
                controller.hover(false);controller.pulse();controller.setMagnet(1);controller.refresh()
            } catch {violations.append("sample menu update failed: \(error)")}
            after(0.25) { [self] in
                if menu.items.count != originalItems.count || !zip(menu.items,originalItems).allSatisfy({$0===$1}) {violations.append("compact context menu replaced its native items")}
                if controller.layoutActivities.map(\.id) != [source.id] || window.frame != originalFrame {violations.append("compact menu source reflowed or disappeared during background refresh")}
                completed=true;menu.cancelTrackingWithoutAnimation()
            }
        }
    }
}
