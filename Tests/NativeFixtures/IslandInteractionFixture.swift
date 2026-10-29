// SPDX-License-Identifier: MPL-2.0
// Copyright (c) 2026 Matthew Williams

@testable import Antille
import AppKit
import SwiftUI
@testable import AntilleApp

@MainActor @Observable final class IslandInteractionSamples {
    let store=IslandStore(profile:IslandProfile.presets[0])
    let utilities:UtilityController
    var lastAction="No sample action"
    private var controller:IslandController?
    private let preferenceName="dev.upsided.antille.interaction.\(UUID().uuidString)"
    init() {
        let defaults=UserDefaults(suiteName:preferenceName)!
        utilities=UtilityController(fixture:true,defaults:defaults)
        utilities.setNote("CARPE DIEM!!!");utilities.enablePower(false)
    }
    func start() {
        guard controller==nil else{return}
        utilities.updated={ [weak self] in try? self?.store.replace(producerID:UtilityController.producer,with:$0)}
        utilities.start()
        do {
            for index in 0..<12 {
                try store.upsert(IslandActivity(producerID:"sample",activityID:String(index),title:index==0 ? "Sample question":"Sample agent \(index)",attention:index==0 ? .needsAttention:.none,symbol:"leaf",actions:[IslandAction(id:"send",title:"Send sample answer")],content:[
                    IslandBlock(id:"output",kind:.text,text:"**Sample output.** This fixture uses no live account or credentials.",lineLimit:6,markdown:true),
                    IslandBlock(id:"question",kind:.text,text:"Which sample approach should this Pikmin use?"),
                    IslandBlock(id:"answer",kind:.textInput,text:"Write a sample answer"),
                    IslandBlock(id:"submit",kind:.button,text:"Send sample answer",actionID:"send")
                ],focusActionID:"focus",blurActionID:"blur",actionsInMenu:true,requiresClickToExpand:true,preferredExpandedHeight:520,showsInCompact:index<3))
            }
        } catch {lastAction=error.localizedDescription}
        store.actionHandler={ [weak self] activity,action in
            self?.lastAction=activity.title+": "+action.id
            if activity.producerID==UtilityController.producer {self?.utilities.handle(action.id)}
        }
        let utilities=self.utilities
        let icon:(IslandActivity)->AnyView={activity in
            activity.producerID==UtilityController.producer ? AnyView(UtilityCompactIcon(activity:activity,utilities:utilities)):AnyView(IslandActivityIcon(activity))
        }
        controller=IslandController(store:store,compact:icon,expanded:{ [weak self] in
            guard let self else{return AnyView(EmptyView())}
            return AnyView(IslandDefaultExpanded(store:self.store,icon:icon,content:{activity in
                activity.producerID==UtilityController.producer ? AnyView(UtilityIslandContent(activityID:activity.activityID,utilities:utilities)):nil
            }))
        })
        store.selectedID="sample::0";controller?.show();controller?.expand()
    }
    func stop() {controller?.close();controller=nil;utilities.stop();UserDefaults(suiteName:preferenceName)?.removePersistentDomain(forName:preferenceName)}
    func open(_ id:String) {store.selectedID=id;controller?.expand()}
    func width(_ width:Double) {
        store.profile.expandedWidth=width;store.profile.compactLimit=width<=300 ? 1:4;store.profile.wingWidth=width<=300 ? 36:52
        utilities.showNoteInCompact(width>300);controller?.refresh()
    }
    func collapse() {controller?.dismiss()}
}
@MainActor final class IslandInteractionDelegate:NSObject,NSApplicationDelegate {
    let model=IslandInteractionSamples()
    func applicationDidFinishLaunching(_ notification:Notification) {NSApp.setActivationPolicy(.accessory);model.start()}
    func applicationShouldTerminateAfterLastWindowClosed(_ sender:NSApplication)->Bool {false}
    func applicationWillTerminate(_ notification:Notification) {model.stop()}
}
@main struct IslandInteractionFixture:App {
    @NSApplicationDelegateAdaptor(IslandInteractionDelegate.self) private var delegate
    var body:some Scene {
        Window("Antille Interaction Fixture",id:"samples") {
            VStack(alignment:.leading,spacing:12) {
                Text("Isolated island samples").font(.headline)
                Text("No T3, host, live player, credentials or permission requests.").font(.caption)
                Text(delegate.model.lastAction).font(.caption).foregroundStyle(.secondary)
            }.padding(20)
        }.defaultSize(width:340,height:140).commands {
            CommandMenu("Fixture") {
                Button("Sample question") {delegate.model.open("sample::0")}
                Button("Sticky note") {delegate.model.open("local.utilities::note")}
                Button("Timer") {delegate.model.open("local.utilities::timer")}
                Button("Now playing") {delegate.model.open("local.utilities::music")}
                Divider()
                Button("Narrow layout") {delegate.model.width(300)}
                Button("Standard layout") {delegate.model.width(380)}
                Button("Wide layout") {delegate.model.width(600)}
                Button("Collapse island") {delegate.model.collapse()}
            }
        }
        MenuBarExtra("Antille QA",systemImage:"testtube.2") {Button("Quit fixture") {NSApp.terminate(nil)}}
    }
}
