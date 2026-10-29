// SPDX-License-Identifier: MPL-2.0
// Copyright (c) 2026 Matthew Williams

import Antille
import Foundation
import IOKit.ps
import Observation

/// The run-loop source is scheduled on main and removed by the owning utility
/// controller before shutdown. No cursor/input/audio or accessibility access.
@MainActor @Observable final class PowerBridge {
    var snapshot:IslandPowerState?
    @ObservationIgnored var changed:(()->Void)?
    @ObservationIgnored private var source:CFRunLoopSource?
    @ObservationIgnored private var lowPowerObserver:NSObjectProtocol?
    private let fixture:Bool
    init(fixture:Bool=SilentCredentialPolicy.memoryOnly) {self.fixture=fixture}
    func start() {
        if fixture {snapshot=IslandPowerState(percent:62,pluggedIn:true,charging:true,minutesToFull:34);changed?();return}
        guard source==nil else{return}
        refresh()
        source=IOPSNotificationCreateRunLoopSource({context in
            guard let context else{return}
            MainActor.assumeIsolated {Unmanaged<PowerBridge>.fromOpaque(context).takeUnretainedValue().refresh()}
        },Unmanaged.passUnretained(self).toOpaque())?.takeRetainedValue()
        if let source {CFRunLoopAddSource(CFRunLoopGetMain(),source,.commonModes)}
        lowPowerObserver=NotificationCenter.default.addObserver(forName:.NSProcessInfoPowerStateDidChange,object:nil,queue:.main) { [weak self] _ in MainActor.assumeIsolated {self?.refresh()} }
    }
    func stop() {
        if let source {CFRunLoopRemoveSource(CFRunLoopGetMain(),source,.commonModes);CFRunLoopSourceInvalidate(source)}
        source=nil
        if let lowPowerObserver {NotificationCenter.default.removeObserver(lowPowerObserver)};lowPowerObserver=nil
    }
    private func refresh() {
        guard let info=IOPSCopyPowerSourcesInfo()?.takeRetainedValue(),let sources=IOPSCopyPowerSourcesList(info)?.takeRetainedValue() as? [CFTypeRef] else {snapshot=nil;changed?();return}
        for item in sources {
            guard let values=IOPSGetPowerSourceDescription(info,item)?.takeUnretainedValue() as? [String:Any],values[kIOPSTypeKey] as? String==kIOPSInternalBatteryType else{continue}
            let capacity=values[kIOPSCurrentCapacityKey] as? Int,maximum=values[kIOPSMaxCapacityKey] as? Int
            let percent=capacity.flatMap{current in maximum.flatMap{$0>0 ? Int((Double(current)/Double($0)*100).rounded()):nil}}
            let value=IslandPowerState(percent:percent,pluggedIn:values[kIOPSPowerSourceStateKey] as? String==kIOPSACPowerValue,charging:values[kIOPSIsChargingKey] as? Bool ?? false,lowPowerMode:ProcessInfo.processInfo.isLowPowerModeEnabled,minutesRemaining:values[kIOPSTimeToEmptyKey] as? Int,minutesToFull:values[kIOPSTimeToFullChargeKey] as? Int)
            if value != snapshot {snapshot=value;changed?()};return
        }
        if snapshot != nil {snapshot=nil;changed?()}
    }
}
