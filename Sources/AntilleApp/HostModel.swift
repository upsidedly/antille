// SPDX-License-Identifier: MPL-2.0
// Copyright (c) 2026 Matthew Williams

import Antille
import AppKit
import Observation
import UserNotifications
import SwiftUI

struct PairingRequest: Identifiable {
    var id: String
    var nonce: String
    var approved: Bool = false
    var token: String?
    var created: Date = .now
}
@MainActor @Observable
final class HostModel {
    let utilities=UtilityController()
    let store=IslandStore()
    var profiles: [IslandProfile] = IslandProfile.presets
    var draft=IslandProfile.presets[0]
    var pairings: [PairingRequest] = []
    var approvedProducers: [String] = []
    var status="Starting…"
    var error: String?
    var previewState="Running"
    var previewTitle="A little space for your day"
    var isReady=false
    var saveMessage=""
    private let disk=IslandDiskStore()
    private var controller:IslandController?
    private var server:IslandLocalServer?
    private var startupTask:Task<Void,Never>?
    private var pendingActions:[IslandActionEvent]=[]
    private var actionResults:[String:String]=[:]
    private var grants:[String:String]=[:]
    private var notified:Set<String>=[]
    private var previousDraft:IslandProfile?
    private var sweepTask:Task<Void,Never>?
    private var seenAt:[String:Date]=[:]
    private var rate:[String:(start:Date,count:Int)]=[:]
    private var actionWaiters:[UUID:(producer:String,excluded:Set<String>,continuation:CheckedContinuation<[IslandActionEvent],Never>)]=[:]
    private var actionTimers:[UUID:Task<Void,Never>]=[:]
    init() {}
    func start() {
        guard startupTask==nil else { return }
        startupTask=Task {
            do {
                profiles=try await disk.loadProfiles()
                draft=profiles.first(where:{$0.id==UserDefaults.standard.string(forKey:"Antille.currentProfile")}) ?? profiles[0]
                store.profile=draft
                let ids=UserDefaults.standard.stringArray(forKey:"Antille.approvedProducers") ?? []
                let stored=await Task.detached(priority:.utility) {ids.compactMap {id in IslandCredential.read("host::"+id).map{(id,$0)}}}.value
                try Task.checkCancellation()
                for (id,token) in stored {grants[id]=token;approvedProducers.append(id)}
                store.actionHandler={ [weak self] activity,action in self?.perform(activity,action) }
                let server=IslandLocalServer { [weak self] request in
                    guard let self else { return IslandResponse(ok:false,message:"Host is shutting down.") }
                    return await self.handle(request)
                }
                try await server.start()
                self.server=server
                let utilities=self.utilities
                let icon:(IslandActivity)->AnyView = {activity in
                    if activity.producerID==UtilityController.producer {return AnyView(UtilityCompactIcon(activity:activity,utilities:utilities))}
                    return AnyView(IslandActivityIcon(activity))
                }
                controller=IslandController(store:store,compact:icon,expanded:{ [weak self] in
                    guard let self else{return AnyView(EmptyView())}
                    return AnyView(IslandDefaultExpanded(store:self.store,icon:icon,showsHeader:{$0.producerID != UtilityController.producer || $0.activityID != "music"},content:{activity in
                        activity.producerID==UtilityController.producer ? AnyView(UtilityIslandContent(activityID:activity.activityID,utilities:utilities)):nil
                    }))
                });controller?.show()
                utilities.updated={ [weak self] activities in
                    guard let self else{return}
                    do {try self.store.replace(producerID:UtilityController.producer,with:activities);self.controller?.refresh()}
                    catch {self.error=error.localizedDescription}
                }
                utilities.completed={ [weak self] activity in self?.controller?.pulse();self?.notify(activity) }
                utilities.start()
                status="Ready";isReady=true;installProfileContent()
                sweepTask=Task { [weak self] in
                    while !Task.isCancelled {
                        do { try await Task.sleep(for:.seconds(10)) } catch { return }
                        guard let self else { return }
                        for (producer,seen) in seenAt where Date.now.timeIntervalSince(seen)>35 {
                            store.markStale(producerID:producer)
                        }
                        pendingActions.removeAll { Date.now.timeIntervalSince($0.createdAt)>120 }
                    }
                }
            } catch { self.error=error.localizedDescription;status="Needs attention" }
        }
    }
    func stop() {for id in Array(actionWaiters.keys) {finishWaiter(id,events:[])};startupTask?.cancel();utilities.stop();sweepTask?.cancel();server?.stop();controller?.close()}
    func showIsland() { store.presentation = .expanded;controller?.show();controller?.expand() }
    func showUtility(_ id:String) {store.selectedID=UtilityController.producer+"::"+id;showIsland()}
    func setProfile(_ id:String) {
        guard let profile=profiles.first(where:{$0.id==id}) else { return }
        draft=profile;store.profile=profile;installProfileContent();controller?.refresh()
    }
    func apply() async {
        var value=draft;value.normalize()
        previousDraft=store.profile
        if let index=profiles.firstIndex(where:{$0.id==value.id}) { profiles[index]=value } else { profiles.append(value) }
        do {
            try await disk.saveProfiles(profiles)
            draft=value;store.profile=value;installProfileContent();controller?.refresh();saveMessage="Saved"
            UserDefaults.standard.set(value.id,forKey:"Antille.currentProfile")
        } catch { self.error=error.localizedDescription;saveMessage="" }
    }
    func undoApply() {
        guard let previousDraft else { return }
        draft=previousDraft;self.previousDraft=nil
        Task { await apply() }
    }
    func duplicate() {
        var copy=draft;copy.id=UUID().uuidString;copy.name=draft.name+" copy"
        profiles.append(copy);draft=copy
    }
    func importProfile() {
        let panel=NSOpenPanel();panel.allowedContentTypes=[.json];panel.allowsMultipleSelection=false
        guard panel.runModal() == .OK,let url=panel.url else { return }
        Task {
            do {
                let data=try await Task.detached { try Data(contentsOf:url) }.value
                var profile=try JSONDecoder().decode(IslandProfile.self,from:data)
                profile.id=UUID().uuidString;profile.normalize()
                // Imports never enable previously unapproved sources or notification permissions.
                profile.bannersEnabled=false
                profiles.append(profile);draft=profile;saveMessage="Imported — apply to enable"
            } catch { self.error=error.localizedDescription }
        }
    }
    func exportProfile() {
        let panel=NSSavePanel();panel.allowedContentTypes=[.json];panel.nameFieldStringValue=draft.name+".json"
        guard panel.runModal() == .OK,let url=panel.url else { return }
        let value=draft
        Task {
            do {
                let encoder=JSONEncoder();encoder.outputFormatting=[.prettyPrinted,.sortedKeys]
                let data=try encoder.encode(value)
                try await Task.detached { try data.write(to:url,options:.atomic) }.value
                saveMessage="Exported"
            } catch { self.error=error.localizedDescription }
        }
    }
    func recoverPrevious() {
        Task {
            do {
                let url=IslandPaths.directory.appending(path:"profiles.previous.json")
                let data=try await Task.detached { try Data(contentsOf:url) }.value
                let recovered:[IslandProfile]
                if let archive=try? JSONDecoder().decode(IslandProfileArchive.self,from:data) { recovered=archive.profiles }
                else { recovered=try JSONDecoder().decode([IslandProfile].self,from:data) }
                guard let first=recovered.first else { throw IslandError.invalid("The previous profile is empty.") }
                profiles=recovered;draft=first;await apply()
            } catch { self.error=error.localizedDescription }
        }
    }
    func approve(_ producer:String) {
        guard let index=pairings.firstIndex(where:{$0.id==producer}) else { return }
        let token=UUID().uuidString+UUID().uuidString
        do {
            try IslandCredential.save(token,producer:"host::"+producer)
            grants[producer]=token;pairings[index].approved=true;pairings[index].token=token
            if !approvedProducers.contains(producer) { approvedProducers.append(producer) }
            UserDefaults.standard.set(approvedProducers,forKey:"Antille.approvedProducers")
        } catch { self.error=error.localizedDescription }
    }
    func revoke(_ producer:String) {
        grants.removeValue(forKey:producer);approvedProducers.removeAll{$0==producer};pairings.removeAll{$0.id==producer}
        for item in store.activities where item.producerID==producer { store.remove(producerID:producer,activityID:item.activityID) }
        UserDefaults.standard.set(approvedProducers,forKey:"Antille.approvedProducers")
        // Keep old Keychain item inaccessible by deleting it through the shared helper.
        IslandCredential.delete("host::"+producer)
    }
    func handle(_ request:IslandRequest) async -> IslandResponse {
        guard request.version==1 else { return IslandResponse(ok:false,message:"Unsupported protocol version.") }
        if request.operation=="ping" { return IslandResponse(message:"Antille 1.0") }
        guard let producer=request.producerID,!producer.isEmpty,producer.count<=120 else {
            return IslandResponse(ok:false,message:"A valid producer ID is required.")
        }
        guard producer != UtilityController.producer else {
            return IslandResponse(ok:false,message:"This producer identity is reserved for Antille’s built-in utilities.")
        }
        if request.operation=="pair" {
            guard let nonce=request.requestID,nonce.count>=32,nonce.count<=128 else {
                return IslandResponse(ok:false,message:"Pairing needs a private request nonce.")
            }
            pairings.removeAll { Date.now.timeIntervalSince($0.created)>600 }
            if let index=pairings.firstIndex(where:{$0.id==producer}) {
                guard pairings[index].nonce==nonce else { return IslandResponse(ok:false,message:"A pairing request already exists for this producer.") }
                if pairings[index].approved,let token=pairings[index].token {
                    pairings.remove(at:index)
                    return IslandResponse(message:"Paired",token:token)
                }
            } else if pairings.count<16 {
                pairings.append(PairingRequest(id:producer,nonce:nonce))
            }
            return IslandResponse(ok:false,message:"Approve \(producer) in Antille’s Sources tab, then retry pairing.")
        }
        guard let expected=grants[producer],let token=request.token,expected==token else {
            return IslandResponse(ok:false,message:"Source is not paired. Run pair and approve it in Antille.")
        }
        let now=Date.now
        var window=rate[producer] ?? (start:now,count:0)
        if now.timeIntervalSince(window.start)>=1 { window=(now,0) }
        guard window.count<60 else { return IslandResponse(ok:false,message:"Source update rate exceeded 60 requests per second.") }
        window.count+=1;rate[producer]=window;seenAt[producer]=now
        do {
            switch request.operation {
            case "hello":
                guard let generation=request.generation,!generation.isEmpty else { throw IslandError.invalid("A generation is required.") }
                store.beginGeneration(producerID:producer,generation:generation)
            case "pulse": controller?.pulse()
            case "magnet":
                guard let value=request.value,value.isFinite,(0...1).contains(value) else {throw IslandError.invalid("Magnet strength must be between 0 and 1.")}
                if let point=request.position,(!point.x.isFinite || !point.y.isFinite) {throw IslandError.invalid("Magnet position must be finite.")}
                controller?.setMagnet(value,at:request.position?.cgPoint)
            case "drop-session":
                guard let id=request.activityID,id.count<=200,let value=request.value,[0,1].contains(value),let revision=request.revision,revision>=0 else {throw IslandError.invalid("A valid drag session is required.")}
                controller?.setDropInteraction(sessionID:producer+"::"+id,active:value==1,revision:revision)
            case "landing":
                guard let activity=request.activity,activity.producerID==producer else {throw IslandError.invalid("A source-owned activity is required.")}
                try activity.validate()
                return IslandResponse(position:controller.map{IslandPoint($0.reserveLanding(activity))},target:controller.map{IslandBounds($0.dropTarget)})
            case "snapshot": return IslandResponse(activities:store.activities.filter{$0.producerID==producer})
            case "upsert":
                guard let activity=request.activity,activity.producerID==producer else { throw IslandError.invalid("Activity is outside the source’s scope.") }
                let changed=try store.upsert(activity)
                if changed { notify(activity) }
            case "remove":
                guard let id=request.activityID else { throw IslandError.invalid("An activity ID is required.") }
                store.remove(producerID:producer,activityID:id,revision:request.revision)
            case "stale": store.markStale(producerID:producer)
            case "actions":
                return IslandResponse(actions:pendingActions.filter{$0.producerID==producer})
            case "actions.wait":
                guard (request.excludingActionIDs?.count ?? 0)<=256 else {throw IslandError.invalid("Too many excluded action IDs.")}
                let events=await waitForActions(producer,excluding:Set(request.excludingActionIDs ?? []))
                guard grants[producer]==token else {return IslandResponse(ok:false,message:"Source access was revoked.")}
                return IslandResponse(actions:events,target:controller.map{IslandBounds($0.dropTarget)})
            case "ack":
                guard let id=request.actionID,pendingActions.contains(where:{$0.id==id && $0.producerID==producer}) else { throw IslandError.invalid("Unknown action.") }
                if let event=pendingActions.first(where:{$0.id==id && $0.producerID==producer}),event.actionID=="detach" {
                    store.remove(producerID:producer,activityID:event.activityID,revision:request.revision)
                    controller?.completeExtraction(activityID:producer+"::"+event.activityID)
                }
                pendingActions.removeAll{$0.id==id && $0.producerID==producer}
                actionResults[id]=String((request.result ?? "Done").prefix(500))
                if request.result?.hasPrefix("Error:")==true {store.errorMessage=String((request.result ?? "").dropFirst(6).prefix(500))}
                if actionResults.count>100 { actionResults.removeAll() }
            default: throw IslandError.invalid("Unknown operation.")
            }
            return IslandResponse()
        } catch { return IslandResponse(ok:false,message:error.localizedDescription) }
    }
    private func perform(_ activity:IslandActivity,_ action:IslandAction) {
        if activity.producerID==UtilityController.producer {utilities.handle(action.id);return}
        if activity.producerID=="local.profile" {
            if let block=store.profile.customBlocks.first(where:{$0.actionID==action.id}) {
                if block.kind == .button,let target=block.asset,let url=URL(string:target),["http","https"].contains(url.scheme?.lowercased() ?? "") {
                    NSWorkspace.shared.open(url)
                } else if block.kind == .toggle,let index=draft.customBlocks.firstIndex(where:{$0.id==block.id}) {
                    draft.customBlocks[index].value=(block.value ?? 0)>0 ? 0 : 1
                    Task { await apply() }
                } else { store.errorMessage="Configure this button with an http or https URL in Content." }
            }
            return
        }
        if activity.producerID=="local.timer" {
            if action.id=="stop" { utilities.cancelTimer();store.remove(producerID:activity.producerID,activityID:activity.activityID) }
            else if action.id=="restart" { startTimer() }
            return
        }
        guard pendingActions.count<100 else { store.errorMessage="Too many unanswered source actions.";return }
        if let fields=action.fields,fields.count>64 || fields.values.reduce(0,{$0+$1.utf8.count})>131072 {store.errorMessage="This form is too large to send.";return}
        pendingActions.append(IslandActionEvent(producerID:activity.producerID,activityID:activity.activityID,actionID:action.id,position:action.position,fields:action.fields))
        for (id,waiter) in actionWaiters where waiter.producer==activity.producerID {
            let ready=pendingActions.filter{$0.producerID==activity.producerID && !waiter.excluded.contains($0.id)}
            if !ready.isEmpty {finishWaiter(id,events:ready)}
        }
        store.errorMessage=nil
    }
    private func finishWaiter(_ id:UUID,events:[IslandActionEvent]) {
        actionTimers.removeValue(forKey:id)?.cancel()
        actionWaiters.removeValue(forKey:id)?.continuation.resume(returning:events)
    }
    private func waitForActions(_ producer:String,excluding:Set<String>) async -> [IslandActionEvent] {
        let existing=pendingActions.filter{$0.producerID==producer && !excluding.contains($0.id)}
        if !existing.isEmpty {return existing}
        let id=UUID()
        return await withTaskCancellationHandler {
            await withCheckedContinuation { continuation in
                if Task.isCancelled {continuation.resume(returning:[]);return}
                actionWaiters[id]=(producer,excluding,continuation)
                actionTimers[id]=Task { [weak self] in
                    do {try await Task.sleep(for:.milliseconds(1400))} catch{return}
                    self?.finishWaiter(id,events:[])
                }
            }
        } onCancel: {Task { @MainActor [weak self] in self?.finishWaiter(id,events:[]) }}
    }
    func installProfileContent() {
        guard !store.profile.customBlocks.isEmpty else {
            store.remove(producerID:"local.profile",activityID:"dashboard");return
        }
        let item=IslandActivity(producerID:"local.profile",activityID:"dashboard",revision:Int(Date.now.timeIntervalSince1970*1000),
            title:store.profile.name,state:"custom",priority:-100,symbol:"square.stack.3d.up",
            accentHex:store.profile.accentHex,content:store.profile.customBlocks)
        do { try store.upsert(item) } catch { self.error=error.localizedDescription }
    }
    func addBlock(_ kind:IslandBlock.Kind) {
        let id=UUID().uuidString
        draft.customBlocks.append(IslandBlock(id:id,kind:kind,text:kind == .text ? "Make a little room for what matters." : kind == .button ? "Open website" : kind == .toggle ? "My switch" : nil,
            value:kind == .progress ? 0.5 : kind == .timer ? Date.now.addingTimeInterval(300).timeIntervalSince1970 : 0,
            asset:kind == .symbol ? "leaf" : kind == .button ? "https://example.com" : nil,actionID:kind == .button || kind == .toggle ? id : nil))
    }
    func importImageBlock() {
        let panel=NSOpenPanel();panel.allowedContentTypes=[.png,.jpeg,.heic];panel.allowsMultipleSelection=false
        guard panel.runModal() == .OK,let url=panel.url else { return }
        Task {
            do {
                let target=IslandPaths.directory.appending(path:"assets").appending(path:UUID().uuidString+"."+url.pathExtension)
                try await Task.detached {
                    let size=try url.resourceValues(forKeys:[.fileSizeKey]).fileSize ?? Int.max
                    guard size<4_194_304 else { throw IslandError.invalid("Choose an image smaller than 4 MiB.") }
                    try FileManager.default.createDirectory(at:target.deletingLastPathComponent(),withIntermediateDirectories:true)
                    try FileManager.default.copyItem(at:url,to:target)
                }.value
                draft.customBlocks.append(IslandBlock(id:UUID().uuidString,kind:.image,asset:target.path))
            } catch { self.error=error.localizedDescription }
        }
    }
    func startTimer(seconds:TimeInterval=300) {
        utilities.startTimer(seconds:seconds);showUtility("timer")
    }
    func enableNotifications() async {
        guard !SilentCredentialPolicy.memoryOnly else {error="System alerts are disabled in the fixture app.";return}
        do {
            let allowed=try await UNUserNotificationCenter.current().requestAuthorization(options:[.alert,.sound])
            draft.bannersEnabled=allowed
            if !allowed { error="Notifications are disabled. Visual island alerts still work." }
        } catch { self.error=error.localizedDescription }
    }
    private func notify(_ activity:IslandActivity) {
        guard !SilentCredentialPolicy.memoryOnly,activity.allowsNotifications,activity.attention != .none,!activity.stale,!store.profile.mutedProducers.contains(activity.producerID) else { return }
        let key=activity.id+"::"+activity.generation+"::"+activity.state+"::"+(activity.celebrationID ?? "")
        guard notified.insert(key).inserted else { return }
        if notified.count>1000 { notified=[key] }
        let profile=store.profile
        if profile.quietHoursEnabled {
            let hour=Calendar.current.component(.hour,from:.now)
            let quiet=profile.quietStart>profile.quietEnd ? (hour>=profile.quietStart || hour<profile.quietEnd) : (hour>=profile.quietStart && hour<profile.quietEnd)
            if quiet { return }
        }
        guard profile.bannersEnabled else { return }
        let content=UNMutableNotificationContent();content.title=activity.title;content.body=activity.detail
        if profile.soundEnabled { content.sound = .default }
        content.userInfo=["activityID":activity.id]
        UNUserNotificationCenter.current().add(UNNotificationRequest(identifier:key,content:content,trigger:nil)) { error in
            if let error { Task { @MainActor [weak self] in self?.error=error.localizedDescription } }
        }
    }
}
