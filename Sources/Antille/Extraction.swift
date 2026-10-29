// SPDX-License-Identifier: MPL-2.0
// Copyright (c) 2026 Matthew Williams

import AppKit
import SwiftUI
import Observation

public enum IslandHeadHitTesting {
    public static func screenRect(_ local:CGRect,panel:CGRect)->CGRect {
        CGRect(x:panel.minX+local.minX,y:panel.maxY-local.maxY,width:local.width,height:local.height)
    }
    public static func nearest(to pointer:CGPoint,regions:[String:CGRect])->String? {
        regions.filter{!$0.value.isEmpty && $0.value.insetBy(dx:-5,dy:-4).contains(pointer)}.min {left,right in
            let a=hypot(pointer.x-left.value.midX,pointer.y-left.value.midY),b=hypot(pointer.x-right.value.midX,pointer.y-right.value.midY)
            return a==b ? left.key<right.key:a<b
        }?.key
    }
    public static func returnRegion(island:CGRect)->CGRect {
        CGRect(x:island.minX-6,y:island.minY-10,width:island.width+12,height:island.height+10)
    }
}

private final class ExtractionPanel:NSPanel {
    override var canBecomeKey:Bool {false}
    override var canBecomeMain:Bool {false}
}
@MainActor @Observable private final class ExtractionMotion {
    var scale=0.38
    var angle=0.0
}
@MainActor final class IslandExtractionController {
    private weak var controller:IslandController?
    private let store:IslandStore
    private weak var panel:NSPanel?
    private var regions:[String:(activityID:String,rect:CGRect,compact:Bool)]=[:]
    private var picked:(activity:IslandActivity,start:CGPoint,last:CGPoint,time:TimeInterval)?
    private var ghosts:[String:ExtractionPanel]=[:]
    private var motions:[String:ExtractionMotion]=[:]
    private var deadlines:[String:Task<Void,Never>]=[:]
    var onChange:((Set<String>)->Void)?
    var isDragging:Bool {picked.map{ghosts[$0.activity.id] != nil} ?? false}
    init(store:IslandStore,controller:IslandController,panel:NSPanel) {self.store=store;self.controller=controller;self.panel=panel}
    func register(_ id:String,region:CGRect,regionID:String) {
        let key=id+"::"+regionID
        if region.isEmpty {regions.removeValue(forKey:key)} else {regions[key]=(id,region,regionID=="compact" || regionID.hasPrefix("compact:"))}
    }
    func hoveredActivity(at pointer:CGPoint)->IslandActivity? {
        guard let panel else{return nil}
        let eligible=Dictionary(uniqueKeysWithValues:store.visibleActivities.filter{!$0.stale && ghosts[$0.id]==nil && $0.actions.contains(where:{$0.id=="detach"})}.map{($0.id,$0)})
        let frames=regions.filter {_,value in
            guard let activity=eligible[value.activityID] else{return false}
            return !value.compact || activity.showsInCompact != false
        }.mapValues{IslandHeadHitTesting.screenRect($0.rect,panel:panel.frame)}
        guard let key=IslandHeadHitTesting.nearest(to:pointer,regions:frames),let id=regions[key]?.activityID else{return nil}
        return eligible[id]
    }
    func handle(_ event:NSEvent,panel:NSPanel) {
        guard event.window===panel || (picked != nil && (event.type == .leftMouseDragged || event.type == .leftMouseUp)) else{return}
        guard let pointer=IslandPointerLocation.screenPoint(for:event) else{return}
        switch event.type {
        case .leftMouseDown:
            guard !event.modifierFlags.contains(.control) else{return}
            guard let item=hoveredActivity(at:pointer) else{return}
            picked=(item,pointer,pointer,ProcessInfo.processInfo.systemUptime)
        case .leftMouseDragged:
            guard var current=picked else{return}
            let now=ProcessInfo.processInfo.systemUptime
            if ghosts[current.activity.id]==nil {
                guard hypot(pointer.x-current.start.x,pointer.y-current.start.y)>4 else{return}
                makeGhost(current.activity,at:pointer)
                controller?.collapse()
            }
            let velocity=(pointer.x-current.last.x)/max(0.008,now-current.time)
            if let motion=motions[current.activity.id] {
                let reduced=NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
                withAnimation(reduced ? nil:.interactiveSpring(response:0.22,dampingFraction:0.6)) {motion.angle=reduced ? 0:max(-16,min(16,-velocity*0.014))}
            }
            ghosts[current.activity.id]?.setFrameOrigin(CGPoint(x:pointer.x-43,y:pointer.y-71.5))
            current.last=pointer;current.time=now;picked=current
            if let controller {controller.setMagnet(IslandMagnet.strength(pointer:pointer,target:controller.dropTarget),at:pointer)}
        case .leftMouseUp:
            guard let current=picked else{return};picked=nil
            guard let ghost=ghosts[current.activity.id] else{return}
            controller?.setMagnet(0)
            if controller?.extractionReturnTarget.contains(pointer)==true {
                complete(current.activity.id);controller?.pulse();return
            }
            let screen=NSScreen.screens.first(where:{$0.frame.contains(pointer)}) ?? NSScreen.main
            let frame=screen?.visibleFrame ?? CGRect(x:0,y:0,width:1440,height:900)
            let origin=CGPoint(x:min(frame.maxX-ghost.frame.width,max(frame.minX,ghost.frame.minX)),y:min(frame.maxY-ghost.frame.height,max(frame.minY,ghost.frame.minY)))
            ghost.setFrameOrigin(origin)
            deadlines[current.activity.id]=Task { [weak self] in
                do {try await Task.sleep(for:.seconds(5))} catch{return}
                guard let self,ghosts[current.activity.id] != nil else{return}
                complete(current.activity.id)
                store.errorMessage="The source did not complete the move. Try again when it reconnects."
            }
            store.perform(IslandAction(id:"detach",title:"Move to desktop",position:IslandPoint(origin)),on:current.activity)
        default:break
        }
    }
    private func makeGhost(_ activity:IslandActivity,at point:CGPoint) {
        let motion=ExtractionMotion()
        let ghost=ExtractionPanel(contentRect:CGRect(x:point.x-43,y:point.y-71.5,width:86,height:116),styleMask:[.borderless,.nonactivatingPanel],backing:.buffered,defer:false)
        ghost.backgroundColor = .clear;ghost.isOpaque=false;ghost.hasShadow=false;ghost.ignoresMouseEvents=true
        ghost.animationBehavior = .none
        ghost.level=NSWindow.Level(rawValue:NSWindow.Level.mainMenu.rawValue+4)
        ghost.collectionBehavior=[.canJoinAllSpaces,.fullScreenAuxiliary,.stationary,.ignoresCycle]
        ghost.contentView=NSHostingView(rootView:ExtractionPreview(icon:controller?.compactView(activity) ?? AnyView(IslandActivityIcon(activity)),motion:motion).accessibilityHidden(true))
        ghosts[activity.id]=ghost;motions[activity.id]=motion;onChange?(Set(ghosts.keys))
        ghost.orderFrontRegardless()
        withAnimation(NSWorkspace.shared.accessibilityDisplayShouldReduceMotion ? nil:.spring(response:0.28,dampingFraction:0.72)) {motion.scale=1}
    }
    func complete(_ id:String) {
        deadlines.removeValue(forKey:id)?.cancel()
        ghosts.removeValue(forKey:id)?.close();motions.removeValue(forKey:id)
        onChange?(Set(ghosts.keys))
    }
    func cancelAll() {picked=nil;for id in Array(ghosts.keys) {complete(id)};regions=[:]}
}
private struct ExtractionPreview:View {
    let icon:AnyView
    let motion:ExtractionMotion
    var body:some View {
        VStack(spacing:0) {
            icon.frame(width:74,height:89)
                .scaleEffect(motion.scale).rotationEffect(.degrees(motion.angle),anchor:.top)
        }.frame(width:86,height:116,alignment:.top)
    }
}
