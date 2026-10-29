// SPDX-License-Identifier: MPL-2.0
// Copyright (c) 2026 Matthew Williams

import Foundation

public struct IslandCountdown:Codable,Equatable,Sendable {
    public enum Phase:String,Codable,Sendable {case idle,running,paused,finished}
    public private(set) var phase:Phase = .idle
    public private(set) var duration:TimeInterval=1500
    public private(set) var deadline:Date?
    public private(set) var pausedRemaining:TimeInterval=1500
    public private(set) var sessionID=UUID().uuidString
    public init() {}
    public var isValid:Bool {
        duration.isFinite && (1...86400).contains(duration) && pausedRemaining.isFinite && (0...duration).contains(pausedRemaining) &&
        (phase == .running ? deadline?.timeIntervalSince1970.isFinite==true:deadline==nil)
    }
    public func remaining(at now:Date)->TimeInterval {
        switch phase {case .running:max(0,min(duration,deadline?.timeIntervalSince(now) ?? 0));case .paused:pausedRemaining;case .finished:0;case .idle:duration}
    }
    public mutating func start(seconds:TimeInterval,at now:Date) throws {
        guard seconds.isFinite,(1...86400).contains(seconds) else {throw IslandError.invalid("Choose a timer between one second and 24 hours.")}
        duration=seconds;pausedRemaining=seconds;deadline=now.addingTimeInterval(seconds);phase = .running;sessionID=UUID().uuidString
    }
    public mutating func pause(at now:Date) {
        guard phase == .running else{return}
        if tick(at:now) {return}
        pausedRemaining=remaining(at:now);deadline=nil;phase = .paused
    }
    public mutating func resume(at now:Date) {
        guard phase == .paused else{return}
        deadline=now.addingTimeInterval(pausedRemaining);phase = .running
    }
    public mutating func cancel() {deadline=nil;phase = .idle;pausedRemaining=duration}
    @discardableResult public mutating func tick(at now:Date)->Bool {
        guard phase == .running,let deadline,deadline<=now else{return false}
        self.deadline=nil;pausedRemaining=0;phase = .finished;return true
    }
    public static func clock(_ seconds:TimeInterval,compact:Bool=false)->String {
        let value=seconds.isFinite ? Int(max(0,min(86400,ceil(seconds)))):0
        if compact,value>=3600 {return "\(value/3600)h\((value%3600)/60)"}
        return String(format:"%02d:%02d",value/60,value%60)
    }
}

public enum IslandMusicPlayer:String,Codable,CaseIterable,Sendable {
    case spotify,music
    public var name:String {self == .spotify ? "Spotify":"Music"}
    public var bundleID:String {self == .spotify ? "com.spotify.client":"com.apple.Music"}
    public var notificationName:String {self == .spotify ? "com.spotify.client.PlaybackStateChanged":"com.apple.Music.playerInfo"}
}
public struct IslandNowPlaying:Equatable,Sendable {
    public enum PlaybackState:String,Sendable {case playing,paused,stopped,unknown}
    public var player:IslandMusicPlayer
    public var title:String
    public var artist:String
    public var album:String
    public var trackID:String
    public var playbackState:PlaybackState
    public var isPlaying:Bool {get{playbackState == .playing}set{playbackState=newValue ? .playing:.paused}}
    public var duration:Double?
    public var position:Double?
    public var artworkURL:URL?
    public var reportedAt:Date
    public init(player:IslandMusicPlayer,title:String,artist:String="",album:String="",trackID:String="",isPlaying:Bool=false,duration:Double?=nil,position:Double?=nil,artworkURL:URL?=nil,reportedAt:Date = .now,playbackState:PlaybackState?=nil) {
        self.player=player;self.title=String(title.prefix(500));self.artist=String(artist.prefix(500));self.album=String(album.prefix(500));self.trackID=String(trackID.prefix(500));self.playbackState=playbackState ?? (isPlaying ? .playing:.paused)
        self.duration=duration.flatMap{$0.isFinite && $0>0 && $0<=172800 ? $0:nil}
        self.position=position.flatMap{$0.isFinite && $0>=0 ? min(172800,$0):nil};self.artworkURL=artworkURL;self.reportedAt=reportedAt
    }
    public func position(at now:Date)->Double? {
        position.map{min(duration ?? 172800,$0+(isPlaying ? max(0,now.timeIntervalSince(reportedAt)):0))}
    }
    public static func notification(_ values:[String:String],player:IslandMusicPlayer,at now:Date)->Self {
        let milliseconds=Double(values[player == .spotify ? "Duration":"Total Time"] ?? "")
        return Self(player:player,title:values["Name"] ?? "",artist:values["Artist"] ?? "",album:values["Album"] ?? "",trackID:values["TrackID"] ?? values["PersistentID"] ?? "",duration:milliseconds.map{$0/1000},position:Double(values["Playback Position"] ?? ""),reportedAt:now,playbackState:PlaybackState(rawValue:values["Player State"]?.lowercased() ?? "") ?? .unknown)
    }
    public static func script(_ output:String,player:IslandMusicPlayer,previous:Self?,at now:Date) throws ->Self {
        let fields=output.trimmingCharacters(in:.newlines).components(separatedBy:"\u{1f}")
        guard fields.count==8 else{throw IslandError.invalid("The player returned incomplete playback information.")}
        let hasTitle = !fields[1].isEmpty && fields[1] != "missing value"
        let prior=previous?.player==player ? previous:nil
        let length=Double(fields[4]).map{$0/(player == .spotify ? 1000:1)}
        return Self(player:player,title:hasTitle ? fields[1]:(prior?.title ?? ""),artist:hasTitle ? fields[2]:(prior?.artist ?? ""),album:hasTitle ? fields[3]:(prior?.album ?? ""),trackID:hasTitle ? fields[7]:(prior?.trackID ?? ""),duration:hasTitle ? length:(length ?? prior?.duration),position:Double(fields[5]),artworkURL:hasTitle ? (fields[6].isEmpty ? nil:URL(string:fields[6])):prior?.artworkURL,reportedAt:now,playbackState:PlaybackState(rawValue:fields[0]) ?? .unknown)
    }
}

public struct IslandPowerState:Equatable,Sendable {
    public var percent:Int?
    public var pluggedIn:Bool
    public var charging:Bool
    public var lowPowerMode:Bool
    public var minutesRemaining:Int?
    public var minutesToFull:Int?
    public init(percent:Int?,pluggedIn:Bool,charging:Bool,lowPowerMode:Bool=false,minutesRemaining:Int?=nil,minutesToFull:Int?=nil) {
        self.percent=percent.map{min(100,max(0,$0))};self.pluggedIn=pluggedIn || charging;self.charging=charging;self.lowPowerMode=lowPowerMode
        self.minutesRemaining=minutesRemaining.flatMap{$0>0 ? $0:nil};self.minutesToFull=minutesToFull.flatMap{$0>0 ? $0:nil}
    }
    public var isLow:Bool {(percent ?? 100)<=20 && !pluggedIn}
    public var symbol:String {
        if charging {return "battery.100percent.bolt"}
        let value=percent ?? 0
        return value<=10 ? "battery.0percent":value<=30 ? "battery.25percent":value<=60 ? "battery.50percent":value<=85 ? "battery.75percent":"battery.100percent"
    }
    public var status:String {
        if charging {return "Charging"}
        if pluggedIn {return percent==100 ? "Fully charged":"Connected to power"}
        return percent==nil ? "Power information unavailable":"On battery"
    }
}
