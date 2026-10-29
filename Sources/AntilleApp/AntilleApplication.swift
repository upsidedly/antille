// SPDX-License-Identifier: MPL-2.0
// Copyright (c) 2026 Matthew Williams

import SwiftUI
import AppKit
import Antille

@main struct AntilleApplication: App {
    @NSApplicationDelegateAdaptor(AntilleDelegate.self) private var delegate
    @Environment(\.openWindow) private var openWindow
    var body: some Scene {
        Window(SilentCredentialPolicy.memoryOnly ? "Antille — Fixture":"Antille",id:"creator") {
            CreatorView(host:delegate.model).frame(minWidth:820,minHeight:570)
                .onAppear { delegate.model.start() }
        }.defaultSize(width:930,height:650)
        MenuBarExtra {
            Button("Open Antille") { openWindow(id:"creator");NSApp.activate(ignoringOtherApps:true) }
            Button("Expand island") { delegate.model.showIsland() }
            Button("Sticky note") {delegate.model.showUtility("note")}
            Button("Now playing") {delegate.model.showUtility("music")}.disabled(!delegate.model.utilities.musicEnabled)
            Button("Timer") {delegate.model.showUtility("timer")}
            Button("Power") {delegate.model.showUtility("power")}.disabled(!delegate.model.utilities.powerEnabled)
            Button("Start a 5-minute timer") { delegate.model.startTimer() }
            Divider()
            Text(delegate.model.status)
            Button("Quit Antille") { delegate.model.stop();NSApp.terminate(nil) }.keyboardShortcut("q")
        } label: { Image(systemName:"capsule.tophalf.filled") }
    }
}
@MainActor final class AntilleDelegate:NSObject,NSApplicationDelegate {
    let model=HostModel()
    func applicationDidFinishLaunching(_ notification:Notification) {
        NSApp.setActivationPolicy(.accessory);model.start()
        showCreator()
    }
    func applicationWillTerminate(_ notification:Notification) { model.stop() }
    func showCreator() {
        NSApp.activate(ignoringOtherApps:true)
        NSApp.windows.first(where:{$0.title.hasPrefix("Antille")})?.makeKeyAndOrderFront(nil)
    }
}
struct CreatorView:View {
    @Bindable var host:HostModel
    @State private var tab="Utilities"
    @State private var sample="Running"
    var body:some View {
        HStack(spacing:0) {
            VStack(alignment:.leading,spacing:20) {
                HStack(spacing:10) {
                    Image(systemName:"capsule.tophalf.filled").font(.system(size:23,weight:.light))
                    Text("Antille").font(.system(size:20,weight:.semibold))
                }.padding(.top,8)
                Text("Your island").font(.system(size:11,weight:.medium)).foregroundStyle(.secondary)
                ScrollView {
                    VStack(spacing:4) {
                        ForEach(host.profiles) { profile in
                            Button { host.setProfile(profile.id) } label:{
                                HStack {
                                    Circle().fill(Color(islandHex:profile.accentHex)).frame(width:7,height:7)
                                    Text(profile.name).lineLimit(1);Spacer()
                                    if profile.id==host.draft.id { Image(systemName:"checkmark").font(.system(size:10,weight:.semibold)) }
                                }.padding(.horizontal,10).padding(.vertical,10)
                                .background(profile.id==host.draft.id ? Color.primary.opacity(0.065) : .clear,in:RoundedRectangle(cornerRadius:8))
                            }.buttonStyle(.plain)
                        }
                    }
                }
                Button { host.duplicate() } label:{Label("Duplicate profile",systemImage:"plus")}.buttonStyle(.plain).font(.system(size:12))
                Spacer(minLength:0)
                VStack(alignment:.leading,spacing:8) {
                    HStack(spacing:5) { Circle().fill(host.isReady ? Color.green.opacity(0.7) : .orange).frame(width:5,height:5);Text(host.status) }
                }.font(.system(size:11))
            }.padding(20).frame(width:190).background(.quaternary.opacity(0.35))
            Divider()
            VStack(spacing:0) {
                HStack {
                    if tab=="Utilities" {
                        Text("Utilities").font(.system(size:19,weight:.medium));Spacer()
                        Button("Open island") {host.showIsland()}
                    } else {
                    TextField("Profile name",text:$host.draft.name).textFieldStyle(.plain).font(.system(size:19,weight:.medium))
                    Spacer()
                    Menu {
                        Button("Import profile…") { host.importProfile() }
                        Button("Export profile…") { host.exportProfile() }
                        Button("Restore previous save") { host.recoverPrevious() }
                    } label:{Image(systemName:"square.and.arrow.up")}.menuStyle(.borderlessButton).frame(width:30)
                    Button("Apply") { Task { await host.apply() } }.keyboardShortcut("s").buttonStyle(.borderedProminent).tint(Color(islandHex:"6B806A"))
                    }
                }.padding(.horizontal,26).padding(.vertical,20)
                if tab != "Utilities" {preview.padding(.horizontal,26).padding(.bottom,16)}
                Picker("Section",selection:$tab) {
                    ForEach(["Utilities","Island","Behavior","Content","Sources"],id:\.self) { Text($0) }
                }.pickerStyle(.segmented).labelsHidden().padding(.horizontal,26)
                ScrollView {
                    Form {
                        switch tab {
                        case "Utilities":UtilitiesSettingsView(utilities:host.utilities)
                        case "Island": appearance
                        case "Behavior": behavior
                        case "Content": content
                        default: sources
                        }
                    }.formStyle(.grouped).padding(.horizontal,10)
                }
                HStack {
                    if let error=host.error { Image(systemName:"exclamationmark.circle");Text(error).foregroundStyle(.orange).lineLimit(2) }
                    else { Text(host.saveMessage).foregroundStyle(.secondary) }
                    Spacer()
                    if tab != "Utilities" {Button("Undo apply") { host.undoApply() }.buttonStyle(.plain).foregroundStyle(.secondary)}
                }.font(.system(size:11)).padding(.horizontal,26).padding(.vertical,12)
            }
        }.background(Color(nsColor:.windowBackgroundColor))
    }
    private var preview:some View {
        VStack(spacing:14) {
            HStack {
                Text("Preview").font(.system(size:11,weight:.medium)).foregroundStyle(.secondary)
                Spacer()
                Picker("Preview state",selection:$sample) {
                    Text("Running").tag("Running");Text("Attention").tag("Attention");Text("Long title").tag("Long title");Text("Disconnected").tag("Disconnected")
                }.labelsHidden().frame(width:130).controlSize(.small)
            }
            HStack {
                Spacer()
                VStack(spacing:0) {
                    HStack {
                        Image(systemName:"leaf.fill").foregroundStyle(Color(islandHex:host.draft.accentHex))
                        Spacer()
                        Text("10:24").font(.system(size:10,weight:.medium)).foregroundStyle(.white.opacity(0.4))
                    }.padding(.horizontal,24).frame(height:30)
                    HStack(spacing:12) {
                        Image(systemName:sample=="Attention" ? "hand.raised" : sample=="Disconnected" ? "wifi.slash" : "timer")
                            .font(.system(size:24,weight:.light)).foregroundStyle(Color(islandHex:host.draft.accentHex))
                        VStack(alignment:.leading,spacing:5) {
                            Text(sample=="Long title" ? "A thoughtful little place for everything you’re working on" : "A little space for your day")
                                .font(.system(size:13,weight:.medium)).lineLimit(2)
                            Text(sample=="Disconnected" ? "Source disconnected" : sample=="Attention" ? "Something needs your attention" : "One thing at a time.")
                                .font(.system(size:11)).foregroundStyle(.white.opacity(0.5))
                        }
                        Spacer(minLength:0)
                    }.padding(.horizontal,24).padding(.bottom,host.draft.customBlocks.isEmpty ? 20 : 8).padding(.top,8)
                    ForEach(Array(host.draft.customBlocks.prefix(3))) { block in
                        IslandBlockView(block,action:{_ in}).font(.system(size:11)).padding(.horizontal,24).padding(.bottom,8)
                    }
                }
                .foregroundStyle(.white).frame(width:min(440,host.draft.expandedWidth))
                .background(.black,in:IslandShellShape(radius:host.draft.cornerRadius))
                Spacer()
            }
        }.padding(16).background(.primary.opacity(0.035),in:RoundedRectangle(cornerRadius:12))
    }
    private var appearance:some View {
        Group {
            Section("Appearance") {
                HStack(spacing:12) {
                    Text("Palette");Spacer()
                    ForEach(["B4C9AE","C2C4DD","D9BD99","E7A8AB","A3CCD1"],id:\.self) { hex in
                        Button { host.draft.accentHex=hex } label:{
                            Circle().fill(Color(islandHex:hex)).frame(width:22,height:22)
                                .overlay(Circle().stroke(.primary.opacity(host.draft.accentHex==hex ? 0.6 : 0),lineWidth:1).padding(-3))
                        }.buttonStyle(.plain).accessibilityLabel("Accent \(hex)")
                    }
                }
                TextField("Accent hex",text:$host.draft.accentHex)
                LabeledContent("Corners") { Slider(value:$host.draft.cornerRadius,in:4...42);Text("\(Int(host.draft.cornerRadius)) pt").monospacedDigit().frame(width:40) }
            }
            Section("Geometry") {
                LabeledContent("Expanded width") { Slider(value:$host.draft.expandedWidth,in:300...700);Text("\(Int(host.draft.expandedWidth)) pt").monospacedDigit().frame(width:50) }
                LabeledContent("Expanded height") { Slider(value:$host.draft.expandedHeight,in:160...450);Text("\(Int(host.draft.expandedHeight)) pt").monospacedDigit().frame(width:50) }
                LabeledContent("Notch wings") { Slider(value:$host.draft.wingWidth,in:36...140);Text("\(Int(host.draft.wingWidth)) pt").monospacedDigit().frame(width:50) }
                Picker("Display",selection:$host.draft.displayID) {
                    Text("Main display").tag("main")
                    ForEach(NSScreen.screens,id:\.localizedName) { screen in
                        Text(screen.localizedName).tag(String((screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber)?.uint32Value ?? 0))
                    }
                }
            }
        }
    }
    private var behavior:some View {
        Group {
            Section("Interaction") {
                Toggle("Open on hover",isOn:$host.draft.openOnHover)
                LabeledContent("Hover delay") { Slider(value:$host.draft.hoverDelay,in:0...1);Text(String(format:"%.1f s",host.draft.hoverDelay)).frame(width:40) }
                LabeledContent("Close delay") { Slider(value:$host.draft.dismissDelay,in:0.08...1);Text(String(format:"%.1f s",host.draft.dismissDelay)).frame(width:40) }
                Toggle("Hide when empty",isOn:$host.draft.hideWhenEmpty)
                Toggle("Show alongside full-screen apps",isOn:$host.draft.showInFullscreen)
                Button("Expand live island") { host.showIsland() }
            }
            Section("Alerts") {
                Toggle("Notification sounds",isOn:$host.draft.soundEnabled)
                Toggle("Quiet hours",isOn:$host.draft.quietHoursEnabled)
                if host.draft.quietHoursEnabled {
                    Stepper("From \(host.draft.quietStart):00",value:$host.draft.quietStart,in:0...23)
                    Stepper("Until \(host.draft.quietEnd):00",value:$host.draft.quietEnd,in:0...23)
                }
                Button(host.draft.bannersEnabled ? "Notifications enabled" : "Enable notifications…") { Task { await host.enableNotifications() } }
            }
        }
    }
    private var content:some View {
        Group {
            Section("Collapsed island") { Stepper("Show up to \(host.draft.compactLimit) activities",value:$host.draft.compactLimit,in:1...8) }
            Section("Expanded order") {
                ForEach(Array(host.draft.componentOrder.enumerated()),id:\.element) { index,item in
                    HStack {
                        Text(item.capitalized);Spacer()
                        Button { if index>0 { host.draft.componentOrder.swapAt(index,index-1) } } label:{Image(systemName:"arrow.up")}.disabled(index==0).help("Move up")
                        Button { if index+1<host.draft.componentOrder.count { host.draft.componentOrder.swapAt(index,index+1) } } label:{Image(systemName:"arrow.down")}.disabled(index+1==host.draft.componentOrder.count).help("Move down")
                    }
                }
            }
            Section("Your content") {
                ForEach($host.draft.customBlocks) { $block in
                    VStack(alignment:.leading,spacing:8) {
                        HStack {
                            Text(block.kind.rawValue.capitalized).font(.caption).foregroundStyle(.secondary)
                            Spacer()
                            Button { host.draft.customBlocks.removeAll{$0.id==block.id} } label:{Image(systemName:"minus.circle")}
                                .buttonStyle(.plain).help("Remove component")
                        }
                        if [.text,.button,.toggle].contains(block.kind) {
                            TextField("Text",text:Binding(get:{block.text ?? ""},set:{block.text=$0}))
                        }
                        if block.kind == .symbol {
                            TextField("SF Symbol",text:Binding(get:{block.asset ?? ""},set:{block.asset=$0}))
                        }
                        if block.kind == .button {
                            TextField("Website URL",text:Binding(get:{block.asset ?? ""},set:{block.asset=$0}))
                        }
                        if block.kind == .progress {
                            Slider(value:Binding(get:{block.value ?? 0},set:{block.value=$0}),in:0...1)
                        }
                        if block.kind == .image,let path=block.asset { Text(URL(fileURLWithPath:path).lastPathComponent).font(.caption).lineLimit(1) }
                    }.padding(.vertical,3)
                }
                Menu("Add component") {
                    ForEach([IslandBlock.Kind.text,.symbol,.progress,.timer,.button,.toggle],id:\.self) { kind in
                        Button(kind.rawValue.capitalized) { host.addBlock(kind) }
                    }
                    Button("Image…") { host.importImageBlock() }
                }
                Text("Edits appear in the preview. Apply to use them in your live island.").font(.caption).foregroundStyle(.secondary)
            }
            Section("Try it") {
                Button("Start a 5-minute focus timer") { host.startTimer() }
                Text("Publish other content with the antille command. Native apps can supply their own SwiftUI views through the library.").font(.caption).foregroundStyle(.secondary)
            }
        }
    }
    private var sources:some View {
        Group {
            Section("Pairing requests") {
                if host.pairings.isEmpty { Text("Run “antille pair --producer your.id” to connect a source.").foregroundStyle(.secondary) }
                ForEach(host.pairings) { request in
                    HStack { Text(request.id);Spacer()
                        if request.approved { Text("Approved — retry pairing").foregroundStyle(.secondary) }
                        else { Button("Allow") {host.approve(request.id)} }
                    }
                }
            }
            Section("Connected sources") {
                if host.approvedProducers.isEmpty { Text("No external sources paired.").foregroundStyle(.secondary) }
                ForEach(host.approvedProducers,id:\.self) { producer in
                    HStack { Text(producer);Spacer()
                        Toggle("Visible",isOn:Binding(get:{!host.draft.hiddenProducers.contains(producer)},set:{if $0 {host.draft.hiddenProducers.remove(producer)} else {host.draft.hiddenProducers.insert(producer)}})).toggleStyle(.checkbox)
                        Button("Revoke") {host.revoke(producer)}
                    }
                }
            }
        }
    }
}
