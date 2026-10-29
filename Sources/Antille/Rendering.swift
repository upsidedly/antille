// SPDX-License-Identifier: MPL-2.0
// Copyright (c) 2026 Matthew Williams

import SwiftUI
import AppKit

public extension IslandActivity {
    @MainActor var preferredCompactWidth:Double {
        guard let label=compactLabel,!label.isEmpty else{return 28}
        let width=(label as NSString).size(withAttributes:[.font:NSFont.systemFont(ofSize:10,weight:.semibold)]).width
        return min(160,max(44,ceil(width)+12))
    }
}

public extension Color {
    init(islandHex: String) {
        let hex=islandHex.trimmingCharacters(in:CharacterSet(charactersIn:"#"))
        let value=UInt64(hex,radix:16) ?? 0xB4C9AE
        self.init(red:Double((value>>16)&255)/255,green:Double((value>>8)&255)/255,blue:Double(value&255)/255)
    }
}
public enum IslandAsset {
    public static func allowed(_ path: String) -> Bool {
        let url=URL(fileURLWithPath:path).resolvingSymlinksInPath().standardizedFileURL
        let roots=[URL.applicationSupportDirectory.path,"/Applications",FileManager.default.homeDirectoryForCurrentUser.appending(path:"Applications").path]
        return roots.contains { url.path.hasPrefix($0+"/") }
    }
    public static func load(_ paths: [String]) -> [Data] {
        var total=0
        return paths.prefix(120).compactMap { path in
            guard allowed(path),let size=(try? URL(fileURLWithPath:path).resourceValues(forKeys:[.fileSizeKey]))?.fileSize,
                  size<4_194_304,total+size<50_331_648,let data=try? Data(contentsOf:URL(fileURLWithPath:path)) else { return nil }
            total+=size; return data
        }
    }
}
@MainActor private final class IslandFrameCache {
    static let shared=IslandFrameCache()
    private final class Frames:NSObject {let images:[NSImage];init(_ images:[NSImage]) {self.images=images}}
    private let cache=NSCache<NSString,Frames>()
    private var loading:[String:Task<[NSImage],Never>]=[:]
    private init() {cache.totalCostLimit=67_108_864}
    func load(_ paths:[String]) async -> [NSImage] {
        let key=paths.joined(separator:"\n")
        if let frames=cache.object(forKey:key as NSString) {return frames.images}
        if let task=loading[key] {return await task.value}
        let task=Task { @MainActor in
            let data=await Task.detached(priority:.utility) {IslandAsset.load(paths)}.value
            let images=data.compactMap(NSImage.init(data:))
            let cost=images.reduce(0) {$0+Int($1.size.width*$1.size.height)*4}
            cache.setObject(Frames(images),forKey:key as NSString,cost:cost)
            return images
        }
        loading[key]=task
        defer {loading.removeValue(forKey:key)}
        return await task.value
    }
}
public enum IslandSpritePlayback {
    public static func frame(at date:Date,count:Int,fps:Double,startedAt:Date?=nil,repeats:Bool=true)->Int {
        guard count>1 else{return 0}
        let rate=fps.isFinite ? min(30,max(1,fps)):12
        let elapsed=max(0,startedAt.map{date.timeIntervalSince($0)} ?? date.timeIntervalSinceReferenceDate)
        let value=floor(elapsed*rate)
        guard value.isFinite else{return repeats ? 0:count-1}
        return repeats ? Int(value.truncatingRemainder(dividingBy:Double(count))):Int(min(Double(count-1),value))
    }
}
public struct IslandSprite: View {
    public var paths: [String]
    public var fps: Double
    public var startedAt:Date?
    public var repeats:Bool
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.islandContentActive) private var contentActive
    @State private var images: [NSImage] = []
    @State private var loadedPaths:[String]=[]
    @State private var loadedFPS=12.0
    @State private var loadedStart:Date?
    @State private var loadedRepeats=true
    public init(paths: [String], fps: Double = 12,startedAt:Date?=nil,repeats:Bool=true) { self.paths=paths; self.fps=fps;self.startedAt=startedAt;self.repeats=repeats }
    public var body: some View {
        Group {
            if images.isEmpty { Image(systemName:"leaf").foregroundStyle(.secondary) }
            else if images.count==1 || reduceMotion { Image(nsImage:images[0]).resizable().scaledToFit() }
            else {
                TimelineView(.animation(minimumInterval:1/max(1,min(30,fps)),paused:!contentActive)) { context in
                    let current=loadedPaths==paths
                    let frame=IslandSpritePlayback.frame(at:context.date,count:images.count,fps:current ? fps:loadedFPS,startedAt:current ? startedAt:loadedStart,repeats:current ? repeats:loadedRepeats)
                    Image(nsImage:images[max(0,frame)]).resizable().scaledToFit()
                }
            }
        }
        .task(id:paths) {
            let paths=self.paths
            let rate=fps,start=startedAt,repeatFrames=repeats
            let loaded=await IslandFrameCache.shared.load(paths)
            guard !Task.isCancelled else { return }
            images=loaded;loadedPaths=paths;loadedFPS=rate;loadedStart=start;loadedRepeats=repeatFrames
        }
        .accessibilityHidden(true)
    }
}
public struct IslandActivityIcon: View {
    public var activity: IslandActivity
    public init(_ activity: IslandActivity) { self.activity=activity }
    public var body: some View {
        Group {
            if !activity.spriteFrames.isEmpty { IslandSprite(paths:activity.spriteFrames,fps:activity.framesPerSecond,startedAt:activity.spriteStartedAt.map{Date(timeIntervalSince1970:$0)},repeats:activity.spriteRepeats ?? true) }
            else if let path=activity.imagePath { IslandSprite(paths:[path]) }
            else { Image(systemName:activity.symbol).font(.system(size:20,weight:.medium)).foregroundStyle(Color(islandHex:activity.accentHex)) }
        }
        .opacity(activity.stale ? 0.45 : 1)
        .modifier(IslandSuccessEffect(trigger:activity.celebrationID))
        .accessibilityElement(children:.ignore)
        .accessibilityLabel(activity.title)
    }
}

public struct IslandBlockView: View {
    public let block: IslandBlock
    public var action: (String) -> Void
    @Binding private var fields:[String:String]
    @Environment(\.islandContentActive) private var contentActive
    public init(_ block: IslandBlock,fields:Binding<[String:String]> = .constant([:]),action: @escaping (String)->Void) { self.block=block; self.action=action;self._fields=fields }
    @ViewBuilder public var body: some View {
        switch block.kind {
        case .text:
            if block.markdown==true {
                if let lines=block.lineLimit {IslandMarkdownPreview(source:block.text ?? "",lines:lines).id(block.textIdentity ?? block.id)}
                else {IslandMarkdownText(block.text ?? "").id(block.textIdentity ?? block.id)}
            }
            else {Text(block.text ?? "").lineLimit(block.lineLimit).fixedSize(horizontal:false,vertical:true).textSelection(.enabled)}
        case .symbol: Image(systemName:block.asset ?? "circle")
        case .image: IslandSprite(paths:block.asset.map{[$0]} ?? []).frame(maxWidth:120,maxHeight:80)
        case .sprite: IslandSprite(paths:block.frames ?? [],fps:block.value ?? 12).frame(width:48,height:48)
        case .progress: ProgressView(value:min(1,max(0,block.value ?? 0)))
        case .timer:
            TimelineView(.animation(minimumInterval:1,paused:!contentActive)) { context in
                let remaining=max(0,(block.value ?? 0)-context.date.timeIntervalSince1970)
                Text(String(format:"%02d:%02d",Int(remaining)/60,Int(remaining)%60)).monospacedDigit()
            }
        case .button: Button(block.text ?? "Action") { if let id=block.actionID { action(id) } }.disabled(block.disabled==true)
        case .toggle: Toggle(block.text ?? "",isOn:Binding(get:{(block.value ?? 0)>0},set:{_ in if let id=block.actionID {action(id)}}))
        case .textInput:
            TextField(block.text ?? "Message",text:Binding(get:{fields[block.id] ?? ""},set:{fields[block.id]=String($0.prefix(24000))}),axis:.vertical)
                .textFieldStyle(.roundedBorder).lineLimit(1...5).disabled(block.disabled==true)
        case .choices:
            Group {
                if block.multiple==true {
                    VStack(alignment:.leading,spacing:6) {
                        ForEach(Array((block.options ?? []).enumerated()),id:\.offset) {_,option in
                            Toggle(isOn:Binding(get:{selectedValues.contains(option.value)},set:{selected in
                                var values=selectedValues
                                values.removeAll{$0==option.value};if selected {values.append(option.value)}
                                setSelection(values)
                            })) {choiceLabel(option)}.toggleStyle(.checkbox)
                        }
                    }
                } else {
                    Picker(block.text ?? "Choose an answer",selection:Binding(get:{selectedValues.first ?? ""},set:{setSelection([$0])})) {
                        ForEach(Array((block.options ?? []).enumerated()),id:\.offset) {_,option in choiceLabel(option).tag(option.value)}
                    }.pickerStyle(.radioGroup).labelsHidden()
                }
            }.disabled(block.disabled==true)
        case .hstack: HStack { children }
        case .vstack,.list: VStack(alignment:.leading,spacing:8) { children }
        case .spacer: Spacer(minLength:0)
        }
    }
    private var children: some View {
        ForEach(block.children ?? []) { child in AnyView(IslandBlockView(child,fields:$fields,action:action)) }
    }
    private var selectedValues:[String] {fields[block.id].flatMap{$0.data(using:.utf8)}.flatMap{try? JSONDecoder().decode([String].self,from:$0)} ?? []}
    private func setSelection(_ values:[String]) {
        if let data=try? JSONEncoder().encode(values) {fields[block.id]=String(decoding:data,as:UTF8.self)}
    }
    private func choiceLabel(_ option:IslandChoice)->some View {
        VStack(alignment:.leading,spacing:2) {Text(option.label);if let detail=option.detail {Text(detail).font(.system(size:10)).foregroundStyle(.secondary)}}
    }
}

public struct IslandDefaultExpanded: View {
    public let store: IslandStore
    private let icon:((IslandActivity)->AnyView)?
    private let content:((IslandActivity)->AnyView?)?
    public init(store: IslandStore,icon:((IslandActivity)->AnyView)?=nil,content:((IslandActivity)->AnyView?)?=nil) { self.store=store;self.icon=icon;self.content=content }
    @State private var fields:[String:[String:String]]=[:]
    @State private var focused:IslandActivity?
    @State private var selectorOrder:[String]=[]
    @Environment(\.islandContentActive) private var contentActive
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    private var selected: IslandActivity? {
        store.visibleActivities.first(where:{$0.id==store.selectedID}) ?? store.visibleActivities.first
    }
    public var body: some View {
        VStack(alignment:.leading,spacing:12) {
            if let activity=selected {
                if store.visibleActivities.count>1 {
                    activitySelector(selected:activity)
                }
                HStack(alignment:.top,spacing:12) {
                    iconView(activity).frame(width:activity.actionsInMenu==true ? 28:45,height:activity.actionsInMenu==true ? 34:50)
                        .modifier(ActivityDragRegion(store:store,activity:activity,regionID:"selected"))
                    VStack(alignment:.leading,spacing:4) {
                        Text(activity.title).font(.system(size:activity.actionsInMenu==true ? 13:15,weight:.semibold)).lineLimit(2)
                        HStack(spacing:5) {
                            if activity.stale { Image(systemName:"wifi.slash") }
                            Text(activity.stale ? "Source disconnected" : activity.state.replacingOccurrences(of:"_",with:" ").capitalized)
                        }.font(.system(size:11)).foregroundStyle(.white.opacity(0.55))
                    }
                    Spacer(minLength:0)
                    if activity.actionsInMenu==true,!activity.actions.isEmpty {
                        Menu {
                            ForEach(activity.actions) {action in
                                Button(action.title) {var selected=action;selected.fields=fields[activity.id];store.perform(selected,on:activity)}.disabled(activity.stale)
                            }
                        } label:{Image(systemName:"ellipsis").frame(width:24,height:24)}
                            .menuStyle(.borderlessButton).menuIndicator(.hidden).fixedSize().help("Activity actions").accessibilityLabel("Activity actions")
                    }
                    if activity.attention != .none {
                        Image(systemName:activity.attention == .error ? "exclamationmark.circle.fill" : activity.attention == .information ? "info.circle.fill":"hand.raised.fill")
                            .foregroundStyle(Color(islandHex:activity.accentHex))
                            .accessibilityLabel(activity.attention == .error ? "Failed" : activity.attention == .information ? "Information":"Needs attention")
                    }
                }
                if let nativeContent=content?(activity) {nativeContent}
                else {ForEach(store.profile.componentOrder,id:\.self) { component in
                    switch component {
                    case "detail":
                        if !activity.detail.isEmpty { Text(activity.detail).font(.system(size:12)).foregroundStyle(.white.opacity(0.7)).lineLimit(3) }
                    case "progress":
                        if let progress=activity.progress { ProgressView(value:progress).tint(Color(islandHex:store.profile.accentHex)) }
                        if let end=activity.endsAt {
                            TimelineView(.animation(minimumInterval:1,paused:!contentActive)) { context in
                                let seconds=max(0,Int(end.timeIntervalSince(context.date)))
                                Text(String(format:"%02d:%02d",seconds/60,seconds%60))
                                    .font(.system(size:30,weight:.light,design:.rounded)).monospacedDigit()
                            }
                        }
                    case "content":
                        ForEach(activity.content) { block in
                            IslandBlockView(block,fields:Binding(get:{fields[activity.id] ?? [:]},set:{fields[activity.id]=$0})) { id in
                                store.perform(IslandAction(id:id,title:id,fields:fields[activity.id]),on:activity)
                            }
                                .font(.system(size:12))
                        }
                    case "actions":
                        if !activity.actions.isEmpty,activity.actionsInMenu != true {
                            HStack {
                                ForEach(activity.actions) { action in
                                    Button(action.title) { store.perform(action,on:activity) }.disabled(activity.stale)
                                }
                            }.controlSize(.small)
                        }
                    default: EmptyView()
                    }
                }}
            } else {
                Spacer()
                HStack {
                    Image(systemName:"circle.dotted").font(.system(size:26,weight:.ultraLight))
                    VStack(alignment:.leading,spacing:4) {
                        Text("Your space, in the notch").font(.system(size:14,weight:.medium))
                        Text("Connect a source or start a timer.").font(.system(size:12)).foregroundStyle(.white.opacity(0.5))
                    }
                }
                Spacer()
            }
            if let error=store.errorMessage {
                Text(error).font(.system(size:11)).foregroundStyle(.orange).textSelection(.enabled)
            }
        }.padding(.horizontal,22).padding(.bottom,18).padding(.top,10)
        .foregroundStyle(.white).frame(maxWidth:.infinity,alignment:.topLeading)
        .onAppear {reconcileSelector();changeFocus(contentActive ? selected:nil)}
        .onChange(of:store.visibleActivities.map(\.id)) {_,_ in reconcileSelector()}
        .onChange(of:selected?.id) {_,_ in changeFocus(contentActive ? selected:nil)}
        .onChange(of:contentActive) {_,active in changeFocus(active ? selected:nil)}
        .onChange(of:selected?.formResetID) {_,_ in
            guard let activity=selected,let submitted=activity.formResetFields else{return}
            var current=fields[activity.id] ?? [:]
            for (id,value) in submitted where current[id]==value {current[id]=""}
            fields[activity.id]=current
        }
        .onDisappear {changeFocus(nil)}
    }
    private var selectorActivities:[IslandActivity] {
        let order=Dictionary(uniqueKeysWithValues:selectorOrder.enumerated().map{($0.element,$0.offset)})
        return store.visibleActivities.sorted {left,right in
            if left.attention.rank != right.attention.rank {return left.attention.rank>right.attention.rank}
            if left.priority != right.priority {return left.priority>right.priority}
            if let a=order[left.id],let b=order[right.id] {return a<b}
            if order[left.id] != nil {return true};if order[right.id] != nil {return false}
            return IslandStore.precedes(left,right)
        }
    }
    private func reconcileSelector() {
        let items=store.visibleActivities,ids=Set(items.map(\.id)),retained=selectorOrder.filter{ids.contains($0)},known=Set(retained)
        let next=retained+items.filter{!known.contains($0.id)}.map(\.id)
        if selectorOrder != next {selectorOrder=next}
    }
    private func activitySelector(selected activity:IslandActivity)->some View {
        ScrollViewReader {reader in
            HStack(spacing:8) {
                ScrollView(.horizontal) {
                    HStack(spacing:8) {
                        ForEach(selectorActivities) {item in
                            Button {store.selectedID=item.id} label:{
                                iconView(item).frame(width:30,height:34).padding(5)
                                    .background(item.id==activity.id ? .white.opacity(0.12):.clear,in:RoundedRectangle(cornerRadius:10))
                                    .modifier(ActivityDragRegion(store:store,activity:item,regionID:"tab"))
                            }.buttonStyle(.plain).help(item.title).id(item.id)
                                .accessibilityLabel(item.title).accessibilityValue(item.id==activity.id ? "Selected":"")
                                .modifier(IslandDragCapture(enabled:item.actions.contains{$0.id=="detach"}))
                                .contextMenu {ForEach(item.actions) {action in Button(action.title) {store.perform(action,on:item)}}}
                        }
                    }
                }.scrollIndicators(.never)
                Menu {
                    ForEach(selectorActivities) {item in
                        Button {store.selectedID=item.id} label:{
                            if item.id==activity.id {Label(item.title,systemImage:"checkmark")}
                            else {Text(item.title)}
                        }
                    }
                } label:{Image(systemName:"list.bullet").font(.system(size:12)).foregroundStyle(.white.opacity(0.6)).frame(width:24,height:28).contentShape(Rectangle())}
                    .menuStyle(.borderlessButton).menuIndicator(.hidden).fixedSize().help("All activities").accessibilityLabel("All activities")
            }
            .task(id:contentActive ? activity.id:nil) {
                guard contentActive else{return};await Task.yield();guard !Task.isCancelled else{return}
                withAnimation(reduceMotion ? nil:.easeOut(duration:0.14)) {reader.scrollTo(activity.id,anchor:.center)}
            }
        }
    }
    private func changeFocus(_ activity:IslandActivity?) {
        // Capture the initial choice by identity before attention sorting changes.
        if store.selectedID==nil,let activity {store.selectedID=activity.id}
        if let focused,focused.id != activity?.id,let action=focused.blurActionID {store.perform(IslandAction(id:action,title:"Hide output"),on:focused)}
        if let activity,focused?.id != activity.id,let action=activity.focusActionID {store.perform(IslandAction(id:action,title:"Show output"),on:activity)}
        focused=activity
    }
    private func iconView(_ activity:IslandActivity)->AnyView {
        AnyView((icon?(activity) ?? AnyView(IslandActivityIcon(activity))).accessibilityElement(children:.ignore).accessibilityLabel(activity.title))
    }
}
struct ActivityDragRegion:ViewModifier {
    let store:IslandStore
    let activity:IslandActivity
    let regionID:String
    @State private var instanceID=UUID().uuidString
    @Environment(\.islandContentActive) private var contentActive
    func body(content:Content)->some View {
        let registrationID=regionID+":"+instanceID
        let measured=content.background {
            GeometryReader {proxy in
                let rect=proxy.frame(in:.named("islandWindow"))
                Color.clear.onAppear {store.activityRegionHandler?(activity.id,contentActive ? rect:.zero,registrationID)}
                    .onChange(of:rect) {_,value in store.activityRegionHandler?(activity.id,contentActive ? value:.zero,registrationID)}
                    .onChange(of:contentActive) {_,active in store.activityRegionHandler?(activity.id,active ? rect:.zero,registrationID)}
                    .onChange(of:activity.id) {old,new in
                        store.activityRegionHandler?(old,.zero,registrationID)
                        store.activityRegionHandler?(new,contentActive ? rect:.zero,registrationID)
                    }
                    .onDisappear {store.activityRegionHandler?(activity.id,.zero,registrationID)}
            }
        }
        return Group {
            if let action=activity.actions.first(where:{$0.id=="detach"}) {
                measured.accessibilityAction(named:Text("Move to desktop")) {store.perform(action,on:activity)}
            } else {measured}
        }
    }
}

public struct IslandSuccessEffect:ViewModifier {
    let trigger:String?
    let amplitude:Double
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.islandContentActive) private var contentActive
    @State private var started:Date?
    public init(trigger:String?,amplitude:Double=2) {self.trigger=trigger;self.amplitude=amplitude}
    public func body(content:Content)->some View {
        Group {
            if let started {
                TimelineView(.animation(minimumInterval:1/30,paused:reduceMotion || !contentActive)) { context in
                    let t=max(0,min(1,context.date.timeIntervalSince(started)/1.2))
                    content.scaleEffect(reduceMotion ? 1:1+sin(t*Double.pi)*0.08)
                        .offset(y:reduceMotion ? 0:-sin(t*Double.pi)*amplitude)
                        .overlay(alignment:.topTrailing) {
                            Image(systemName:reduceMotion ? "checkmark":"sparkle").font(.system(size:8,weight:.bold)).foregroundStyle(.yellow)
                                .opacity(reduceMotion ? 1:1-t).offset(x:reduceMotion ? 0:3+t*3,y:reduceMotion ? 0:-t*5)
                        }
                }
            } else {content}
        }
        .task(id:trigger) {
            guard trigger != nil else {started=nil;return}
            started = .now
            do {try await Task.sleep(for:.milliseconds(1250))} catch{return}
            started=nil
        }
    }
}
