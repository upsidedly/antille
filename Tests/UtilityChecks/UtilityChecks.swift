// SPDX-License-Identifier: MPL-2.0
// Copyright (c) 2026 Matthew Williams

import Foundation
import Antille
@testable import AntilleApp

enum CheckFailure:Error {case failed(String,UInt)}
func require(_ condition:Bool,_ message:String,line:UInt = #line) throws {
    guard condition else {throw CheckFailure.failed(message,line)}
}
func fails(_ body:() throws ->Void) throws {
    do {try body()} catch {return};throw CheckFailure.failed("Expected failure",#line)
}
func fails<E:Error>(_ type:E.Type,_ body:() async throws ->Void) async throws {
    do {try await body()} catch is E {return};throw CheckFailure.failed("Expected \(type)",#line)
}

func checkState() throws {
    let origin=Date(timeIntervalSince1970:1000)
    var timer=IslandCountdown()
    try timer.start(seconds:90,at:origin)
    let firstSession=timer.sessionID
    timer.pause(at:origin.addingTimeInterval(30))
    try require(timer.phase == .paused && timer.remaining(at:origin.addingTimeInterval(900))==60,"Pause freezes remaining time")
    var restored=try JSONDecoder().decode(IslandCountdown.self,from:JSONEncoder().encode(timer))
    try require(restored.isValid,"Saved timer is valid")
    restored.resume(at:origin.addingTimeInterval(900))
    try require(restored.remaining(at:origin.addingTimeInterval(930))==30,"Resume uses the saved remainder")
    try require(restored.tick(at:origin.addingTimeInterval(5000)),"Elapsed deadline completes after sleep")
    try require(restored.phase == .finished && restored.remaining(at:origin)==0,"Finished timer has zero remainder")
    try require(!restored.tick(at:origin.addingTimeInterval(5001)),"Completion emits once")
    try restored.start(seconds:90,at:origin)
    try require(restored.sessionID != firstSession,"Restart creates a new celebration identity")
    restored.cancel()
    try require(restored.phase == .idle && restored.deadline==nil && restored.remaining(at:origin)==90,"Cancel returns to idle")
    for value in [Double.nan,.infinity,-1,0,86401] {try fails {try timer.start(seconds:value,at:.now)}}
    try timer.start(seconds:1,at:origin)
    try require(timer.remaining(at:origin.addingTimeInterval(-100))==1,"Clock regression cannot exceed duration")
    try require(IslandCountdown.clock(.infinity)=="00:00" && IslandCountdown.clock(.greatestFiniteMagnitude)=="1440:00","Formatting bounds nonfinite and huge values")
    try require(IslandCountdown.clock(90)=="01:30" && IslandCountdown.clock(5400,compact:true)=="1h30","Clock labels")
    let notified=IslandNowPlaying.notification(["Name":"Song, with commas 🎵","Artist":"Ártist","Player State":"Playing","Duration":"180000"],player:.spotify,at:origin)
    try require(notified.isPlaying && notified.duration==180 && notified.position==nil,"Notifications convert milliseconds without inventing position")
    let fields=["playing","Song, with commas 🎵","Ártist","Album","180000","12.5","https://i.scdn.co/image/sample","track:one"]
    let track=try IslandNowPlaying.script(fields.joined(separator:"\u{1f}"),player:.spotify,previous:nil,at:origin)
    try require(track.title==notified.title && track.artist==notified.artist,"Metadata preserves commas and Unicode")
    try require(track.position(at:origin.addingTimeInterval(5))==17.5 && track.position(at:origin.addingTimeInterval(9999))==180,"Playing position extrapolates and clamps")
    try fails {_=try IslandNowPlaying.script("incomplete",player:.spotify,previous:nil,at:origin)}
    let unknown=IslandNowPlaying.notification(["Player State":"Unexpected","Duration":"-3"],player:.music,at:origin)
    try require(unknown.playbackState == .unknown && unknown.duration==nil,"Unknown state is explicit")
    let prior=IslandNowPlaying.notification(["Name":"Known music","Artist":"Known artist","Total Time":"120000","Player State":"Playing"],player:.music,at:origin)
    let missing=["paused","","","","","30","",""].joined(separator:"\u{1f}")
    let retained=try IslandNowPlaying.script(missing,player:.music,previous:prior,at:origin)
    try require(retained.title=="Known music" && retained.artist=="Known artist" && retained.duration==120,"Music scripting regression retains notification metadata")
    try require(retained.position(at:origin.addingTimeInterval(40))==30,"Paused position stays still")
    let other=try IslandNowPlaying.script(missing,player:.spotify,previous:prior,at:origin)
    try require(other.title.isEmpty && other.duration==nil,"Metadata cannot leak across players")
    let charging=IslandPowerState(percent:120,pluggedIn:false,charging:true,minutesRemaining:-1,minutesToFull:0)
    try require(charging.percent==100 && charging.pluggedIn && charging.charging && !charging.isLow,"Charging and level bounds")
    try require(charging.minutesRemaining==nil && charging.minutesToFull==nil,"Unknown estimates are omitted")
    try require(IslandPowerState(percent:19,pluggedIn:false,charging:false).isLow && !IslandPowerState(percent:nil,pluggedIn:false,charging:false).isLow,"Low battery requires a known level")
    for raw in ["https://i.scdn.co/image/a","https://art.spotifycdn.com/a"] {try require(MusicArtwork.allowed(URL(string:raw)!),"Allow Spotify image CDN")}
    for raw in ["http://i.scdn.co/a","https://i.scdn.co.attacker.invalid/a","file:///tmp/a","https://localhost/a"] {try require(!MusicArtwork.allowed(URL(string:raw)!),"Reject untrusted artwork locations")}
}

func checkProcesses() async throws {
    let data=try await MediaCommandJob().run("return \"Local sample 🎵\"")
    try require(String(decoding:data,as:UTF8.self).trimmingCharacters(in:.newlines)=="Local sample 🎵","AppleScript output")
    try await fails(MediaCommandFailure.self) {_=try await MediaCommandJob().run("error \"sample failure\"")}
    let clock=ContinuousClock(),start=clock.now
    try await fails(MediaCommandFailure.self) {_=try await MediaCommandJob().run("delay 10",timeout:.milliseconds(100))}
    try require(start.duration(to:clock.now) < .seconds(3),"Process timeout is bounded")
    let task=Task {try await MediaCommandJob().run("delay 10")}
    try await Task.sleep(for:.milliseconds(100));task.cancel()
    try await fails(CancellationError.self) {_=try await task.value}
    try await fails(MediaCommandFailure.self) {_=try await MediaCommandJob().run("set x to \"sample\"\nrepeat 16 times\nset x to x & x\nend repeat\nreturn x")}
}

private actor PlaybackProbe {
    var requests:[Bool]=[]
    var executions=0
    var allowed=false
    func authorize(_ request:Bool)->Bool {requests.append(request);return allowed}
    func execute()->Data {executions+=1;return Data(["paused","Sample","Artist","Album","180000","12","","sample"].joined(separator:"\u{1f}").utf8)}
    func allow() {allowed=true}
}

@MainActor func checkLifecycle() async throws {
    let name="dev.upsided.antille.tests.\(UUID().uuidString)",prefs=UserDefaults(suiteName:name)!
    defer {prefs.removePersistentDomain(forName:name)}
    let probe=PlaybackProbe()
    let music=MusicBridge(fixture:false,defaults:prefs,authorize:{_,request in await probe.authorize(request)},execute:{_ in await probe.execute()},runningPlayers:{[IslandMusicPlayer.spotify.bundleID]})
    music.start();defer{music.stop()}
    await music.refresh()
    try require(music.running && !music.controlsAllowed,"Unavailable authorization is truthful")
    try require(await probe.executions==0,"Preflight denial executes no script")
    try require(await probe.requests.allSatisfy{!$0},"Background never requests permission")
    music.perform(.toggle)
    for _ in 0..<100 {if !music.busy {break};try await Task.sleep(for:.milliseconds(10))}
    try require(!music.busy && music.error?.contains("Automation settings")==true,"Denied control recovers from busy and explains access")
    let deniedExecutions=await probe.executions,deniedRequests=await probe.requests
    try require(deniedExecutions==0 && deniedRequests.contains(true),"Only explicit action requests authorization")
    await probe.allow();music.perform(.toggle)
    for _ in 0..<100 {if !music.busy {break};try await Task.sleep(for:.milliseconds(10))}
    try require(!music.busy && music.error==nil && music.snapshot?.title=="Sample","Control recovers after authorization")
    try require(await probe.executions==2,"Action followed by metadata refresh")
    music.stop()
    let utilities=UtilityController(fixture:true,defaults:prefs),store=IslandStore()
    try store.upsert(IslandActivity(producerID:"external",activityID:"head",title:"Existing head"))
    utilities.updated={try? store.replace(producerID:UtilityController.producer,with:$0)}
    utilities.start();defer{utilities.stop()}
    utilities.music.perform(.next)
    try require(utilities.music.snapshot?.title=="Another sample song","Sample next control")
    utilities.music.perform(.previous);utilities.music.perform(.toggle)
    try require(utilities.music.snapshot?.title=="Sample song" && utilities.music.snapshot?.isPlaying==false,"Sample previous and pause controls")
    utilities.music.perform(.toggle)
    try require(store.activities.count==5 && store.compactActivities.count==2,"Idle utility roster and empty note stay expanded only; active music and external head stay compact")
    utilities.startTimer(seconds:90);utilities.pauseTimer()
    let remaining=utilities.timer.pausedRemaining
    try require(remaining>89 && remaining<=90,"Controller pauses deadline")
    let restored=UtilityController(fixture:true,defaults:prefs)
    try require(restored.timer.phase == .paused && restored.timer.pausedRemaining==remaining,"Controller restores exact paused remainder")
    utilities.enableMusic(false);utilities.enablePower(false)
    try require(store.activities.count==3 && store.activities.contains{$0.producerID=="external"},"Utility preference changes retain external producers and the note")
    utilities.cancelTimer();try require(store.compactActivities.count==1,"Cancelled timer leaves compact area")
    utilities.setNote("  CARPE DIEM!!!\n")
    let note=store.activities.first{$0.activityID=="note"}
    try require(note?.compactLabel=="CARPE DIEM!!!" && note?.showsInCompact==true && note?.detail=="CARPE DIEM!!!","Saved note appears as compact text")
    utilities.showNoteInCompact(false)
    try require(store.activities.contains{$0.activityID=="note" && $0.showsInCompact==false} && store.compactActivities.count==1,"Hiding the compact note preserves its expanded card")
    let savedNote=UtilityController(fixture:true,defaults:prefs)
    try require(savedNote.noteText=="CARPE DIEM!!!" && !savedNote.noteInCompact && !savedNote.powerEnabled,"Note and visibility survive restart without enabling battery")
    utilities.showNoteInCompact(true)
    try require(store.compactActivities.contains{$0.compactLabel=="CARPE DIEM!!!"},"Restoring visibility republishes the saved note")
    utilities.setNote("\n   ")
    try require(store.activities.contains{$0.activityID=="note" && $0.showsInCompact==false && $0.compactLabel==nil},"Clearing the note leaves an empty add-note card")
    let emoji="👩🏽‍💻"
    try require(UtilityController.boundedNote(emoji+"x",byteLimit:emoji.utf8.count)==emoji,"Note bounds preserve a whole grapheme")
    try require(UtilityController.boundedNote(emoji,byteLimit:emoji.utf8.count-1).isEmpty,"Note bounds never split a grapheme")
    utilities.setNote(String(repeating:emoji,count:500))
    try require(utilities.noteText.utf8.count<=4096,"Saved note has a bounded local payload")
    for item in utilities.activities {try item.validate()}
    utilities.setNote("")
    utilities.stop()
    var expired=IslandCountdown();try expired.start(seconds:1,at:Date.now.addingTimeInterval(-10))
    prefs.set(try JSONEncoder().encode(expired),forKey:"Antille.countdown")
    let elapsed=UtilityController(fixture:true,defaults:prefs)
    var completions=0;elapsed.completed={_ in completions+=1}
    elapsed.start();try require(elapsed.timer.phase == .finished && completions==1,"Expired restored deadline finishes")
    elapsed.stop();elapsed.start();try require(completions==1,"Repeated lifecycle does not duplicate completion");elapsed.stop()
    let activity=elapsed.activities.first{$0.activityID=="timer"}
    try require(activity?.celebrationID==expired.sessionID && activity?.attention == .information,"Timer finish uses an informational celebration")
    let host=HostModel()
    for operation in ["pair","hello","upsert"] {
        let response=await host.handle(IslandRequest(operation:operation,producerID:UtilityController.producer,requestID:String(repeating:"a",count:32)))
        try require(!response.ok && response.message?.contains("reserved")==true && host.pairings.isEmpty,"External sources cannot claim the built-in utility identity")
    }
}

@main struct UtilityChecks {
    @MainActor static func main() async {
        do {try checkState();try await checkProcesses();try await checkLifecycle();print("PASS: persistent notes/visibility/Unicode bounds, timer deadlines/restoration/once-only completion, media metadata, power bounds, artwork origins, process failure/timeout/cancellation/output bounds, silent authorization and recovery, producer coexistence.")}
        catch {FileHandle.standardError.write(Data("FAIL: \(error)\n".utf8));exit(1)}
    }
}
