// SPDX-License-Identifier: MPL-2.0
// Copyright (c) 2026 Matthew Williams

import AppKit
import Carbon

public enum IslandArrowKey:UInt32 {case up=126,down=125}

/// A standard hot key, claimed only while a consumer has an eligible hovered
/// object. It does not monitor typing or request Accessibility/Input Monitoring.
@MainActor public final class IslandHoverArrowShortcut {
    private final class Weak {weak var value:IslandHoverArrowShortcut?;init(_ value:IslandHoverArrowShortcut){self.value=value}}
    private static var registry:[UInt32:Weak]=[:]
    private static var nextID:UInt32=0
    private static var handler:EventHandlerRef?
    private let id:UInt32
    private let key:IslandArrowKey
    private let onPress:@MainActor ()->Void
    private let isEligible:@MainActor ()->Bool
    private var reference:EventHotKeyRef?
    private var requested=false
    private var menuTracking=false
    private var retryAt:TimeInterval=0
    private var observers:[NSObjectProtocol]=[]
    // Internal native boundary seams keep recovery checks off the user's arrows.
    var uptime:()->TimeInterval = {ProcessInfo.processInfo.systemUptime}
    var registerKey:(IslandArrowKey,EventHotKeyID,inout EventHotKeyRef?)->OSStatus = {key,id,reference in
        RegisterEventHotKey(key.rawValue,0,id,GetApplicationEventTarget(),0,&reference)
    }
    public var isRegistered:Bool {reference != nil}
    public init(key:IslandArrowKey,isEligible:@escaping @MainActor ()->Bool={true},onPress:@escaping @MainActor ()->Void) {
        Self.nextID &+= 1;id=Self.nextID;self.key=key;self.onPress=onPress;self.isEligible=isEligible
        Self.registry[id]=Weak(self)
        observers.append(NotificationCenter.default.addObserver(forName:NSMenu.didBeginTrackingNotification,object:nil,queue:.main) { [weak self] _ in
            MainActor.assumeIsolated {self?.menuTracking=true;self?.unregisterKey()}
        })
        observers.append(NotificationCenter.default.addObserver(forName:NSMenu.didEndTrackingNotification,object:nil,queue:.main) { [weak self] _ in
            MainActor.assumeIsolated {guard let self else{return};self.menuTracking=false;self.retryAt=0;_ = self.setEnabled(self.requested)}
        })
    }
    @discardableResult public func setEnabled(_ enabled:Bool)->Bool {
        requested=enabled
        if !enabled || !isEligible() {unregisterKey();retryAt=0;return true}
        if menuTracking {return true}
        if reference != nil {return true}
        let now=uptime()
        // A transient owner/menu can hold the key longer than one hover frame.
        // Recover on this same hover; the controller's pointer refresh retries
        // at most four times/second, stopping on success, leave, hide or close.
        guard now>=retryAt else{return false}
        if Self.handler==nil {
            var spec=EventTypeSpec(eventClass:OSType(kEventClassKeyboard),eventKind:UInt32(kEventHotKeyPressed))
            let status=InstallEventHandler(GetApplicationEventTarget(),{_,event,_ in
                guard let event else{return OSStatus(eventNotHandledErr)}
                var value=EventHotKeyID(signature:0,id:0)
                let result=GetEventParameter(event,EventParamName(kEventParamDirectObject),EventParamType(typeEventHotKeyID),nil,MemoryLayout<EventHotKeyID>.size,nil,&value)
                guard result==noErr,value.signature==0x414E544C else{return OSStatus(eventNotHandledErr)}
                let id=value.id
                Task { @MainActor in
                    guard let shortcut=IslandHoverArrowShortcut.registry[id]?.value,shortcut.reference != nil,!shortcut.menuTracking else{return}
                    guard shortcut.isEligible() else{shortcut.unregisterKey();return}
                    shortcut.onPress()
                }
                return noErr
            },1,&spec,nil,&Self.handler)
            guard status==noErr else{retryAt=now+0.25;return false}
        }
        let result=registerKey(key,EventHotKeyID(signature:0x414E544C,id:id),&reference)
        retryAt=result==noErr ? 0:now+0.25
        return result==noErr
    }
    private func unregisterKey() {if let reference {UnregisterEventHotKey(reference)};reference=nil}
    public func close() {
        requested=false;unregisterKey()
        for observer in observers {NotificationCenter.default.removeObserver(observer)};observers=[]
        Self.registry.removeValue(forKey:id)
        if Self.registry.isEmpty,let handler=Self.handler {RemoveEventHandler(handler);Self.handler=nil}
    }
}
