// SPDX-License-Identifier: MPL-2.0
// Copyright (c) 2026 Matthew Williams

import SwiftUI
import Antille
@testable import AntilleApp

@MainActor @Observable final class UtilitiesFixtureModel {
    let utilities:UtilityController
    let store=IslandStore()
    var settings=false
    var width=390.0
    init() {
        let defaults=UserDefaults.standard
        defaults.removePersistentDomain(forName:"dev.upsided.antille.utilities.fixture")
        utilities=UtilityController(fixture:true,defaults:defaults)
        store.selectedID=UtilityController.producer+"::music"
        utilities.updated={ [weak self] activities in try? self?.store.replace(producerID:UtilityController.producer,with:activities) }
        store.actionHandler={ [weak self] _,action in self?.utilities.handle(action.id) }
        utilities.start()
    }
}
@main struct UtilitiesFixture:App {
    @State private var model=UtilitiesFixtureModel()
    var body:some Scene {
        Window("Antille Utilities Fixture",id:"utilities") {
            VStack(spacing:12) {
                if model.settings {
                    Form {UtilitiesSettingsView(utilities:model.utilities)}.formStyle(.grouped).frame(width:620,height:540)
                } else {
                    IslandDefaultExpanded(store:model.store,icon:{AnyView(UtilityCompactIcon(activity:$0,utilities:model.utilities))},showsHeader:{$0.activityID != "music"},content:{AnyView(UtilityIslandContent(activityID:$0.activityID,utilities:model.utilities))})
                        .frame(width:model.width).background(.black,in:RoundedRectangle(cornerRadius:24)).preferredColorScheme(.dark)
                }
                HStack {
                    Button(model.settings ? "Island cards":"Utility settings") {model.settings.toggle()}
                    Button("Two-second sample timer") {model.utilities.startTimer(seconds:2);model.store.selectedID=UtilityController.producer+"::timer"}
                }.controlSize(.small)
                Text("Isolated sample data. No player access, T3, server, notifications or floating island.")
                    .font(.caption2).foregroundStyle(.secondary).frame(maxWidth:420)
            }.padding(16)
        }.defaultSize(width:440,height:350).commands {
            CommandMenu("Fixture") {
                Button("Narrow island") {model.width=300}
                Button("Standard island") {model.width=390}
                Button("Paused playback sample") {model.utilities.music.snapshot?.isPlaying=false}
                Button("Long title sample") {model.utilities.music.snapshot?.title="A very long sample song title that needs room to wrap without hiding the playback controls";model.utilities.music.snapshot?.artist="Sample artist with a long name"}
                Button("Denied playback sample") {model.utilities.music.controlsAllowed=false;model.utilities.music.error="Allow Antille to control Spotify in macOS Automation settings."}
                Button("Closed player sample") {model.utilities.music.snapshot=nil;model.utilities.music.running=false;model.utilities.music.error=nil}
            }
        }
    }
}
