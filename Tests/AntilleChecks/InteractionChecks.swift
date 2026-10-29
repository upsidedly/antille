// SPDX-License-Identifier: MPL-2.0
// Copyright (c) 2026 Matthew Williams

import Antille
import AppKit

@MainActor func runInteractionChecks() async throws {
    let start=Date(timeIntervalSince1970:1000)
    try expect(IslandSpritePlayback.frame(at:start.addingTimeInterval(-1),count:60,fps:25,startedAt:start,repeats:false)==0,"one-shot before start")
    try expect(IslandSpritePlayback.frame(at:start.addingTimeInterval(0.5),count:60,fps:25,startedAt:start,repeats:false)==12,"one-shot phase")
    try expect(IslandSpritePlayback.frame(at:start.addingTimeInterval(8),count:60,fps:25,startedAt:start,repeats:false)==59,"one-shot holds its neutral last frame")
    try expect(IslandSpritePlayback.frame(at:start.addingTimeInterval(3),count:60,fps:20,startedAt:start,repeats:true)==0,"looping sprites retain their behavior")
    var activity=IslandActivity(producerID:"interaction-check",activityID:"head",title:"Sample")
    let legacy=try IslandWire.decoder().decode(IslandActivity.self,from:IslandWire.encoder().encode(activity))
    try expect(legacy.actionsInMenu==nil && legacy.spriteStartedAt==nil && legacy.showsInCompact==nil && legacy.compactLabel==nil,"older activities keep default behavior")
    var expandedOnly=activity;expandedOnly.activityID="expanded-only";expandedOnly.showsInCompact=false
    let compactStore=IslandStore();try compactStore.upsert(activity);try compactStore.upsert(expandedOnly)
    try expect(compactStore.visibleActivities.count==2 && compactStore.compactActivities.map(\.activityID)==["head"],"expanded-only activities remain available without occupying compact slots")
    let expandedCopy=try IslandWire.decoder().decode(IslandActivity.self,from:IslandWire.encoder().encode(expandedOnly))
    try expect(expandedCopy.showsInCompact==false,"compact eligibility survives the producer wire")
    var note=IslandActivity(producerID:"interaction-check",activityID:"note",title:"Sticky note",priority:60,compactLabel:"CARPE DIEM!!!")
    let noteCopy=try IslandWire.decoder().decode(IslandActivity.self,from:IslandWire.encoder().encode(note))
    try expect(noteCopy.compactLabel=="CARPE DIEM!!!" && note.preferredCompactWidth>28,"compact text survives the wire and reserves its measured width")
    try compactStore.upsert(note)
    let noteController=IslandController(store:compactStore)
    try expect(noteController.compactSlots.map(\.activityID)==["head","note"],"text renders on the trailing wing without changing priority admission")
    noteController.close()
    let orderingStore=IslandStore()
    for index in 0..<3 {try orderingStore.upsert(IslandActivity(producerID:"ordering",activityID:String(index),title:"Agent \(index)",updatedAt:start.addingTimeInterval(Double(-index))))}
    let orderingController=IslandController(store:orderingStore),initialOrder=orderingController.compactSlots.map(\.id)
    var changed=orderingStore.activities.first{$0.activityID=="2"}!
    changed.revision+=1;changed.updatedAt=start.addingTimeInterval(10);changed.detail="Next streamed words"
    try orderingStore.upsert(changed);orderingController.refresh()
    try expect(orderingController.compactSlots.map(\.id)==initialOrder,"streamed output must not move compact heads under the pointer")
    changed.revision+=1;changed.attention = .needsAttention
    try orderingStore.upsert(changed);orderingController.refresh()
    try expect(orderingController.compactSlots.first?.id==changed.id,"new attention can still promote a head")
    orderingController.close()
    note.compactLabel=String(repeating:"x",count:257)
    do {try note.validate();throw CheckError.failed("oversize compact text was accepted")} catch is IslandError {}
    let geometry=IslandGeometry(screen:CGRect(x:0,y:0,width:1440,height:900),cutoutWidth:180,topInset:36)
    let widths=[28.0,28.0,28.0,28.0,noteCopy.preferredCompactWidth]
    var profile=IslandProfile();profile.compactLimit=8
    let leftCount=3
    let labelFrame=geometry.frame(profile:profile,expanded:false,activityCount:5,slotWidths:widths,leadingSlotCount:leftCount)
    let iconFrame=geometry.frame(profile:profile,expanded:false,activityCount:5,slotWidths:Array(repeating:28,count:5),leadingSlotCount:leftCount)
    try expect(labelFrame.maxX>iconFrame.maxX && labelFrame.minX==iconFrame.minX,"a long note grows into the right wing while keeping the left menu clearance")
    var previousRight=Double.leastNormalMagnitude
    for index in widths.indices {
        guard let point=geometry.landingSlot(index:index,profile:profile,activityCount:5,slotWidths:widths,leadingSlotCount:leftCount) else {throw CheckError.failed("missing mixed-width landing")}
        let minX=point.x-widths[index]/2,maxX=point.x+widths[index]/2
        try expect(minX>=labelFrame.minX && maxX<=labelFrame.maxX,"mixed-width landing fits its wing")
        try expect(index<leftCount ? maxX<=geometry.screen.midX-90:minX>=geometry.screen.midX+90,"text and sprites stay outside the physical camera")
        try expect(index==0 || minX>previousRight,"text and sprite slots never overlap")
        previousRight=maxX
    }
    let solo=geometry.landingSlot(index:0,profile:profile,activityCount:1,slotWidths:[noteCopy.preferredCompactWidth],leadingSlotCount:0)!
    try expect(solo.x>geometry.screen.midX+90,"a solo note still occupies the right wing")
    let narrow=IslandGeometry(screen:CGRect(x:0,y:0,width:640,height:500),cutoutWidth:180,topInset:36)
    let bounded=narrow.compactSlotWidths(profile:profile,activityCount:8,preferred:Array(repeating:160,count:8))
    let narrowFrame=narrow.frame(profile:profile,expanded:false,activityCount:8,slotWidths:bounded)
    try expect(bounded.allSatisfy{$0>=28 && $0<160} && narrowFrame.minX>=12 && narrowFrame.maxX<=628,"compact captions shrink within screen margins")
    var wide=profile;wide.expandedWidth=780
    let wideFrame=narrow.frame(profile:wide,expanded:true,activityCount:2,slotWidths:[28,150],leadingSlotCount:1)
    try expect(wideFrame.minX>=12 && wideFrame.maxX<=628,"a wide expanded section with an asymmetric caption stays within screen margins")
    let local=CGRect(x:20,y:8,width:28,height:24),panel=CGRect(x:100,y:500,width:500,height:80)
    let firstRegion=IslandHeadHitTesting.screenRect(local,panel:panel),movedRegion=IslandHeadHitTesting.screenRect(local,panel:panel.offsetBy(dx:300,dy:-100))
    try expect(movedRegion==firstRegion.offsetBy(dx:300,dy:-100),"hit regions follow current panel placement rather than an earlier screen frame")
    let neighbors=["left":CGRect(x:0,y:0,width:28,height:28),"right":CGRect(x:33,y:0,width:28,height:28)]
    try expect(IslandHeadHitTesting.nearest(to:CGPoint(x:31,y:14),regions:neighbors)=="right","overlapping hit padding selects the nearest head")
    try expect(IslandHeadHitTesting.nearest(to:CGPoint(x:-4,y:14),regions:neighbors)=="left" && IslandHeadHitTesting.nearest(to:CGPoint(x:-12,y:14),regions:neighbors)==nil,"head edges have bounded forgiving hit padding")
    let returnRegion=IslandHeadHitTesting.returnRegion(island:CGRect(x:500,y:868,width:300,height:32))
    try expect(returnRegion.contains(CGPoint(x:600,y:875)) && !returnRegion.contains(CGPoint(x:600,y:840)),"pulling beyond the visible lower lip extracts rather than using the large incoming drop target")
    activity.actionsInMenu=true;activity.requiresClickToExpand=true;activity.preferredExpandedHeight=520;activity.spriteStartedAt=1000.125;activity.spriteRepeats=false
    let roundTrip=try IslandWire.decoder().decode(IslandActivity.self,from:IslandWire.encoder().encode(activity))
    try expect(roundTrip.actionsInMenu==true && roundTrip.requiresClickToExpand==true && roundTrip.preferredExpandedHeight==520 && roundTrip.spriteStartedAt==1000.125 && roundTrip.spriteRepeats==false,"optional interaction, form height and fractional playback settings survive the wire")
    let markdown="# Status\n\n**Ready** and `swift build`\n\n- One\n2. Two\n\n> A quote\n\n```swift\nlet count = 2\n```\n\n| Task | State |\n| --- | --- |\n| Build | Done |"
    let blocks=IslandMarkdown.blocks(markdown)
    try expect(blocks.contains{$0.kind == .heading(1)} && blocks.contains{$0.kind == .list("•")} && blocks.contains{$0.kind == .list("2.")} && blocks.contains{$0.kind == .quote} && blocks.contains{$0.kind == .table},"Markdown block structure survives streaming")
    try expect(blocks.first(where:{$0.kind == .code("swift")})?.text=="let count = 2","code fences remain verbatim")
    try expect(IslandMarkdown.blocks("```swift\nlet unfinished =").last?.text=="let unfinished =","incomplete streaming fences render without losing code")
    try expect(String(IslandMarkdown.inline("**Ready** and `swift build`").characters)=="Ready and swift build","Markdown inline syntax renders as attributed text")
    try expect(IslandMarkdown.commonPrefix("Ready 👋", "Ready 👋 with more")==7,"fade range preserves existing grapheme clusters")
    let longCode="```swift\n"+String(repeating:"let value = \"🌸\"\n",count:400)
    let tail=IslandMarkdown.tail(longCode)
    try expect(tail.utf8.count<=3600 && tail.hasPrefix("```\n") && IslandMarkdown.blocks(tail).first?.kind == .code(""),"bounded Unicode tails preserve an open code fence")
    let markdownBlock=IslandBlock(id:"output",kind:.text,text:markdown,lineLimit:9,markdown:true,textIdentity:"message-1")
    let blockCopy=try IslandWire.decoder().decode(IslandBlock.self,from:IslandWire.encoder().encode(markdownBlock))
    try expect(blockCopy==markdownBlock,"Markdown identity and viewport settings survive the wire")
    let store=IslandStore();store.profile.openOnHover=true;store.profile.hoverDelay=0
    try store.upsert(activity)
    let controller=IslandController(store:store)
    controller.hover(true)
    try await Task.sleep(for:.milliseconds(60))
    try expect(store.presentation == .collapsed && controller.hoverInvitation==1,"click-required consumers invite hover without opening")
    controller.expand();controller.hover(false)
    try await Task.sleep(for:.milliseconds(240))
    try expect(store.presentation == .expanded,"a click-opened island stays open when the pointer leaves so keyboard replies remain usable")
    controller.togglePin();controller.expand()
    try expect(store.presentation == .pinned,"clicking a different head preserves a pinned island")
    controller.togglePin()
    controller.collapse()
    try expect(store.presentation == .collapsed,"explicit dismissal releases the click hold")
    controller.activateCompact(activity)
    try expect(store.presentation == .expanded && store.selectedID==activity.id,"compact activation opens its item")
    controller.activateCompact(activity)
    try expect(store.presentation == .collapsed,"activating the already open compact item closes the island")
    var other=activity;other.activityID="other";try store.upsert(other)
    controller.activateCompact(activity);controller.activateCompact(other)
    try expect(store.presentation == .expanded && store.selectedID==other.id,"a different compact item switches content without closing")
    controller.togglePin();controller.activateCompact(activity)
    try expect(store.presentation == .pinned && store.selectedID==activity.id,"switching compact items preserves the pin")
    controller.activateCompact(activity)
    try expect(store.presentation == .collapsed,"an explicit repeat click also closes a pinned selected item")
    controller.close()
    _=NSApplication.shared
    for key in [IslandArrowKey.up,.down] {
        let shortcut=IslandHoverArrowShortcut(key:key) {}
        try expect(shortcut.setEnabled(true) && shortcut.isRegistered,"plain hover arrow can register without an input-monitoring prompt")
        NotificationCenter.default.post(name:NSMenu.didBeginTrackingNotification,object:nil)
        try expect(!shortcut.isRegistered,"menu tracking releases the arrow")
        NotificationCenter.default.post(name:NSMenu.didEndTrackingNotification,object:nil)
        try expect(shortcut.isRegistered,"hover arrow returns after menu tracking")
        shortcut.setEnabled(false)
        try expect(!shortcut.isRegistered,"leaving hover restores the normal arrow")
        shortcut.close()
    }
    print("PASS: compact text wire/width/landing/camera clearance; Markdown blocks/inline/incomplete fences/Unicode bounds; one-shot/loop timing; click-only hover; same-item dismissal/different-item switching/pinning; Up/Down registration/menu suspension/release.")
}
