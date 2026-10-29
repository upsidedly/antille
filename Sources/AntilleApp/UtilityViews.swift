// SPDX-License-Identifier: MPL-2.0
// Copyright (c) 2026 Matthew Williams

import SwiftUI
import AppKit
import Antille

struct UtilitiesSettingsView:View {
    @Bindable var utilities:UtilityController
    var body:some View {
        Group {
            Section("Sticky note") {NoteUtilityView(utilities:utilities)}
            Section("Music") {
                Toggle("Show music",isOn:Binding(get:{utilities.musicEnabled},set:{utilities.enableMusic($0)}))
                if utilities.musicEnabled {
                    Picker("Player",selection:Binding(get:{utilities.music.preferred},set:{utilities.music.setPreferred($0)})) {
                        Text("Automatic").tag("automatic");Text("Spotify").tag("spotify");Text("Music").tag("music")
                    }
                    MusicUtilityView(music:utilities.music,fixture:utilities.fixture)
                }
            }
            Section("Timer") {TimerUtilityView(utilities:utilities)}
            Section("Power") {
                Toggle("Show battery and charging",isOn:Binding(get:{utilities.powerEnabled},set:{utilities.enablePower($0)}))
                if utilities.powerEnabled {PowerUtilityView(power:utilities.power,fixture:utilities.fixture)}
            }
            if let error=utilities.error {Section {Text(error).font(.system(size:11)).foregroundStyle(.orange)}}
            Section {Text("Utilities apply immediately across profiles.").font(.caption).foregroundStyle(.secondary)}
        }
    }
}

struct NoteUtilityView:View {
    @Bindable var utilities:UtilityController
    @State private var editing=false
    @State private var draft=""
    @FocusState private var focused:Bool
    @Environment(\.islandContentActive) private var contentActive
    var body:some View {
        VStack(alignment:.leading,spacing:12) {
            if editing {
                TextEditor(text:$draft).font(.system(size:13)).frame(height:84)
                    .accessibilityLabel("Note text").focused($focused)
                    .scrollContentBackground(.hidden).padding(6).background(.primary.opacity(0.055),in:RoundedRectangle(cornerRadius:7))
                HStack(spacing:10) {
                    Button("Save note") {utilities.setNote(draft);editing=false}
                    Button("Cancel") {editing=false}
                }.controlSize(.small)
            } else {
                if !utilities.noteText.isEmpty {
                    Text(utilities.noteText).font(.system(size:15,weight:.medium)).fixedSize(horizontal:false,vertical:true).textSelection(.enabled)
                }
                Button(utilities.noteText.isEmpty ? "Add a note":"Edit note") {draft=utilities.noteText;editing=true}.controlSize(.small)
            }
            if !utilities.noteText.isEmpty {
                Toggle("Show in compact island",isOn:Binding(get:{utilities.noteInCompact},set:{utilities.showNoteInCompact($0)}))
                    .font(.system(size:11)).toggleStyle(.checkbox)
            }
        }.frame(maxWidth:.infinity,alignment:.leading)
            .task(id:editing && contentActive) {guard editing,contentActive else{focused=false;return};await Task.yield();guard !Task.isCancelled else{return};focused=true}
    }
}

struct MusicUtilityView:View {
    @Bindable var music:MusicBridge
    var fixture=false
    @Environment(\.islandContentActive) private var contentActive
    var body:some View {
        VStack(alignment:.leading,spacing:14) {
            HStack(alignment:.center,spacing:12) {
                Group {
                    if let image=music.artwork ?? music.playerIcon {Image(nsImage:image).resizable().scaledToFit()}
                    else {Image(systemName:"music.note").resizable().scaledToFit().padding(8)}
                }.frame(width:44,height:44).clipShape(RoundedRectangle(cornerRadius:7)).accessibilityHidden(true)
                VStack(alignment:.leading,spacing:4) {
                    Text(music.snapshot?.title.isEmpty==false ? music.snapshot?.title ?? "Now playing":music.running ? "Waiting for playback":"\(music.player.name) is closed")
                        .font(.system(size:13,weight:.semibold)).lineLimit(2).textSelection(.enabled)
                    if let artist=music.snapshot?.artist,!artist.isEmpty {Text(artist).font(.system(size:11)).foregroundStyle(.secondary).lineLimit(1)}
                    Text(fixture ? "Sample playback · no live player":music.snapshot.map{$0.playbackState.rawValue.capitalized+" in "+music.player.name} ?? music.player.name)
                        .font(.system(size:10)).foregroundStyle(.secondary)
                }.frame(maxWidth:.infinity,alignment:.leading)
            }
            if let track=music.snapshot,let duration=track.duration,track.position != nil {
                TimelineView(.animation(minimumInterval:1,paused:!track.isPlaying || !contentActive)) {context in
                    let position=track.position(at:context.date) ?? 0
                    VStack(spacing:4) {
                        ProgressView(value:min(1,max(0,position/duration)))
                        HStack {Text(IslandCountdown.clock(position));Spacer();Text(IslandCountdown.clock(duration))}.font(.system(size:9)).monospacedDigit().foregroundStyle(.secondary)
                    }
                }
            }
            if music.running {
                HStack(spacing:16) {
                    Spacer()
                    transport("Previous track",symbol:"backward.end.fill",command:.previous)
                    transport(music.snapshot?.isPlaying==true ? "Pause":"Play",symbol:music.snapshot?.isPlaying==true ? "pause.fill":"play.fill",command:.toggle)
                    transport("Next track",symbol:"forward.end.fill",command:.next)
                    Spacer()
                    if music.busy {ProgressView().controlSize(.mini)}
                }.buttonStyle(.plain)
                if !music.controlsAllowed,!fixture {Text("macOS may ask for Automation access when you use a playback control.").font(.system(size:10)).foregroundStyle(.secondary)}
            } else {Button("Open \(music.player.name)") {music.openPlayer()}.controlSize(.small)}
            if let error=music.error {
                Text(error).font(.system(size:11)).foregroundStyle(.orange).fixedSize(horizontal:false,vertical:true)
                if !music.controlsAllowed,let url=URL(string:"x-apple.systempreferences:com.apple.preference.security?Privacy_Automation") {
                    Link("Automation settings",destination:url).font(.system(size:11))
                }
            }
        }.frame(maxWidth:.infinity,alignment:.leading)
    }
    private func transport(_ title:String,symbol:String,command:MusicTransport)->some View {
        Button {music.perform(command)} label:{Image(systemName:symbol).font(.system(size:command == .toggle ? 20:14)).frame(width:32,height:32)}
            .disabled(music.busy).help(title).accessibilityLabel(title+" in "+music.player.name)
    }
}

struct TimerUtilityView:View {
    @Bindable var utilities:UtilityController
    var body:some View {
        VStack(alignment:.leading,spacing:12) {
            if utilities.timer.phase == .idle {
                HStack(spacing:8) {ForEach([5,15,25],id:\.self) {minutes in Button("\(minutes) min") {utilities.startTimer(seconds:Double(minutes*60))}}}.controlSize(.small)
                HStack(spacing:8) {
                    TextField("Minutes",value:$utilities.minutes,format:.number).textFieldStyle(.roundedBorder).frame(width:58).accessibilityLabel("Timer minutes")
                    Stepper("minutes",value:$utilities.minutes,in:1...1440).fixedSize()
                    Spacer(minLength:0)
                    Button("Start") {utilities.startTimer()}.disabled(!(1...1440).contains(utilities.minutes))
                }.controlSize(.small)
            } else {
                Text(IslandCountdown.clock(utilities.timer.remaining(at:utilities.now))).font(.system(size:32,weight:.light)).monospacedDigit()
                HStack(spacing:10) {
                    switch utilities.timer.phase {
                    case .running:Button("Pause") {utilities.pauseTimer()};Button("Cancel") {utilities.cancelTimer()}
                    case .paused:Text("Paused").font(.system(size:11)).foregroundStyle(.secondary);Button("Resume") {utilities.resumeTimer()};Button("Cancel") {utilities.cancelTimer()}
                    case .finished:Button("Start again") {utilities.restartTimer()};Button("Dismiss") {utilities.cancelTimer()}
                    case .idle:EmptyView()
                    }
                }.controlSize(.small)
            }
        }.frame(maxWidth:.infinity,alignment:.leading)
    }
}

struct PowerUtilityView:View {
    @Bindable var power:PowerBridge
    var fixture=false
    var body:some View {
        VStack(alignment:.leading,spacing:9) {
            if let value=power.snapshot {
                HStack(spacing:10) {
                    Image(systemName:value.symbol).font(.system(size:22)).foregroundStyle(value.isLow ? .orange:.primary).accessibilityHidden(true)
                    if let percent=value.percent {Text("\(percent)%").font(.system(size:19,weight:.medium)).monospacedDigit()}
                    Text(value.status).font(.system(size:12)).foregroundStyle(.secondary)
                }
                if let percent=value.percent {ProgressView(value:Double(percent)/100).accessibilityLabel("Battery level").accessibilityValue("\(percent) percent")}
                if value.charging,let minutes=value.minutesToFull {Text("About \(minutes) minutes until full").font(.system(size:11)).foregroundStyle(.secondary)}
                else if !value.pluggedIn,let minutes=value.minutesRemaining {Text("About \(minutes) minutes remaining").font(.system(size:11)).foregroundStyle(.secondary)}
                if value.lowPowerMode {Label("Low Power Mode",systemImage:"leaf").font(.system(size:11)).foregroundStyle(.secondary)}
            } else {Text("Battery information is unavailable on this Mac.").font(.system(size:12)).foregroundStyle(.secondary)}
            if fixture {Text("Sample battery state").font(.system(size:10)).foregroundStyle(.secondary)}
        }.frame(maxWidth:.infinity,alignment:.leading)
    }
}

struct UtilityCompactIcon:View {
    let activity:IslandActivity
    @Bindable var utilities:UtilityController
    @Environment(\.islandContentActive) private var contentActive
    var body:some View {
        switch activity.activityID {
        case "note":Image(systemName:"note.text").font(.system(size:19))
        case "timer":
            TimelineView(.animation(minimumInterval:1,paused:utilities.timer.phase != .running || !contentActive)) {context in
                VStack(spacing:1) {
                    Image(systemName:utilities.timer.phase == .finished ? "checkmark":"timer").font(.system(size:9))
                    Text(IslandCountdown.clock(utilities.timer.remaining(at:context.date),compact:true)).font(.system(size:9,weight:.medium)).monospacedDigit()
                }
            }
        case "power":
            VStack(spacing:1) {Image(systemName:utilities.power.snapshot?.symbol ?? "battery.0percent").font(.system(size:12));if let percent=utilities.power.snapshot?.percent {Text("\(percent)%").font(.system(size:8)).monospacedDigit()}}
        default:
            if let artwork=utilities.music.artwork {Image(nsImage:artwork).resizable().scaledToFill().frame(width:24,height:24).clipShape(RoundedRectangle(cornerRadius:4))}
            else {Image(systemName:"music.note").font(.system(size:17))}
        }
    }
}

struct UtilityIslandContent:View {
    let activityID:String
    @Bindable var utilities:UtilityController
    var body:some View {
        Group {
            switch activityID {
            case "note":NoteUtilityView(utilities:utilities)
            case "music":MusicUtilityView(music:utilities.music,fixture:utilities.fixture)
            case "timer":TimerUtilityView(utilities:utilities)
            case "power":PowerUtilityView(power:utilities.power,fixture:utilities.fixture)
            default:EmptyView()
            }
        }.padding(.vertical,4)
    }
}
