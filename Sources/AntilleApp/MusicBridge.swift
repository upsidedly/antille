// SPDX-License-Identifier: MPL-2.0
// Copyright (c) 2026 Matthew Williams

import Antille
import AppKit
import ApplicationServices
import Observation
import ImageIO

enum MusicTransport:String,Sendable {case previous,toggle,next}
enum MusicAutomation {
    /// Consent may block; every probe, including explicit requests, stays off UI.
    static func allowed(_ player:IslandMusicPlayer,request:Bool=false) async ->Bool {
        await Task.detached(priority:.utility) {
            var target=AEAddressDesc()
            let bytes=Data(player.bundleID.utf8)
            let created=bytes.withUnsafeBytes {AECreateDesc(DescType(typeApplicationBundleID),$0.baseAddress,$0.count,&target)}
            guard created==noErr else{return false}
            defer {AEDisposeDesc(&target)}
            return AEDeterminePermissionToAutomateTarget(&target,AEEventClass(typeWildCard),AEEventID(typeWildCard),request)==noErr
        }.value
    }
    static func query(_ player:IslandMusicPlayer)->String {
        // Only the closed player enum enters a script. Metadata/user input never does.
        let artwork=player == .spotify ? "set coverURL to artwork url of current track":"set coverURL to \"\""
        let identity=player == .spotify ? "set trackID to id of current track":"set trackID to persistent ID of current track"
        return """
        if not (application id "\(player.bundleID)" is running) then return ""
        with timeout of 2 seconds
            tell application id "\(player.bundleID)"
                set playback to player state as text
                set trackName to ""
                set trackArtist to ""
                set trackAlbum to ""
                set trackLength to ""
                set trackID to ""
                set coverURL to ""
                set trackPosition to ""
                try
                    set trackName to name of current track
                    set trackArtist to artist of current track
                    set trackAlbum to album of current track
                end try
                try
                    set trackLength to duration of current track
                end try
                try
                    set trackPosition to player position
                end try
                try
                    \(artwork)
                    \(identity)
                end try
            end tell
            set AppleScript's text item delimiters to character id 31
            return {playback, trackName, trackArtist, trackAlbum, trackLength, trackPosition, coverURL, trackID} as text
        end timeout
        """
    }
    static func command(_ command:MusicTransport,player:IslandMusicPlayer)->String {
        let action:String=switch command {case .previous:"previous track";case .toggle:"playpause";case .next:"next track"}
        return "if not (application id \"\(player.bundleID)\" is running) then return \"\"\nwith timeout of 2 seconds\ntell application id \"\(player.bundleID)\" to \(action)\nend timeout"
    }
}

@MainActor @Observable final class MusicBridge {
    var snapshot:IslandNowPlaying?
    var running=false
    var controlsAllowed=false
    var busy=false
    var error:String?
    var player:IslandMusicPlayer = .spotify
    var playerIcon:NSImage?
    var artwork:NSImage?
    var preferred:String
    @ObservationIgnored var changed:(()->Void)?
    @ObservationIgnored private var observers:[NSObjectProtocol]=[]
    @ObservationIgnored private var pollTask:Task<Void,Never>?
    @ObservationIgnored private var actionTask:Task<Void,Never>?
    @ObservationIgnored private var latest:[IslandMusicPlayer:IslandNowPlaying]=[:]
    @ObservationIgnored private var revision=0
    @ObservationIgnored private var actionID:UUID?
    @ObservationIgnored private var started=false
    @ObservationIgnored private var icons:[IslandMusicPlayer:NSImage]=[:]
    @ObservationIgnored private var artworkTask:Task<Void,Never>?
    @ObservationIgnored private var artworkURL:URL?
    private let fixture:Bool
    private let defaults:UserDefaults
    @ObservationIgnored private let authorize:@Sendable (IslandMusicPlayer,Bool) async ->Bool
    @ObservationIgnored private let execute:@Sendable (String) async throws ->Data
    @ObservationIgnored private let runningPlayers:@MainActor ()->Set<String>
    init(fixture:Bool=SilentCredentialPolicy.memoryOnly,defaults:UserDefaults = .standard,
         authorize:@escaping @Sendable (IslandMusicPlayer,Bool) async ->Bool = {await MusicAutomation.allowed($0,request:$1)},
         execute:@escaping @Sendable (String) async throws ->Data = {try await MediaCommandJob().run($0)},
         runningPlayers:@escaping @MainActor ()->Set<String> = {Set(NSWorkspace.shared.runningApplications.compactMap(\.bundleIdentifier))}) {
        self.fixture=fixture;self.defaults=defaults;self.authorize=authorize;self.execute=execute;self.runningPlayers=runningPlayers
        preferred=defaults.string(forKey:"Antille.musicPlayer") ?? "automatic"
        if !["automatic","spotify","music"].contains(preferred) {preferred="automatic"}
        player=IslandMusicPlayer(rawValue:preferred) ?? .spotify
    }
    func start() {
        guard !started else{return};started=true;updateIcon()
        if fixture {
            running=true;controlsAllowed=true;snapshot=IslandNowPlaying(player:player,title:"Sample song",artist:"Fixture artist",album:"Local sample",trackID:"sample-one",isPlaying:true,duration:180,position:12)
            changed?();return
        }
        for source in IslandMusicPlayer.allCases {
            observers.append(DistributedNotificationCenter.default().addObserver(forName:Notification.Name(source.notificationName),object:nil,queue:.main) { [weak self] notification in
                let keys=["Name","Artist","Album","TrackID","PersistentID","Player State","Duration","Total Time","Playback Position"]
                var fields:[String:String]=[:]
                for key in keys {if let value=notification.userInfo?[key] {fields[key]=String(String(describing:value).prefix(2000))}}
                MainActor.assumeIsolated {
                    self?.receive(fields,from:source)
                }
            })
        }
        pollTask=Task { @MainActor [weak self] in
            while !Task.isCancelled {
                guard let self else{return}
                await self.refresh()
                do {try await Task.sleep(for:.seconds(self.running && self.controlsAllowed ? 3:10))} catch{return}
            }
        }
    }
    func stop() {
        started=false
        pollTask?.cancel();pollTask=nil;actionTask?.cancel();actionTask=nil
        actionID=nil;busy=false;latest=[:];snapshot=nil;running=false;controlsAllowed=false
        artworkTask?.cancel();artworkTask=nil;artworkURL=nil;artwork=nil
        for observer in observers {DistributedNotificationCenter.default().removeObserver(observer)};observers=[]
    }
    func setPreferred(_ value:String) {
        let restart=started;stop()
        preferred=["automatic","spotify","music"].contains(value) ? value:"automatic";defaults.set(preferred,forKey:"Antille.musicPlayer");revision+=1
        player=IslandMusicPlayer(rawValue:preferred) ?? .spotify;updateIcon()
        if restart {start()};changed?()
    }
    private func receive(_ fields:[String:String],from source:IslandMusicPlayer) {
        guard started else{return}
        let incoming=IslandNowPlaying.notification(fields,player:source,at:.now)
        latest[source]=incoming
        guard preferred=="automatic" || preferred==source.rawValue else{return}
        if incoming.isPlaying || snapshot==nil || player==source {
            if player != source {controlsAllowed=false}
            revision+=1;player=source;snapshot=incoming;running=true;error=nil;updateIcon();updateArtwork();changed?()
        }
    }
    func refresh() async {
        guard started,!fixture else{return}
        let available=runningPlayers()
        latest=latest.filter{available.contains($0.key.bundleID)}
        let selected=IslandMusicPlayer(rawValue:preferred) ?? latest.values.filter{available.contains($0.player.bundleID) && $0.isPlaying}.max(by:{$0.reportedAt<$1.reportedAt})?.player ?? IslandMusicPlayer.allCases.first(where:{available.contains($0.bundleID)}) ?? .spotify
        if player != selected {player=selected;snapshot=latest[selected];controlsAllowed=false;revision+=1;updateIcon()}
        running=available.contains(selected.bundleID)
        guard running else {snapshot=nil;controlsAllowed=false;updateArtwork();changed?();return}
        let requestRevision=revision
        let allowed=await authorize(selected,false)
        guard !Task.isCancelled,revision==requestRevision,player==selected else{return}
        controlsAllowed=allowed
        guard allowed,!busy else {changed?();return}
        do {
            let data=try await execute(MusicAutomation.query(selected))
            guard !Task.isCancelled,revision==requestRevision,player==selected else{return}
            snapshot=try IslandNowPlaying.script(String(decoding:data,as:UTF8.self),player:selected,previous:snapshot,at:.now);error=nil;updateArtwork()
        } catch {if !Task.isCancelled,revision==requestRevision,player==selected {self.error=error.localizedDescription}}
        changed?()
    }
    func perform(_ command:MusicTransport) {
        guard started,!busy,running else{return}
        if fixture {
            guard var value=snapshot else{return}
            if command == .toggle {value.position=value.position(at:.now);value.isPlaying.toggle()}
            else {value.title=command == .next ? "Another sample song":"Sample song";value.trackID=value.title;value.position=0}
            value.reportedAt = .now;snapshot=value
            changed?();return
        }
        busy=true;error=nil;revision+=1
        let selected=player,id=UUID();actionID=id
        actionTask=Task { @MainActor [weak self] in
            guard let self else{return}
            defer {if actionID==id {busy=false;actionTask=nil;actionID=nil;changed?()}}
            let allowed=await authorize(selected,true)
            guard !Task.isCancelled,actionID==id,player==selected else{return}
            guard allowed else {error="Allow Antille to control \(selected.name) in macOS Automation settings.";controlsAllowed=false;return}
            controlsAllowed=true
            do {
                _=try await execute(MusicAutomation.command(command,player:selected))
                let requestRevision=revision
                let data=try await execute(MusicAutomation.query(selected))
                guard !Task.isCancelled,actionID==id,player==selected,revision==requestRevision else{return}
                snapshot=try IslandNowPlaying.script(String(decoding:data,as:UTF8.self),player:selected,previous:snapshot,at:.now);updateArtwork()
            } catch {if !Task.isCancelled,actionID==id,player==selected {self.error=error.localizedDescription}}
        }
    }
    func openPlayer() {
        guard !fixture else{return}
        guard let url=NSWorkspace.shared.urlForApplication(withBundleIdentifier:player.bundleID) else {error="\(player.name) is not installed.";changed?();return}
        NSWorkspace.shared.openApplication(at:url,configuration:NSWorkspace.OpenConfiguration())
    }
    private func updateIcon() {
        if let icon=icons[player] {playerIcon=icon;return}
        if let url=NSWorkspace.shared.urlForApplication(withBundleIdentifier:player.bundleID) {
            let icon=NSWorkspace.shared.icon(forFile:url.path);icons[player]=icon;playerIcon=icon
        } else {playerIcon=nil}
    }
    private func updateArtwork() {
        let url=snapshot?.artworkURL.flatMap{MusicArtwork.allowed($0) ? $0:nil}
        guard url != artworkURL else{return}
        artworkTask?.cancel();artworkTask=nil;artworkURL=url;artwork=nil
        guard !fixture,let url else{return}
        artworkTask=Task { @MainActor [weak self] in
            let data=await MusicArtwork.load(url)
            guard !Task.isCancelled,let self,self.artworkURL==url else{return}
            self.artwork=data.flatMap{NSImage(data:$0)};self.changed?()
        }
    }
}

private final class MusicArtworkRedirects:NSObject,URLSessionTaskDelegate {
    func urlSession(_ session:URLSession,task:URLSessionTask,willPerformHTTPRedirection response:HTTPURLResponse,newRequest request:URLRequest,completionHandler:@escaping (URLRequest?)->Void) {
        completionHandler(request.url.map{MusicArtwork.allowed($0)}==true ? request:nil)
    }
}
enum MusicArtwork {
    static func allowed(_ url:URL)->Bool {
        guard url.scheme=="https",let host=url.host?.lowercased() else{return false}
        return host=="i.scdn.co" || host.hasSuffix(".spotifycdn.com")
    }
    private static let session:URLSession = {
        let config=URLSessionConfiguration.ephemeral;config.timeoutIntervalForRequest=5;config.timeoutIntervalForResource=6
        config.urlCache=URLCache(memoryCapacity:2097152,diskCapacity:0)
        return URLSession(configuration:config,delegate:MusicArtworkRedirects(),delegateQueue:nil)
    }()
    static func load(_ url:URL) async ->Data? {
        guard allowed(url) else{return nil}
        do {
            let (data,response)=try await session.data(from:url)
            guard !Task.isCancelled,let http=response as? HTTPURLResponse,http.statusCode==200,(http.mimeType ?? "").hasPrefix("image/"),data.count<=1048576,
                  let image=CGImageSourceCreateWithData(data as CFData,nil),let properties=CGImageSourceCopyPropertiesAtIndex(image,0,nil) as? [String:Any],
                  let width=properties[kCGImagePropertyPixelWidth as String] as? Int,let height=properties[kCGImagePropertyPixelHeight as String] as? Int,
                  (1...2048).contains(width),(1...2048).contains(height) else{return nil}
            return data
        } catch {return nil}
    }
}
