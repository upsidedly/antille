// SPDX-License-Identifier: MPL-2.0
// Copyright (c) 2026 Matthew Williams

import Foundation
import CoreGraphics

public enum IslandAttention: String, Codable, Sendable, CaseIterable {
    case none, information, needsAttention, error
    public var rank: Int {
        switch self { case .none: 0; case .information: 1; case .needsAttention: 3; case .error: 2 }
    }
}

public struct IslandPoint:Codable,Hashable,Sendable {
    public var x:Double
    public var y:Double
    public init(x:Double,y:Double) {self.x=x;self.y=y}
    public init(_ point:CGPoint) {x=point.x;y=point.y}
    public var cgPoint:CGPoint {CGPoint(x:x,y:y)}
}
public struct IslandBounds:Codable,Equatable,Sendable {
    public var x:Double;public var y:Double;public var width:Double;public var height:Double
    public init(_ rect:CGRect) {x=rect.minX;y=rect.minY;width=rect.width;height=rect.height}
    public var cgRect:CGRect {CGRect(x:x,y:y,width:width,height:height)}
}
public struct IslandAction: Codable, Identifiable, Hashable, Sendable {
    public var id: String
    public var title: String
    public var position:IslandPoint?
    public var fields:[String:String]?
    public init(id: String, title: String,position:IslandPoint?=nil,fields:[String:String]?=nil) {self.id=id;self.title=title;self.position=position;self.fields=fields}
}

public struct IslandBlock: Codable, Identifiable, Equatable, Sendable {
    public enum Kind: String, Codable, Sendable, CaseIterable {
        case text, symbol, image, sprite, progress, timer, button, toggle, textInput, choices, hstack, vstack, list, spacer
    }
    public var id: String
    public var kind: Kind
    public var text: String?
    public var value: Double?
    public var asset: String?
    public var frames: [String]?
    public var actionID: String?
    public var children: [IslandBlock]?
    public var options:[IslandChoice]?
    public var multiple:Bool?
    public var disabled:Bool?
    public var lineLimit:Int?
    public var markdown:Bool?
    public var textIdentity:String?
    public init(id: String, kind: Kind, text: String? = nil, value: Double? = nil, asset: String? = nil,
                frames: [String]? = nil, actionID: String? = nil, children: [IslandBlock]? = nil,options:[IslandChoice]?=nil,multiple:Bool?=nil,disabled:Bool?=nil,lineLimit:Int?=nil,markdown:Bool?=nil,textIdentity:String?=nil) {
        self.id=id; self.kind=kind; self.text=text; self.value=value; self.asset=asset
        self.frames=frames; self.actionID=actionID; self.children=children
        self.options=options;self.multiple=multiple;self.disabled=disabled;self.lineLimit=lineLimit
        self.markdown=markdown;self.textIdentity=textIdentity
    }
    public func validate(depth: Int = 0) throws {
        guard depth < 8, (children?.count ?? 0) <= 64, (frames?.count ?? 0) <= 120,
              (text?.utf8.count ?? 0) <= 4096,(options?.count ?? 0)<=32 else { throw IslandError.invalid("Content is too large or deeply nested.") }
        if let value, !value.isFinite { throw IslandError.invalid("Content values must be finite.") }
        for child in children ?? [] { try child.validate(depth: depth+1) }
    }
}
public struct IslandChoice:Codable,Equatable,Sendable {
    public var label:String
    public var value:String
    public var detail:String?
    public init(label:String,value:String,detail:String?=nil) {self.label=label;self.value=value;self.detail=detail}
}

public enum IslandError: LocalizedError, Sendable {
    case invalid(String), unavailable(String)
    public var errorDescription: String? {
        switch self { case .invalid(let message), .unavailable(let message): message }
    }
}

public struct IslandActivity: Codable, Identifiable, Equatable, Sendable {
    public var id: String { "\(producerID)::\(activityID)" }
    public var producerID: String
    public var activityID: String
    public var generation: String
    public var revision: Int
    public var title: String
    public var detail: String
    public var state: String
    public var attention: IslandAttention
    public var priority: Int
    public var progress: Double?
    public var symbol: String
    public var accentHex: String
    public var imagePath: String?
    public var spriteFrames: [String]
    public var framesPerSecond: Double
    /// Fractional Unix seconds keep one-shot playback in sync across processes.
    public var spriteStartedAt:TimeInterval?
    public var spriteRepeats:Bool?
    public var actionsInMenu:Bool?
    public var requiresClickToExpand:Bool?
    public var preferredExpandedHeight:Double?
    /// False keeps an activity in the expanded roster without a compact slot.
    public var showsInCompact:Bool?
    public var actions: [IslandAction]
    public var content: [IslandBlock]
    public var updatedAt: Date
    public var endsAt: Date?
    public var allowsNotifications: Bool
    public var stale: Bool
    public var focusActionID:String?
    public var blurActionID:String?
    public var celebrationID:String?
    public var formResetID:String?
    public var formResetFields:[String:String]?
    public var compactLabel:String?
    public init(producerID: String, activityID: String, generation: String = "default", revision: Int = 1,
                title: String, detail: String = "", state: String = "running",
                attention: IslandAttention = .none, priority: Int = 0, progress: Double? = nil,
                symbol: String = "sparkle", accentHex: String = "BCD4BE", imagePath: String? = nil,
                spriteFrames: [String] = [], framesPerSecond: Double = 12, actions: [IslandAction] = [],
                content: [IslandBlock] = [], updatedAt: Date = .now, endsAt: Date? = nil, stale: Bool = false, allowsNotifications: Bool = true,focusActionID:String?=nil,blurActionID:String?=nil,celebrationID:String?=nil,formResetID:String?=nil,formResetFields:[String:String]?=nil,spriteStartedAt:TimeInterval?=nil,spriteRepeats:Bool?=nil,actionsInMenu:Bool?=nil,requiresClickToExpand:Bool?=nil,preferredExpandedHeight:Double?=nil,showsInCompact:Bool?=nil,compactLabel:String?=nil) {
        self.producerID=producerID; self.activityID=activityID; self.generation=generation; self.revision=revision
        self.title=title; self.detail=detail; self.state=state; self.attention=attention; self.priority=priority
        self.progress=progress; self.symbol=symbol; self.accentHex=accentHex; self.imagePath=imagePath
        self.spriteFrames=spriteFrames; self.framesPerSecond=framesPerSecond; self.actions=actions
        self.content=content; self.updatedAt=updatedAt; self.endsAt=endsAt; self.stale=stale;self.allowsNotifications=allowsNotifications
        self.focusActionID=focusActionID;self.blurActionID=blurActionID;self.celebrationID=celebrationID
        self.formResetID=formResetID;self.formResetFields=formResetFields
        self.spriteStartedAt=spriteStartedAt;self.spriteRepeats=spriteRepeats;self.actionsInMenu=actionsInMenu;self.requiresClickToExpand=requiresClickToExpand
        self.preferredExpandedHeight=preferredExpandedHeight
        self.showsInCompact=showsInCompact
        self.compactLabel=compactLabel
    }
    public func validate() throws {
        guard !producerID.isEmpty, !activityID.isEmpty, producerID.count <= 120, activityID.count <= 200,
              title.count <= 500, detail.count <= 4000, revision >= 0, (-1000...1000).contains(priority),
              actions.count <= 16, content.count <= 64, spriteFrames.count <= 120,
              framesPerSecond.isFinite, (1...30).contains(framesPerSecond) else {
            throw IslandError.invalid("Activity identity, size, or playback settings are invalid.")
        }
        if let progress, !progress.isFinite || !(0...1).contains(progress) {
            throw IslandError.invalid("Progress must be between 0 and 1.")
        }
        if let spriteStartedAt,!spriteStartedAt.isFinite {throw IslandError.invalid("Sprite start time is invalid.")}
        if let preferredExpandedHeight,(!preferredExpandedHeight.isFinite || !(160...640).contains(preferredExpandedHeight)) {throw IslandError.invalid("Preferred expanded height is invalid.")}
        if let compactLabel,compactLabel.utf8.count>256 {throw IslandError.invalid("Compact text is too long.")}
        for block in content { try block.validate() }
    }
}

public struct IslandProfile: Codable, Identifiable, Equatable, Sendable {
    public var id: String = UUID().uuidString
    public var name: String = "My island"
    public var fillHex: String = "000000"
    public var accentHex: String = "B4C9AE"
    public var wingWidth: Double = 68
    public var expandedWidth: Double = 420
    public var expandedHeight: Double = 270
    public var cornerRadius: Double = 24
    public var hoverDelay: Double = 0.3
    public var dismissDelay: Double = 0.18
    public var openOnHover: Bool = true
    public var hideWhenEmpty: Bool = false
    public var showInFullscreen: Bool = true
    public var displayID: String = "main"
    public var soundEnabled: Bool = false
    public var bannersEnabled: Bool = false
    public var quietStart: Int = 22
    public var quietEnd: Int = 8
    public var quietHoursEnabled: Bool = false
    public var mutedProducers: Set<String> = []
    public var hiddenProducers: Set<String> = []
    public var componentOrder: [String] = ["detail", "progress", "content", "actions"]
    public var compactLimit: Int = 4
    public var customBlocks: [IslandBlock] = []
    public init(name: String = "My island") { self.name=name }
    public mutating func normalize() {
        if ["101311","17191E","142019","101712"].contains(fillHex.uppercased()) { fillHex="000000" }
        wingWidth=wingWidth.isFinite ? min(140,max(36,wingWidth)) : 68
        expandedWidth=expandedWidth.isFinite ? min(780,max(300,expandedWidth)) : 420
        expandedHeight=expandedHeight.isFinite ? min(600,max(160,expandedHeight)) : 270
        cornerRadius=cornerRadius.isFinite ? min(48,max(4,cornerRadius)) : 24
        hoverDelay=hoverDelay.isFinite ? min(1.5,max(0,hoverDelay)) : 0.3
        dismissDelay=dismissDelay.isFinite ? min(2,max(0.08,dismissDelay)) : 0.18
        compactLimit=min(8,max(1,compactLimit))
        quietStart=min(23,max(0,quietStart)); quietEnd=min(23,max(0,quietEnd))
        let allowed=["detail","progress","content","actions"]
        var seen=Set<String>()
        componentOrder=componentOrder.filter { allowed.contains($0) && seen.insert($0).inserted }
        if componentOrder.isEmpty { componentOrder=allowed }
    }
    public static var presets: [IslandProfile] {
        var quiet=IslandProfile(name:"Quiet"); quiet.wingWidth=52; quiet.expandedWidth=380
        var studio=IslandProfile(name:"Studio"); studio.fillHex="000000"; studio.accentHex="C2C4DD"; studio.expandedWidth=500
        var garden=IslandProfile(name:"Garden"); garden.fillHex="000000"; garden.accentHex="BED59B"; garden.wingWidth=88
        return [quiet,studio,garden]
    }
}

public struct IslandGeometry: Equatable, Sendable {
    public var screen: CGRect
    public var cutoutWidth: Double
    public var topInset: Double
    public init(screen: CGRect, cutoutWidth: Double, topInset: Double) {
        self.screen=screen; self.cutoutWidth=max(0,cutoutWidth); self.topInset=max(0,topInset)
    }
    public var headerHeight: Double { max(36,topInset) }
    public func compactSlotWidths(profile:IslandProfile,activityCount:Int,preferred:[Double]=[],leadingSlotCount:Int?=nil)->[Double] {
        let count=min(max(0,activityCount),max(0,profile.compactLimit)),left=min(count,max(0,leadingSlotCount ?? (count+1)/2))
        var widths=(0..<count).map {i in i<preferred.count && preferred[i].isFinite ? min(160,max(28,preferred[i])):28}
        for range in [0..<left,left..<count] where !range.isEmpty {
            let overflow=range.lowerBound==left && activityCount>profile.compactLimit ? 29.0:0
            let budget=max(0,(screen.width-24-cutoutWidth)/2-22-overflow-Double(max(0,range.count-1))*5)
            let total=range.reduce(0.0){$0+widths[$1]},shrinkable=range.reduce(0.0){$0+max(0,widths[$1]-28)}
            if total>budget,shrinkable>0 {
                let fraction=min(1,(total-budget)/shrinkable)
                for i in range {widths[i]-=max(0,widths[i]-28)*fraction}
            }
        }
        return widths
    }
    public func landingSlot(index:Int,profile:IslandProfile,activityCount:Int,slotWidths:[Double]=[],leadingSlotCount:Int?=nil)->CGPoint? {
        guard index>=0,index<activityCount else{return nil}
        let widths=compactSlotWidths(profile:profile,activityCount:activityCount,preferred:slotWidths,leadingSlotCount:leadingSlotCount)
        let count=widths.count,left=min(count,max(0,leadingSlotCount ?? (count+1)/2))
        let x:Double
        if index>=count {x=screen.midX+cutoutWidth/2+20+widths[left..<count].reduce(0,+)+Double(count-left)*5}
        else if index<left {x=screen.midX-cutoutWidth/2-8-widths[index]/2-widths[(index+1)..<left].reduce(0,+)-Double(left-index-1)*5}
        else {x=screen.midX+cutoutWidth/2+8+widths[index]/2+widths[left..<index].reduce(0,+)+Double(index-left)*5}
        return CGPoint(x:x,y:screen.maxY-headerHeight/2)
    }
    public func frame(profile: IslandProfile, expanded: Bool,activityCount:Int=0,slotWidths:[Double]=[],leadingSlotCount:Int?=nil) -> CGRect {
        let widths=compactSlotWidths(profile:profile,activityCount:activityCount,preferred:slotWidths,leadingSlotCount:leadingSlotCount),count=widths.count,left=min(count,max(0,leadingSlotCount ?? (count+1)/2))
        let leading=widths[0..<left].reduce(0,+)+Double(max(0,left-1))*5
        let trailing=widths[left..<count].reduce(0,+)+Double(max(0,count-left-1))*5+(activityCount>profile.compactLimit ? (count>left ? 29:24):0)
        let leadingWing=max(profile.wingWidth,leading+22),trailingWing=max(profile.wingWidth,trailing+22)
        let compactWidth=max(184,cutoutWidth+leadingWing+trailingWing)
        let width=min(screen.width-24,expanded ? max(profile.expandedWidth,compactWidth) : compactWidth)
        let height=expanded ? min(screen.height-40,profile.expandedHeight+headerHeight) : headerHeight
        let clearance=max(0,(screen.width-24-width)/2)
        let offset=min(clearance,max(-clearance,(trailingWing-leadingWing)/2))
        return CGRect(x:screen.midX-width/2+offset,y:screen.maxY-height,width:width,height:height)
    }
}

public enum IslandPresentation: String, Sendable {
    case collapsed, expanded, pinned, hidden
    public var isExpanded: Bool { self == .expanded || self == .pinned }
}
