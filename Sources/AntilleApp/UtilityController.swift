// SPDX-License-Identifier: MPL-2.0
// Copyright (c) 2026 Matthew Williams

import Antille
import Foundation
import Observation

@MainActor @Observable final class UtilityController {
    static let producer="local.utilities"
    let music:MusicBridge
    let power:PowerBridge
    let fixture:Bool
    var timer=IslandCountdown()
    var now=Date.now
    var minutes=25
    var musicEnabled:Bool
    var powerEnabled:Bool
    private(set) var noteText:String
    private(set) var noteInCompact:Bool
    var error:String?
    @ObservationIgnored var updated:(([IslandActivity])->Void)?
    @ObservationIgnored var completed:((IslandActivity)->Void)?
    @ObservationIgnored private var timerTask:Task<Void,Never>?
    @ObservationIgnored private var timerGeneration:UUID?
    @ObservationIgnored private var powerFlashTask:Task<Void,Never>?
    @ObservationIgnored private var powerFlashUntil=Date.distantPast
    @ObservationIgnored private var previousPower:IslandPowerState?
    @ObservationIgnored private var started=false
    private let generation=UUID().uuidString
    private let defaults:UserDefaults
    private var revision=0
    init(fixture:Bool=SilentCredentialPolicy.memoryOnly,defaults:UserDefaults = .standard) {
        self.fixture=fixture;self.defaults=defaults;music=MusicBridge(fixture:fixture,defaults:defaults);power=PowerBridge(fixture:fixture)
        musicEnabled=defaults.object(forKey:"Antille.musicEnabled") as? Bool ?? true
        powerEnabled=defaults.object(forKey:"Antille.powerEnabled") as? Bool ?? true
        noteText=Self.boundedNote(defaults.string(forKey:"Antille.noteText") ?? "")
        noteInCompact=defaults.object(forKey:"Antille.noteInCompact") as? Bool ?? true
        if let data=defaults.data(forKey:"Antille.countdown") {
            do {let restored=try JSONDecoder().decode(IslandCountdown.self,from:data);guard restored.isValid else{throw IslandError.invalid("The saved timer is invalid.")};timer=restored;minutes=max(1,Int(restored.duration/60))}
            catch {self.error="The saved timer could not be restored. Start a new timer to replace it."}
        }
    }
    func start() {
        guard !started else{return};started=true
        music.changed={ [weak self] in self?.publish() }
        power.changed={ [weak self] in self?.powerChanged() }
        if musicEnabled {music.start()};if powerEnabled {power.start()}
        advance();armTimer();publish()
    }
    func stop() {
        started=false;timerTask?.cancel();timerTask=nil;timerGeneration=nil;powerFlashTask?.cancel();powerFlashTask=nil
        music.stop();power.stop()
    }
    func enableMusic(_ enabled:Bool) {
        musicEnabled=enabled;defaults.set(enabled,forKey:"Antille.musicEnabled")
        if started {enabled ? music.start():music.stop()};publish()
    }
    func enablePower(_ enabled:Bool) {
        powerEnabled=enabled;defaults.set(enabled,forKey:"Antille.powerEnabled")
        if started {enabled ? power.start():power.stop()};publish()
    }
    static func boundedNote(_ text:String,byteLimit:Int=4096)->String {
        var result="",bytes=0
        for character in text {
            let size=String(character).utf8.count
            guard bytes+size<=byteLimit else{break}
            result.append(character);bytes+=size
        }
        return result.trimmingCharacters(in:.whitespacesAndNewlines)
    }
    func setNote(_ text:String) {
        noteText=Self.boundedNote(text);defaults.set(noteText,forKey:"Antille.noteText");publish()
    }
    func showNoteInCompact(_ visible:Bool) {
        noteInCompact=visible;defaults.set(visible,forKey:"Antille.noteInCompact");publish()
    }
    func startTimer(seconds:TimeInterval?=nil) {
        do {try timer.start(seconds:seconds ?? Double(minutes)*60,at:.now);error=nil;saveTimer();advance();armTimer()}
        catch {self.error=error.localizedDescription}
    }
    func pauseTimer() {advance();timer.pause(at:.now);saveTimer();armTimer();advance()}
    func resumeTimer() {timer.resume(at:.now);saveTimer();armTimer();advance()}
    func cancelTimer() {timer.cancel();saveTimer();armTimer();advance()}
    func restartTimer() {startTimer(seconds:timer.duration)}
    func handle(_ action:String) {
        switch action {
        case "start":startTimer()
        case "pause":pauseTimer()
        case "resume":resumeTimer()
        case "cancel","dismiss":cancelTimer()
        case "restart":restartTimer()
        case "previous":music.perform(.previous)
        case "toggle":music.perform(.toggle)
        case "next":music.perform(.next)
        case "open-player":music.openPlayer()
        default:break
        }
    }
    private func saveTimer() {
        do {defaults.set(try JSONEncoder().encode(timer),forKey:"Antille.countdown")}
        catch {self.error="The timer could not be saved."}
    }
    private func armTimer() {
        timerTask?.cancel();timerTask=nil;timerGeneration=nil
        guard timer.phase == .running,started else{return}
        let id=UUID();timerGeneration=id
        timerTask=Task { @MainActor [weak self] in
            defer {if let self,self.timerGeneration==id {self.timerTask=nil;self.timerGeneration=nil}}
            while !Task.isCancelled {
                do {try await Task.sleep(for:.seconds(1))} catch{return}
                guard let self,self.started,self.timerGeneration==id else{return}
                self.advance()
                if self.timer.phase != .running {return}
            }
        }
    }
    private func advance() {
        now = .now
        let finished=timer.tick(at:now)
        if finished {saveTimer()}
        publish()
        if finished,let activity=activities.first(where:{$0.activityID=="timer"}) {completed?(activity)}
    }
    private func powerChanged() {
        if let old=previousPower,let current=power.snapshot,old.pluggedIn != current.pluggedIn {
            powerFlashUntil=Date.now.addingTimeInterval(8);powerFlashTask?.cancel()
            powerFlashTask=Task { @MainActor [weak self] in
                do {try await Task.sleep(for:.seconds(8))} catch{return};self?.publish()
            }
        }
        previousPower=power.snapshot;publish()
    }
    private func publish() {guard started else{return};revision+=1;updated?(activities)}
    var activities:[IslandActivity] {
        let date=Date.now
        var result:[IslandActivity]=[]
        let hasNote = !noteText.isEmpty
        let firstLine=String(noteText.split(whereSeparator:{$0.isNewline}).first ?? "")
        let excerpt=Self.boundedNote(String(firstLine.prefix(24)),byteLimit:128)
        result.append(IslandActivity(producerID:Self.producer,activityID:"note",generation:generation,revision:revision,
            title:"Sticky note",detail:String(noteText.prefix(1000)),state:hasNote ? (noteInCompact ? "on island":"saved"):"empty",priority:60,symbol:"note.text",accentHex:"D8D3BA",
            updatedAt:date,allowsNotifications:false,actionsInMenu:true,requiresClickToExpand:true,preferredExpandedHeight:400,showsInCompact:hasNote && noteInCompact,
            compactLabel:hasNote && noteInCompact ? (excerpt.isEmpty ? "Note":excerpt):nil))
        if musicEnabled {
            let track=music.snapshot
            result.append(IslandActivity(producerID:Self.producer,activityID:"music",generation:generation,revision:revision,
                title:"Now playing",detail:track?.artist ?? "",state:music.running ? (track?.playbackState.rawValue ?? "waiting for playback"):"player closed",priority:30,symbol:"music.note",accentHex:"C9C9D4",
                actions:[IslandAction(id:"previous",title:"Previous track"),IslandAction(id:"toggle",title:track?.isPlaying==true ? "Pause":"Play"),IslandAction(id:"next",title:"Next track"),IslandAction(id:"open-player",title:"Open \(music.player.name)")],
                updatedAt:date,allowsNotifications:false,actionsInMenu:true,requiresClickToExpand:true,preferredExpandedHeight:320,showsInCompact:music.running && track?.isPlaying==true))
        }
        let remaining=timer.remaining(at:date),running=timer.phase == .running,done=timer.phase == .finished
        let actionIDs:[(String,String)]=switch timer.phase {case .idle:[("start","Start timer")];case .running:[("pause","Pause"),("cancel","Cancel")];case .paused:[("resume","Resume"),("cancel","Cancel")];case .finished:[("restart","Start again"),("dismiss","Dismiss")]}
        result.append(IslandActivity(producerID:Self.producer,activityID:"timer",generation:generation,revision:revision,
            title:done ? "Timer finished":"Timer",detail:timer.phase == .idle ? "Choose a duration":IslandCountdown.clock(remaining),state:timer.phase.rawValue,attention:done ? .information:.none,priority:50,progress:timer.phase == .idle ? nil:1-remaining/timer.duration,
            symbol:done ? "checkmark.circle":"timer",accentHex:"E0BE91",actions:actionIDs.map{IslandAction(id:$0.0,title:$0.1)},
            updatedAt:date,endsAt:running ? timer.deadline:nil,allowsNotifications:true,celebrationID:done ? timer.sessionID:nil,actionsInMenu:true,requiresClickToExpand:true,preferredExpandedHeight:320,showsInCompact:timer.phase != .idle))
        if powerEnabled {
            let value=power.snapshot
            result.append(IslandActivity(producerID:Self.producer,activityID:"power",generation:generation,revision:revision,
                title:"Power",detail:value?.status ?? "Battery information unavailable",state:value?.status ?? "unavailable",attention:value?.isLow==true ? .needsAttention:.none,priority:40,progress:value?.percent.map{Double($0)/100},symbol:value?.symbol ?? "battery.0percent",accentHex:value?.isLow==true ? "E8AD80":"B9C8CF",updatedAt:date,allowsNotifications:false,actionsInMenu:true,requiresClickToExpand:true,preferredExpandedHeight:320,showsInCompact:value?.isLow==true || date<powerFlashUntil))
        }
        return result
    }
}
