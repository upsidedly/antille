// SPDX-License-Identifier: MPL-2.0
// Copyright (c) 2026 Matthew Williams

import Foundation
import Observation

@MainActor @Observable
public final class IslandStore {
    public private(set) var activities: [IslandActivity] = []
    public var presentation: IslandPresentation = .collapsed
    public var profile: IslandProfile
    public var selectedID: String?
    public var errorMessage: String?
    public var actionHandler: (@MainActor (IslandActivity, IslandAction) -> Void)?
    @ObservationIgnored var activityRegionHandler:((String,CGRect,String)->Void)?
    private var generations: [String:String] = [:]
    private var removals:[String:Int]=[:]
    public init(profile: IslandProfile = IslandProfile()) { self.profile=profile }
    public var visibleActivities: [IslandActivity] {
        activities.filter { !profile.hiddenProducers.contains($0.producerID) }.sorted(by:Self.precedes)
    }
    public var compactActivities:[IslandActivity] {visibleActivities.filter{$0.showsInCompact != false}}
    static func precedes(_ left:IslandActivity,_ right:IslandActivity)->Bool {
        if left.attention.rank != right.attention.rank {return left.attention.rank>right.attention.rank}
        if left.priority != right.priority {return left.priority>right.priority}
        if left.updatedAt != right.updatedAt {return left.updatedAt>right.updatedAt}
        return left.id<right.id
    }
    public func beginGeneration(producerID: String, generation: String) {
        if generations[producerID] != generation {removals=removals.filter{!$0.key.hasPrefix(producerID+"::")}}
        generations[producerID]=generation
    }
    @discardableResult public func upsert(_ activity: IslandActivity) throws -> Bool {
        try activity.validate()
        if let generation=generations[activity.producerID], generation != activity.generation {
            throw IslandError.invalid("Update belongs to an older producer connection.")
        }
        if let removed=removals[activity.id],activity.revision<=removed {return false}
        if let index=activities.firstIndex(where:{$0.id==activity.id}) {
            let old=activities[index]
            if old.generation==activity.generation && old.revision>=activity.revision { return false }
            activities[index]=activity
        } else { activities.append(activity) }
        return true
    }
    public func remove(producerID: String, activityID: String,revision:Int?=nil) {
        if let revision,revision>=0 {
            let key=producerID+"::"+activityID
            removals[key]=max(removals[key] ?? 0,revision)
            if let current=activities.first(where:{$0.id==key}),current.revision>revision {return}
        }
        activities.removeAll {$0.producerID==producerID && $0.activityID==activityID}
        if selectedID == "\(producerID)::\(activityID)" { selectedID=nil }
    }
    public func replace(producerID: String, with incoming: [IslandActivity]) throws {
        for item in incoming { try item.validate(); guard item.producerID==producerID else { throw IslandError.invalid("Producer identity mismatch.") } }
        let ids=Set(incoming.map(\.id))
        activities.removeAll {$0.producerID==producerID && !ids.contains($0.id)}
        for item in incoming { try upsert(item) }
    }
    public func markStale(producerID: String) {
        for i in activities.indices where activities[i].producerID==producerID { activities[i].stale=true }
    }
    public func select(_ activity: IslandActivity) { selectedID=activity.id; presentation = .expanded }
    public func perform(_ action: IslandAction, on activity: IslandActivity) {
        guard !activity.stale else { errorMessage="This source is disconnected."; return }
        actionHandler?(activity,action)
    }
}
public struct IslandProfileArchive: Codable, Sendable {
    public var schemaVersion:Int = 1
    public var profiles:[IslandProfile]
    public init(profiles:[IslandProfile]) { self.profiles=profiles }
}
public actor IslandDiskStore {
    public let directory: URL
    public init(directory: URL = IslandPaths.directory) { self.directory=directory }
    public func loadProfiles() throws -> [IslandProfile] {
        let url=directory.appending(path:"profiles.json")
        guard FileManager.default.fileExists(atPath:url.path) else { return IslandProfile.presets }
        let data=try Data(contentsOf:url)
        var result:[IslandProfile]
        if let archive=try? JSONDecoder().decode(IslandProfileArchive.self,from:data) {
            guard archive.schemaVersion==1 else { throw IslandError.invalid("This profile version is not supported.") }
            result=archive.profiles
        } else { result=try JSONDecoder().decode([IslandProfile].self,from:data) }
        guard !result.isEmpty else { throw IslandError.invalid("A profile file must contain at least one profile.") }
        for index in result.indices { result[index].normalize() }
        return result
    }
    public func saveProfiles(_ profiles: [IslandProfile]) throws {
        try FileManager.default.createDirectory(at:directory,withIntermediateDirectories:true)
        let data=try JSONEncoder().encode(IslandProfileArchive(profiles:profiles))
        let url=directory.appending(path:"profiles.json")
        if FileManager.default.fileExists(atPath:url.path) {
            try? FileManager.default.removeItem(at:directory.appending(path:"profiles.previous.json"))
            try FileManager.default.copyItem(at:url,to:directory.appending(path:"profiles.previous.json"))
        }
        try data.write(to:url,options:.atomic)
    }
}
