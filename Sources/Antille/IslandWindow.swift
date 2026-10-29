// SPDX-License-Identifier: MPL-2.0
// Copyright (c) 2026 Matthew Williams

import AppKit
import SwiftUI
import Observation
import QuartzCore

private final class IslandPanel: NSPanel {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }
    override func cancelOperation(_ sender: Any?) { onEscape?() }
    var onEscape: (() -> Void)?
}
private struct ExpandedContentHeight:PreferenceKey {
    static let defaultValue:IslandContentMeasurement?=nil
    static func reduce(value:inout IslandContentMeasurement?,nextValue:()->IslandContentMeasurement?) {value=nextValue() ?? value}
}
public struct IslandShellShape: Shape {
    public var radius: CGFloat
    public var pull: CGFloat
    public var focus: CGFloat
    public var animatableData:AnimatablePair<CGFloat,AnimatablePair<CGFloat,CGFloat>> {
        get {AnimatablePair(radius,AnimatablePair(pull,focus))}
        set {radius=newValue.first;pull=newValue.second.first;focus=newValue.second.second}
    }
    public init(radius: CGFloat,pull:CGFloat=0,focus:CGFloat=0) {self.radius=radius;self.pull=pull;self.focus=focus}
    public func path(in rect: CGRect) -> Path {
        let r=min(max(4,radius),rect.height/2)
        let depth=max(-0.15,min(1.25,pull))*22
        let bottom=rect.height-max(0,depth)
        let left=r*1.38,right=rect.width-r*1.38
        let center=min(right-1,max(left+1,rect.midX+focus*rect.width*0.27))
        var p=Path()
        p.move(to:.zero); p.addLine(to:CGPoint(x:rect.width,y:0))
        p.addQuadCurve(to:CGPoint(x:rect.width-r*0.38,y:r),control:CGPoint(x:rect.width-r*0.38,y:0))
        p.addLine(to:CGPoint(x:rect.width-r*0.38,y:bottom-r))
        p.addQuadCurve(to:CGPoint(x:right,y:bottom),control:CGPoint(x:rect.width-r*0.38,y:bottom))
        p.addCurve(to:CGPoint(x:center,y:bottom+depth),
                   control1:CGPoint(x:right-(right-center)*0.45,y:bottom),
                   control2:CGPoint(x:center+(right-center)*0.45,y:bottom+depth))
        p.addCurve(to:CGPoint(x:left,y:bottom),
                   control1:CGPoint(x:center-(center-left)*0.45,y:bottom+depth),
                   control2:CGPoint(x:left+(center-left)*0.45,y:bottom))
        p.addQuadCurve(to:CGPoint(x:r*0.38,y:bottom-r),control:CGPoint(x:r*0.38,y:bottom))
        p.addLine(to:CGPoint(x:r*0.38,y:r))
        p.addQuadCurve(to:.zero,control:CGPoint(x:r*0.38,y:0))
        p.closeSubpath()
        return p
    }
}
@MainActor @Observable
public final class IslandController {
    public let store: IslandStore
    public private(set) var visualWidth:Double = 184
    public private(set) var visualHeight:Double = 36
    public private(set) var visualCenterOffset:Double = 0
    public private(set) var visualRadius:Double = 13
    public private(set) var liquidImpulse:Double = 0
    public private(set) var liquidFocus:Double = 0
    public private(set) var hoverInvitation:Double = 0
    public private(set) var extractingIDs:Set<String>=[]
    public private(set) var dropMode=false
    public private(set) var geometry=IslandGeometry(screen:CGRect(x:0,y:0,width:1440,height:900),cutoutWidth:0,topInset:0)
    private(set) var contentPhase=IslandContentPhase.unmounted
    var reduceMotionOverride:Bool?
    fileprivate var reducesMotion:Bool {reduceMotionOverride ?? NSWorkspace.shared.accessibilityDisplayShouldReduceMotion}
    @ObservationIgnored private var panel: IslandPanel?
    @ObservationIgnored var diagnostics:((IslandDiagnosticEvent)->Void)?
    @ObservationIgnored private var hoverTask: Task<Void,Never>?
    @ObservationIgnored private var closeTask: Task<Void,Never>?
    @ObservationIgnored private var observers: [NSObjectProtocol] = []
    @ObservationIgnored private var eventMonitors:[Any]=[]
    @ObservationIgnored private var hitRect=CGRect.zero
    @ObservationIgnored private var lastExpanded:Bool?
    @ObservationIgnored private var lastInside:Bool?
    @ObservationIgnored private var isEnabled=false
    @ObservationIgnored private var impulseTask:Task<Void,Never>?
    @ObservationIgnored private var extraction:IslandExtractionController?
    @ObservationIgnored private var hoverArrow:IslandHoverArrowShortcut?
    @ObservationIgnored private var pointerTask:Task<Void,Never>?
    @ObservationIgnored private var hitTestingTask:Task<Void,Never>?
    @ObservationIgnored private var dropSessions:[String:(revision:Int,active:Bool,expires:TimeInterval)]=[:]
    @ObservationIgnored private var hoverArmed=true
    private var contentHeights:[IslandContentKey:Double]=[:]
    private var compactOrder:[String]=[]
    @ObservationIgnored private var contentTask:Task<Void,Never>?
    @ObservationIgnored private var contentGeneration:UInt64=0
    @ObservationIgnored private var contentExpanded=false
    @ObservationIgnored private var manualExpansion=false
    @ObservationIgnored private var menuTracking=false
    private var contextMenuActivities:[IslandActivity]?
    private var landings:[String:IslandActivity]=[:]
    @ObservationIgnored private var landingTasks:[String:Task<Void,Never>]=[:]
    @ObservationIgnored private let compact: ((IslandActivity)->AnyView)?
    @ObservationIgnored private let expanded: (() -> AnyView)?
    public init(store: IslandStore, compact: ((IslandActivity)->AnyView)? = nil, expanded: (() -> AnyView)? = nil) {
        self.store=store; self.compact=compact; self.expanded=expanded
        compactOrder=store.compactActivities.map(\.id)
    }
    public func show() {
        isEnabled=true
        if pointerTask==nil {
            pointerTask=Task { @MainActor [weak self] in
                while !Task.isCancelled {
                    do {try await Task.sleep(for:.milliseconds(50))} catch{return}
                    guard let self,self.isEnabled else{return}
                    self.updateHitTesting()
                }
            }
        }
        if panel != nil { refresh(); return }
        updateGeometry()
        let panel=IslandPanel(contentRect:containerFrame(),
                            styleMask:[.borderless,.nonactivatingPanel],backing:.buffered,defer:false)
        panel.backgroundColor = .clear; panel.isOpaque=false; panel.hasShadow=false
        panel.animationBehavior = .none
        panel.isFloatingPanel=true; panel.hidesOnDeactivate=false;panel.acceptsMouseMovedEvents=true; panel.isMovable=false
        panel.level=NSWindow.Level(rawValue:NSWindow.Level.mainMenu.rawValue+3)
        panel.collectionBehavior=[.canJoinAllSpaces,.stationary,.ignoresCycle]
        if store.profile.showInFullscreen { panel.collectionBehavior.insert(.fullScreenAuxiliary) }
        panel.title="Antille island"
        panel.setAccessibilityLabel("Antille island")
        self.panel=panel
        panel.onEscape={ [weak self] in self?.dismiss() }
        let extraction=IslandExtractionController(store:store,controller:self,panel:panel)
        extraction.onChange={ [weak self] ids in self?.extractingIDs=ids }
        self.extraction=extraction
        // Initial onAppear measurements can arrive during hosting-view setup.
        store.activityRegionHandler={ [weak self] id,rect,regionID in self?.registerActivity(id,rect:rect,regionID:regionID) }
        let content=NSHostingView(rootView:IslandSurface(controller:self))
        // The panel owns the transparent container's size. Animated SwiftUI
        // content must not feed intrinsic/min/max constraints back into it.
        content.sizingOptions=[]
        content.autoresizingMask=[.width,.height]
        // Keep the hosting view out of NSWindow's root-content role. SwiftUI's
        // animated-window sizing can otherwise resize the panel despite empty
        // sizingOptions, competing with the controller during card changes.
        let container=NSView(frame:CGRect(origin:.zero,size:panel.frame.size))
        content.frame=container.bounds
        container.addSubview(content)
        panel.contentView=container
        hoverArrow=IslandHoverArrowShortcut(key:.down,isEligible:{ [weak self] in
            guard let self else{return false}
            return self.extractableActivity(at:NSEvent.mouseLocation) != nil
        }) { [weak self] in self?.quickDetachHovered() }
        if let monitor=NSEvent.addGlobalMonitorForEvents(matching:[.mouseMoved,.leftMouseDragged,.leftMouseUp,.leftMouseDown,.rightMouseDown],handler:{ [weak self] event in
            let click=event.type == .leftMouseDown || event.type == .rightMouseDown
            MainActor.assumeIsolated {
                if click {self?.dismissOutsideClick(event)}
                if let self,let panel=self.panel {self.extraction?.handle(event,panel:panel);self.updateHitTesting()}
            }
        }) { eventMonitors.append(monitor) }
        if let monitor=NSEvent.addLocalMonitorForEvents(matching:[.mouseMoved,.leftMouseDown,.rightMouseDown,.leftMouseDragged,.leftMouseUp],handler:{ [weak self] event in
            if let self,let panel=self.panel {
                if event.type == .leftMouseDown || event.type == .rightMouseDown {self.dismissOutsideClick(event)}
                self.extraction?.handle(event,panel:panel);self.updateHitTesting()
            };return event
        }) { eventMonitors.append(monitor) }
        observers.append(NotificationCenter.default.addObserver(forName:NSMenu.didBeginTrackingNotification,object:nil,queue:.main) { [weak self] _ in
            MainActor.assumeIsolated {self?.menuTracking=true}
        })
        observers.append(NotificationCenter.default.addObserver(forName:NSMenu.didEndTrackingNotification,object:nil,queue:.main) { [weak self] _ in
            MainActor.assumeIsolated {self?.menuTracking=false}
        })
        observers.append(NotificationCenter.default.addObserver(forName:NSApplication.didChangeScreenParametersNotification,object:nil,queue:.main) { [weak self] _ in
            Task { @MainActor in self?.refresh() }
        })
        observers.append(NSWorkspace.shared.notificationCenter.addObserver(forName:NSWorkspace.didWakeNotification,object:nil,queue:.main) { [weak self] _ in
            Task { @MainActor in self?.refresh() }
        })
        refresh()
    }
    public func hide() {
        isEnabled=false;pointerTask?.cancel();pointerTask=nil;hoverArrow?.setEnabled(false)
        resetPresentationWork();extraction?.cancelAll();panel?.orderOut(nil)
    }
    public func close() {
        isEnabled=false
        resetPresentationWork()
        pointerTask?.cancel();pointerTask=nil
        hoverArrow?.close();hoverArrow=nil
        extraction?.cancelAll();extraction=nil
        store.activityRegionHandler=nil
        for task in landingTasks.values {task.cancel()};landingTasks=[:];landings=[:]
        hoverTask?.cancel(); closeTask?.cancel();impulseTask?.cancel()
        for monitor in eventMonitors {NSEvent.removeMonitor(monitor)};eventMonitors=[]
        for token in observers { NotificationCenter.default.removeObserver(token); NSWorkspace.shared.notificationCenter.removeObserver(token) }
        observers=[]; panel?.close(); panel=nil
    }
    private func resetPresentationWork() {
        contentGeneration &+= 1;contentTask?.cancel();contentTask=nil;contentExpanded=false;contentPhase = .unmounted
        hoverTask?.cancel();closeTask?.cancel();impulseTask?.cancel()
        hitTestingTask?.cancel();hitTestingTask=nil
        lastExpanded=nil;lastInside=nil;hitRect = .zero;hoverArmed=true;manualExpansion=false
        liquidImpulse=0;hoverInvitation=0;dropSessions=[:];dropMode=false
        contextMenuActivities=nil;menuTracking=false
    }
    private func updateContentPresentation(_ expanded:Bool) {
        guard expanded != contentExpanded else{return}
        contentExpanded=expanded;contentGeneration &+= 1;contentTask?.cancel();contentTask=nil
        let generation=contentGeneration
        if expanded {
            if contentPhase == .unmounted {contentPhase = .hidden}
            if reducesMotion {contentPhase = .visible;return}
            contentTask=Task { @MainActor [weak self] in
                do {try await Task.sleep(for:.milliseconds(55))} catch{return}
                guard let self,self.contentGeneration==generation,self.isEnabled,self.contentExpanded else{return}
                withAnimation(.easeOut(duration:0.14)) {self.contentPhase = .visible}
                self.contentTask=nil
            }
        } else {
            withAnimation(reducesMotion ? nil:.easeOut(duration:0.1)) {if contentPhase.isMounted {contentPhase = .hidden}}
            panel?.makeFirstResponder(nil);if panel?.isKeyWindow==true {panel?.resignKey()}
        }
    }
    public func expand(fromHover:Bool=false) {
        hoverTask?.cancel();closeTask?.cancel();hoverInvitation=0
        manualExpansion = !fromHover && (!store.profile.openOnHover || store.visibleActivities.contains{$0.requiresClickToExpand==true})
        if store.presentation != .pinned {store.presentation = .expanded};refresh()
    }
    public func activateCompact(_ activity:IslandActivity) {
        guard !dropMode else{return}
        if store.presentation.isExpanded && store.selectedID==activity.id {
            dismiss()
        } else {store.selectedID=activity.id;expand()}
    }
    public func collapse() {
        guard store.presentation != .pinned else { return }
        dismiss()
    }
    /// Explicit dismissal (Escape, close or repeated selection) also releases a pin.
    public func dismiss() {
        hoverTask?.cancel(); closeTask?.cancel();hoverArmed=false
        manualExpansion=false
        store.presentation = .collapsed; refresh()
    }
    public func togglePin() {
        store.presentation = store.presentation == .pinned ? .expanded : .pinned; refresh()
    }
    public func hover(_ inside: Bool) {
        guard contextMenuActivities==nil else{return}
        let invitation=inside && !dropMode && !store.presentation.isExpanded && (store.visibleActivities.contains{$0.requiresClickToExpand==true} || !store.profile.openOnHover)
        let amount=invitation ? 1.0:0.0
        if hoverInvitation != amount {withAnimation(reducesMotion ? nil:.easeOut(duration:0.18)) {hoverInvitation=amount}}
        if !inside {hoverArmed=true}
        if dropMode || !hoverArmed || extraction?.isDragging==true {lastInside=inside;hoverTask?.cancel();closeTask?.cancel();return}
        guard lastInside != inside else{return};lastInside=inside
        hoverTask?.cancel(); closeTask?.cancel()
        if inside {
            guard store.profile.openOnHover,!store.visibleActivities.contains(where:{$0.requiresClickToExpand==true}),!store.presentation.isExpanded else { return }
            hoverTask=Task { [weak self] in
                guard let self else { return }
                do { try await Task.sleep(for:.seconds(store.profile.hoverDelay)); try Task.checkCancellation();if !store.visibleActivities.contains(where:{$0.requiresClickToExpand==true}) {expand(fromHover:true)} } catch {}
            }
        } else if store.presentation != .pinned && !manualExpansion {
            closeTask=Task { [weak self] in
                guard let self else { return }
                do { try await Task.sleep(for:.seconds(store.profile.dismissDelay)); try Task.checkCancellation(); collapse() } catch {}
            }
        }
    }
    func dismissOutsideClick(_ event:NSEvent) {
        guard manualExpansion,store.presentation == .expanded,!menuTracking,contextMenuActivities==nil else{return}
        // Local activation artifacts can fall beyond their claimed window.
        // Real transparent-canvas clicks remain inside these window bounds.
        if let window=event.window,!CGRect(origin:.zero,size:window.frame.size).contains(event.locationInWindow) {return}
        let region=visibleBounds
        // Local delivery already identifies the window and the click's actual
        // position. The global cursor may still describe the preceding move.
        guard let point=IslandPointerLocation.screenPoint(for:event) else{return}
        if !region.contains(point) {collapse()}
    }
    private func resolvedGeometry()->IslandGeometry {
        let selected=NSScreen.screens.first {
            String(($0.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber)?.uint32Value ?? 0)==store.profile.displayID
        } ?? NSScreen.main ?? NSScreen.screens.first
        guard let screen=selected else {return geometry}
        let left=screen.auxiliaryTopLeftArea; let right=screen.auxiliaryTopRightArea
        let cutout:Double
        if let left,let right { cutout=max(0,right.minX-left.maxX) } else { cutout=0 }
        return IslandGeometry(screen:screen.frame,cutoutWidth:cutout,topInset:screen.safeAreaInsets.top)
    }
    private func updateGeometry() {let current=resolvedGeometry();if geometry != current {geometry=current}}
    private func containerFrame()->CGRect {
        var canvas=store.profile;canvas.expandedHeight=max(640,canvas.expandedHeight)
        let expanded=geometry.frame(profile:canvas,expanded:true,activityCount:layoutActivities.count,slotWidths:compactWidths,leadingSlotCount:compactLeadingCount)
        let width=max(expanded.width+abs(expanded.midX-geometry.screen.midX)*2,geometry.cutoutWidth+store.profile.wingWidth*2)+80
        let height=expanded.height+64
        return CGRect(x:geometry.screen.midX-width/2,y:geometry.screen.maxY-height,width:width,height:height).integral
    }
    private var expandedProfile:IslandProfile {
        var profile=store.profile
        let activity=store.visibleActivities.first(where:{$0.id==store.selectedID}) ?? store.visibleActivities.first
        if let height=activity?.preferredExpandedHeight {profile.expandedHeight=max(profile.expandedHeight,min(640,max(160,height)))}
        return profile
    }
    private var selectedActivity:IslandActivity? {store.visibleActivities.first(where:{$0.id==store.selectedID}) ?? store.visibleActivities.first}
    fileprivate var expandedHeightLimit:Double {expandedProfile.expandedHeight}
    var expandedContentKey:IslandContentKey {
        let frame=geometry.frame(profile:expandedProfile,expanded:true,activityCount:layoutActivities.count,slotWidths:compactWidths,leadingSlotCount:compactLeadingCount)
        return IslandContentKey(activityID:selectedActivity?.id ?? "",width:(frame.width*2).rounded()/2)
    }
    private var expandedTargetFrame:CGRect {
        var frame=geometry.frame(profile:expandedProfile,expanded:true,activityCount:layoutActivities.count,slotWidths:compactWidths,leadingSlotCount:compactLeadingCount)
        if let content=contentHeights[expandedContentKey] {frame.size.height=min(frame.height,max(geometry.headerHeight+130,geometry.headerHeight+28+content));frame.origin.y=geometry.screen.maxY-frame.height}
        return frame
    }
    var expandedContentSize:CGSize {
        let frame=expandedTargetFrame
        return CGSize(width:frame.width,height:max(1,frame.height-geometry.headerHeight-28))
    }
    private var visibleBounds:CGRect {
        if let panel,!hitRect.isEmpty {return IslandHeadHitTesting.screenRect(hitRect,panel:panel.frame)}
        return CGRect(x:geometry.screen.midX+visualCenterOffset-visualWidth/2,y:geometry.screen.maxY-visualHeight,width:visualWidth,height:visualHeight)
    }
    fileprivate func updateHitRect(_ rect:CGRect) {
        hitRect=rect;scheduleHitTesting()
    }
    private func scheduleHitTesting() {
        guard isEnabled,hitTestingTask==nil else{return}
        // One layout can publish a region for every head. Resolve the pointer
        // once after that batch, retaining immediate mouse-event handling.
        hitTestingTask=Task { @MainActor [weak self] in
            await Task.yield()
            guard !Task.isCancelled,let self,self.isEnabled else{return}
            self.hitTestingTask=nil;self.updateHitTesting()
        }
    }
    private func updateHitTesting() {
        diagnostics?(.hitTest)
        guard let panel,isEnabled else{return}
        guard panel.isVisible else {hoverArrow?.setEnabled(false);return}
        if menuTracking || contextMenuActivities != nil {hoverArrow?.setEnabled(false);return}
        updateDropMode()
        if extraction?.isDragging==true {hoverArrow?.setEnabled(false);panel.ignoresMouseEvents=false;return}
        let pointer=NSEvent.mouseLocation
        let region=visibleBounds
        let inside=region.contains(pointer)
        hoverArrow?.setEnabled(inside && extractableActivity(at:pointer) != nil)
        if panel.ignoresMouseEvents != !inside {panel.ignoresMouseEvents = !inside}
        // Ignore unused transparent window area; hover follows only the visible island.
        hover(inside)
    }
    private func quickDetachHovered() {
        guard let activity=extractableActivity(at:NSEvent.mouseLocation),let action=activity.actions.first(where:{$0.id=="detach"}) else{return}
        hoverArrow?.setEnabled(false);collapse();store.perform(action,on:activity)
    }
    func extractableActivity(at pointer:CGPoint)->IslandActivity? {
        guard isEnabled,panel?.isVisible==true,!menuTracking,contextMenuActivities==nil,!dropMode,extraction?.isDragging != true,visibleBounds.contains(pointer) else{return nil}
        return extraction?.hoveredActivity(at:pointer)
    }
    public var dropTarget:CGRect {
        // Resolve even before show(): a producer may be using another process's host.
        let current=resolvedGeometry()
        return CGRect(x:current.screen.midX-max(140,current.cutoutWidth/2+80),y:current.screen.maxY-105,width:max(280,current.cutoutWidth+160),height:125)
    }
    public var extractionReturnTarget:CGRect {
        IslandHeadHitTesting.returnRegion(island:CGRect(x:visibleBounds.minX,y:geometry.screen.maxY-geometry.headerHeight,width:visibleBounds.width,height:geometry.headerHeight))
    }
    public func completeExtraction(activityID:String) {extraction?.complete(activityID)}
    public var layoutActivities:[IslandActivity] {
        if let contextMenuActivities {return contextMenuActivities}
        let current=store.compactActivities,ids=Set(current.map(\.id))
        let pending=landings.values.filter{!ids.contains($0.id) && !store.profile.hiddenProducers.contains($0.producerID)}
        let order=Dictionary(uniqueKeysWithValues:compactOrder.enumerated().map{($0.element,$0.offset)})
        return (current+pending).sorted {left,right in
            if left.attention.rank != right.attention.rank {return left.attention.rank>right.attention.rank}
            if left.priority != right.priority {return left.priority>right.priority}
            if let a=order[left.id],let b=order[right.id] {return a<b}
            if order[left.id] != nil {return true};if order[right.id] != nil {return false}
            return IslandStore.precedes(left,right)
        }
    }
    private func reconcileCompactOrder() {
        let current=store.compactActivities,ids=Set(current.map(\.id))
        let pending=landings.values.filter{!ids.contains($0.id) && !store.profile.hiddenProducers.contains($0.producerID)}.sorted(by:IslandStore.precedes)
        let all=current+pending,eligible=Set(all.map(\.id)),retained=compactOrder.filter{eligible.contains($0)},known=Set(retained)
        let next=retained+all.filter{!known.contains($0.id)}.map(\.id)
        if compactOrder != next {compactOrder=next}
    }
    fileprivate func beginContextMenu() {
        guard contextMenuActivities==nil else{return}
        contextMenuActivities=layoutActivities;hoverTask?.cancel();closeTask?.cancel();hoverArrow?.setEnabled(false)
    }
    fileprivate func endContextMenu() {
        contextMenuActivities=nil;refresh()
    }
    public var compactSlots:[IslandActivity] {
        let admitted=Array(layoutActivities.prefix(store.profile.compactLimit))
        // Text sits on the trailing wing; admission still respects attention.
        return admitted.filter{$0.compactLabel==nil}+admitted.filter{$0.compactLabel != nil}
    }
    fileprivate var compactLeadingCount:Int {min((compactSlots.count+1)/2,compactSlots.filter{$0.compactLabel==nil}.count)}
    private var compactWidths:[Double] {geometry.compactSlotWidths(profile:store.profile,activityCount:layoutActivities.count,preferred:compactSlots.map(\.preferredCompactWidth),leadingSlotCount:compactLeadingCount)}
    fileprivate func compactWidth(for item:IslandActivity)->Double {
        guard let index=compactSlots.firstIndex(where:{$0.id==item.id}),index<compactWidths.count else{return 28}
        return compactWidths[index]
    }
    public func isReserved(_ id:String)->Bool {landings[id] != nil && !store.compactActivities.contains(where:{$0.id==id})}
    public func reserveLanding(_ activity:IslandActivity)->CGPoint {
        landings[activity.id]=activity
        landingTasks.removeValue(forKey:activity.id)?.cancel()
        landingTasks[activity.id]=Task { [weak self] in
            do {try await Task.sleep(for:.seconds(2))} catch{return}
            guard let self else{return};landings.removeValue(forKey:activity.id);landingTasks.removeValue(forKey:activity.id);refresh()
        }
        refresh()
        let current=resolvedGeometry()
        let items=layoutActivities
        let index=compactSlots.firstIndex(where:{$0.id==activity.id}) ?? compactSlots.count
        return current.landingSlot(index:index,profile:store.profile,activityCount:items.count,slotWidths:compactWidths,leadingSlotCount:compactLeadingCount) ?? CGPoint(x:current.screen.midX,y:current.screen.maxY-current.headerHeight/2)
    }
    public func setDropInteraction(sessionID:String,active:Bool,revision:Int) {
        if let previous=dropSessions[sessionID],previous.revision>revision {return}
        dropSessions[sessionID]=(revision,active,ProcessInfo.processInfo.systemUptime+3)
        updateDropMode()
    }
    private func updateDropMode() {
        let now=ProcessInfo.processInfo.systemUptime
        let active=dropSessions.values.contains{$0.active && $0.expires>now} || extraction?.isDragging==true
        guard active != dropMode else{return}
        dropMode=active
        hoverTask?.cancel();closeTask?.cancel()
        if active {
            hoverArmed=false
            if store.presentation != .pinned {store.presentation = .collapsed}
        }
        refresh()
    }
    fileprivate func registerActivity(_ id:String,rect:CGRect,regionID:String="compact") {
        extraction?.register(id,region:rect,regionID:regionID)
        scheduleHitTesting()
    }
    func measureContent(_ measurement:IslandContentMeasurement) {
        let height=measurement.height,key=measurement.key
        guard key==expandedContentKey,height.isFinite,height>0,abs((contentHeights[key] ?? 0)-height)>2 else{return}
        if contentHeights.count>=64,contentHeights[key]==nil {contentHeights=[:]}
        contentHeights[key]=height
        diagnostics?(.measuredContent)
        if store.presentation.isExpanded && !dropMode {refresh()}
    }
    public func setMagnet(_ amount:Double,at point:CGPoint?=nil) {
        guard !reducesMotion,contextMenuActivities==nil else{return}
        impulseTask?.cancel()
        let pointer=point ?? NSEvent.mouseLocation
        let focus=max(-1,min(1,(pointer.x-resolvedGeometry().screen.midX)/max(90,visualWidth*0.4)))
        withAnimation(.interactiveSpring(response:0.27,dampingFraction:0.72)) {
            liquidImpulse=max(0,min(1,amount))*0.85
            if amount>0 {liquidFocus=focus}
        }
    }
    public func pulse() {
        ripple(1)
    }
    private func ripple(_ amount:Double) {
        guard !reducesMotion,contextMenuActivities==nil else{return}
        impulseTask?.cancel()
        withAnimation(.interpolatingSpring(stiffness:470,damping:22)) {liquidImpulse=amount}
        impulseTask=Task { [weak self] in
            do {try await Task.sleep(for:.milliseconds(110))} catch{return}
            guard let self else{return}
            withAnimation(.interpolatingSpring(stiffness:220,damping:18)) {liquidImpulse=0}
        }
    }
    public func refresh() {
        diagnostics?(.refresh)
        reconcileCompactOrder()
        guard let panel,isEnabled else { return }
        guard contextMenuActivities==nil else{return}
        updateGeometry()
        let expanded=store.presentation.isExpanded && !dropMode
        updateContentPresentation(expanded)
        if store.presentation == .hidden || (store.profile.hideWhenEmpty && store.visibleActivities.isEmpty && layoutActivities.isEmpty && !dropMode) {
            hoverArrow?.setEnabled(false);panel.orderOut(nil); return
        }
        var behavior:NSWindow.CollectionBehavior=[.canJoinAllSpaces,.stationary,.ignoresCycle]
        if store.profile.showInFullscreen {behavior.insert(.fullScreenAuxiliary)}
        if panel.collectionBehavior != behavior {panel.collectionBehavior=behavior}
        let container=containerFrame();if panel.frame != container {diagnostics?(.containerResize(panel.frame,container));panel.setFrame(container,display:true)}
        // A native resize can synchronously deliver a fresh content measurement.
        // Resolve the shell afterward so this refresh cannot overwrite it with
        // a maximum-height target captured before the resize.
        var target=expanded ? expandedTargetFrame:geometry.frame(profile:store.profile,expanded:false,activityCount:layoutActivities.count,slotWidths:compactWidths,leadingSlotCount:compactLeadingCount)
        if dropMode {
            target.size.width=min(geometry.screen.width-24,target.width+32)
            target.origin.x=min(geometry.screen.maxX-12-target.width,max(geometry.screen.minX+12,target.minX))
            target.size.height+=28;target.origin.y=geometry.screen.maxY-target.height
        }
        if lastExpanded==nil {
            visualWidth=target.width;visualHeight=target.height;visualCenterOffset=target.midX-geometry.screen.midX;visualRadius=expanded ? store.profile.cornerRadius:13
        } else if visualWidth != target.width || visualHeight != target.height || visualCenterOffset != target.midX-geometry.screen.midX {
            withAnimation(reducesMotion ? nil:.spring(response:0.38,dampingFraction:0.86)) {
                visualWidth=target.width;visualCenterOffset=target.midX-geometry.screen.midX;visualRadius=expanded ? store.profile.cornerRadius:13
                visualHeight=target.height
            }
        }
        lastExpanded=expanded
        if !panel.isVisible {panel.orderFrontRegardless()}
        updateHitTesting()
    }
    func compactView(_ item: IslandActivity) -> AnyView {
        if let label=item.compactLabel {
            return AnyView(Text(label).font(.system(size:10,weight:.semibold)).lineLimit(1).truncationMode(.tail)
                .accessibilityLabel(item.title+": "+label))
        }
        return AnyView((compact?(item) ?? AnyView(IslandActivityIcon(item))).accessibilityElement(children:.ignore).accessibilityLabel(item.title))
    }
    fileprivate func expandedView() -> AnyView {
        expanded?() ?? AnyView(IslandDefaultExpanded(store:store,icon:compact))
    }
}
private struct IslandSurface: View {
    let controller: IslandController
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    private var store: IslandStore { controller.store }
    private var expanded:Bool {store.presentation.isExpanded && !controller.dropMode}
    private var reduced:Bool {reduceMotion || controller.reducesMotion}
    var body: some View {
        VStack(spacing:0) {
            compactHeader
            expandedPane
        }
        .frame(width:controller.visualWidth+controller.liquidImpulse*28+controller.hoverInvitation*8,height:controller.visualHeight+controller.liquidImpulse*26+controller.hoverInvitation*2,alignment:.top)
        .background(.black,in:IslandShellShape(radius:controller.visualRadius+controller.liquidImpulse*4,pull:controller.liquidImpulse,focus:controller.liquidFocus))
        .clipShape(IslandShellShape(radius:controller.visualRadius+controller.liquidImpulse*4,pull:controller.liquidImpulse,focus:controller.liquidFocus))
        .background {
            GeometryReader { proxy in
                let rect=proxy.frame(in:.named("islandWindow"))
                Color.clear.onAppear {controller.updateHitRect(rect)}
                    .onChange(of:rect) {_,value in controller.updateHitRect(value)}
            }
        }
        .onHover { controller.hover($0) }
        .offset(x:controller.visualCenterOffset)
        .frame(maxWidth:.infinity,maxHeight:.infinity,alignment:.top)
        .coordinateSpace(name:"islandWindow")
        .onPreferenceChange(ExpandedContentHeight.self) {measurement in if let measurement {controller.measureContent(measurement)}}
        .preferredColorScheme(.dark)
        .onChange(of:store.presentation) { _,_ in controller.refresh() }
        .onChange(of:store.profile) { _,_ in controller.refresh() }
        .onChange(of:store.selectedID) {_,_ in controller.refresh()}
        .onChange(of:controller.expandedHeightLimit) {_,_ in controller.refresh()}
        .onChange(of:store.visibleActivities.count) { _,_ in controller.refresh() }
        .onChange(of:controller.layoutActivities.map(\.id)) {_,_ in controller.refresh()}
        .onChange(of:controller.compactSlots.map(\.preferredCompactWidth)) {_,_ in controller.refresh()}
    }
    private var compactHeader:some View {
        let items=controller.compactSlots
        let wing=(controller.visualWidth-controller.geometry.cutoutWidth+controller.liquidImpulse*28+controller.hoverInvitation*8)/2
        return HStack(spacing:0) {
            compactGroup(Array(items.prefix(controller.compactLeadingCount)))
                .frame(width:max(0,wing-controller.visualCenterOffset-8),alignment:.trailing).padding(.trailing,8)
            Color.clear.frame(width:controller.geometry.cutoutWidth,height:1).accessibilityHidden(true)
            compactGroup(Array(items.dropFirst(controller.compactLeadingCount)),showOverflow:controller.layoutActivities.count>store.profile.compactLimit)
                .frame(width:max(0,wing+controller.visualCenterOffset-8),alignment:.leading).padding(.leading,8)
        }
        .frame(height:controller.geometry.headerHeight)
        .background {
            Color.clear.contentShape(Rectangle()).onTapGesture {if !controller.dropMode {expanded ? controller.dismiss():controller.expand()}}
        }
        .accessibilityElement(children:.contain).accessibilityLabel("Antille island")
        .accessibilityAction(named:Text(expanded ? "Collapse":"Expand")) {expanded ? controller.dismiss():controller.expand()}
        .animation(reduced ? nil:.easeOut(duration:0.14),value:items.map(\.id))
    }
    private var contentChrome:some View {
        HStack(spacing:4) {
            Spacer()
            Button {controller.togglePin()} label:{Image(systemName:store.presentation == .pinned ? "pin.fill":"pin").frame(width:24,height:24).contentShape(Rectangle())}
                .help("Keep island open").accessibilityLabel(store.presentation == .pinned ? "Unpin island":"Pin island")
            Button {controller.dismiss()} label:{Image(systemName:"xmark").frame(width:24,height:24).contentShape(Rectangle())}
                .help("Close island").accessibilityLabel("Close island")
        }.buttonStyle(.plain).font(.system(size:11)).foregroundStyle(.white.opacity(0.6)).padding(.horizontal,16).frame(height:28)
    }
    private var expandedPane:some View {
        let size=controller.expandedContentSize,key=controller.expandedContentKey
        let active=expanded && controller.contentPhase == .visible
        return ZStack(alignment:.top) {
            if controller.contentPhase.isMounted {
                VStack(spacing:0) {
                    contentChrome
                    ScrollView {
                        controller.expandedView().background {
                            GeometryReader {proxy in Color.clear.preference(key:ExpandedContentHeight.self,value:IslandContentMeasurement(key:key,height:proxy.size.height))}
                        }
                    }.scrollIndicators(.never).frame(width:size.width,height:size.height)
                }
                .frame(width:size.width).fixedSize().animation(nil,value:size)
                .opacity(controller.contentPhase == .visible ? 1:0)
                .environment(\.islandContentActive,active).allowsHitTesting(active).accessibilityHidden(!active)
            }
            if controller.dropMode {Label("Drop here",systemImage:"arrow.down").font(.system(size:10,weight:.medium)).foregroundStyle(.white.opacity(0.5)).padding(.top,2)}
        }
    }
    @ViewBuilder private func compactGroup(_ items: [IslandActivity],showOverflow:Bool=false) -> some View {
        if items.isEmpty && !showOverflow {
            if store.visibleActivities.isEmpty {
                Image(systemName:"circle.dotted").font(.system(size:14,weight:.light)).foregroundStyle(Color(islandHex:store.profile.accentHex).opacity(0.6))
                    .frame(width:24,height:28)
            } else { Color.clear.frame(width:24,height:28) }
        } else {
            HStack(spacing:5) {
                ForEach(items) { item in
                    Button {controller.activateCompact(item)} label:{
                        controller.compactView(item).frame(width:controller.compactWidth(for:item),height:controller.geometry.headerHeight-4)
                    }.buttonStyle(.plain)
                        .opacity(controller.extractingIDs.contains(item.id) || controller.isReserved(item.id) ? 0:1)
                        .scaleEffect(reduced ? 1:controller.isReserved(item.id) ? 0.55:1)
                        .animation(reduced ? nil:.spring(response:0.28,dampingFraction:0.66),value:controller.isReserved(item.id))
                        .accessibilityHidden(controller.isReserved(item.id))
                        .modifier(ActivityDragRegion(store:store,activity:item,regionID:"compact"))
                        .accessibilityLabel(item.compactLabel.map{item.title+": "+$0} ?? item.title)
                        .modifier(IslandDragCapture(enabled:item.actions.contains{$0.id=="detach"}))
                        .islandContextMenu(onOpen:{controller.beginContextMenu()},onClose:{controller.endContextMenu()}) {
                            item.actions.map {action in IslandContextMenuItem(action.title,enabled:!item.stale) {
                                guard let current=store.visibleActivities.first(where:{$0.id==item.id}),let latest=current.actions.first(where:{$0.id==action.id}) else{return}
                                store.perform(latest,on:current)
                            }}
                        }
                        .transition(reduced ? .identity:.scale(scale:0.55).combined(with:.opacity))
                        .overlay(alignment:.bottomTrailing) {
                            if item.attention.rank>1 { Circle().fill(item.attention == .error ? .orange : Color(islandHex:store.profile.accentHex)).frame(width:5,height:5) }
                        }
                        .help("\(item.title) · \(item.stale ? "Source disconnected" : item.state)")
                }
                if showOverflow {
                    Menu {
                        ForEach(Array(controller.layoutActivities.dropFirst(store.profile.compactLimit))) {item in Button(item.title) {controller.activateCompact(item)}}
                    } label:{Text("+\(controller.layoutActivities.count-store.profile.compactLimit)").font(.system(size:10)).foregroundStyle(.white.opacity(0.6)).frame(width:24,height:controller.geometry.headerHeight-4)}
                        .menuStyle(.borderlessButton).menuIndicator(.hidden).fixedSize().help("More active items").accessibilityLabel("More active items")
                }
            }
        }
    }
}
