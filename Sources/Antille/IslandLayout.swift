// SPDX-License-Identifier: MPL-2.0
// Copyright (c) 2026 Matthew Williams

import SwiftUI
import AppKit

@MainActor enum IslandPointerLocation {
    static func screenPoint(for event:NSEvent)->CGPoint? {
        let point=event.window.map{$0.convertPoint(toScreen:event.locationInWindow)} ?? event.locationInWindow
        return point.x.isFinite && point.y.isFinite ? point:nil
    }
}

struct IslandContentKey:Hashable {
    var activityID:String
    var width:Double
}
struct IslandContentMeasurement:Equatable {
    var key:IslandContentKey
    var height:Double
}
enum IslandContentPhase {
    case unmounted,hidden,visible
    var isMounted:Bool {self != .unmounted}
}
enum IslandDiagnosticEvent {
    case hitTest,refresh,measuredContent
    case containerResize(CGRect,CGRect)
}
private struct IslandContentActiveKey:EnvironmentKey {static let defaultValue=true}
public extension EnvironmentValues {
    var islandContentActive:Bool {
        get {self[IslandContentActiveKey.self]}
        set {self[IslandContentActiveKey.self]=newValue}
    }
}
struct IslandDragCapture:ViewModifier {
    let enabled:Bool
    @ViewBuilder func body(content:Content)->some View {
        if enabled {content.highPriorityGesture(DragGesture(minimumDistance:4).onChanged{_ in})}
        else {content}
    }
}
