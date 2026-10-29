// SPDX-License-Identifier: MPL-2.0
// Copyright (c) 2026 Matthew Williams

import AppKit
import SwiftUI

/// A native menu is built once when opened. Updating its SwiftUI source view
/// does not replace the active menu's items or reset its highlighted choice.
public struct IslandContextMenuItem {
    var title:String
    var enabled:Bool
    var checked:Bool
    var children:[Self]
    var action:(@MainActor ()->Void)?
    var separator=false
    public init(_ title:String,enabled:Bool=true,checked:Bool=false,children:[Self]=[],action:(@MainActor ()->Void)?=nil) {
        self.title=title;self.enabled=enabled;self.checked=checked;self.children=children;self.action=action
    }
    public static var separator:Self {var item=Self("");item.separator=true;return item}
}
public extension View {
    @MainActor func islandContextMenu(onOpen:@escaping @MainActor ()->Void={},onClose:@escaping @MainActor ()->Void={},items:@escaping @MainActor ()->[IslandContextMenuItem])->some View {
        modifier(IslandContextMenuModifier(items:items,onOpen:onOpen,onClose:onClose))
    }
}
private struct IslandContextMenuModifier:ViewModifier {
    let items:@MainActor ()->[IslandContextMenuItem]
    let onOpen:@MainActor ()->Void
    let onClose:@MainActor ()->Void
    @State private var handle=IslandMenuHandle()
    func body(content:Content)->some View {
        content.overlay(IslandMenuAnchor(items:items,onOpen:onOpen,onClose:onClose,handle:handle).accessibilityHidden(true))
            .accessibilityAction(named:Text("Show menu")) {handle.view?.showMenu()}
    }
}
@MainActor private final class IslandMenuHandle {weak var view:IslandContextMenuView?}
private struct IslandMenuAnchor:NSViewRepresentable {
    let items:@MainActor ()->[IslandContextMenuItem]
    let onOpen:@MainActor ()->Void
    let onClose:@MainActor ()->Void
    let handle:IslandMenuHandle
    func makeNSView(context:Context)->IslandContextMenuView {let view=IslandContextMenuView();updateNSView(view,context:context);return view}
    func updateNSView(_ view:IslandContextMenuView,context:Context) {
        view.items=items;view.onOpen=onOpen;view.onClose=onClose;handle.view=view
    }
    static func dismantleNSView(_ view:IslandContextMenuView,coordinator:()) {view.cancelMenu()}
}
@MainActor final class IslandContextMenuView:NSView,NSMenuDelegate {
    var items:(@MainActor ()->[IslandContextMenuItem])?
    var onOpen:(@MainActor ()->Void)?
    var onClose:(@MainActor ()->Void)?
    private var activeMenu:NSMenu?
    private var tracking=false
    override func hitTest(_ point:NSPoint)->NSView? {
        guard let event=NSApp.currentEvent,
              [.rightMouseDown,.rightMouseDragged,.rightMouseUp].contains(event.type) ||
                (event.type == .leftMouseDown && event.modifierFlags.contains(.control)) else{return nil}
        return super.hitTest(point)
    }
    override func acceptsFirstMouse(for event:NSEvent?)->Bool {true}
    override func rightMouseDown(with event:NSEvent) {showMenu(event:event)}
    override func mouseDown(with event:NSEvent) {
        if event.modifierFlags.contains(.control) {showMenu(event:event)} else {super.mouseDown(with:event)}
    }
    func showMenu(event:NSEvent?=nil) {
        guard activeMenu==nil,let entries=items?(),!entries.isEmpty else{return}
        let menu=makeMenu(entries);menu.delegate=self;activeMenu=menu
        defer {
            activeMenu=nil
            if tracking {tracking=false;onClose?()}
        }
        if let event {NSMenu.popUpContextMenu(menu,with:event,for:self)}
        else {menu.popUp(positioning:nil,at:CGPoint(x:bounds.midX,y:bounds.midY),in:self)}
    }
    func cancelMenu() {activeMenu?.cancelTrackingWithoutAnimation()}
    func menuWillOpen(_ menu:NSMenu) {
        guard menu===activeMenu,!tracking else{return};tracking=true;onOpen?()
    }
    func menuDidClose(_ menu:NSMenu) {
        guard menu===activeMenu,tracking else{return};tracking=false;onClose?()
    }
    private func makeMenu(_ entries:[IslandContextMenuItem])->NSMenu {
        let menu=NSMenu();menu.autoenablesItems=false
        for entry in entries {
            if entry.separator {menu.addItem(.separator());continue}
            let item=NSMenuItem(title:entry.title,action:nil,keyEquivalent:"")
            item.isEnabled=entry.enabled;item.state=entry.checked ? .on:.off
            if !entry.children.isEmpty {item.submenu=makeMenu(entry.children)}
            else if let action=entry.action {
                let command=IslandMenuCommand(action:action)
                item.target=command;item.action=#selector(IslandMenuCommand.choose(_:));item.representedObject=command
            }
            menu.addItem(item)
        }
        return menu
    }
}
@MainActor private final class IslandMenuCommand:NSObject {
    let action:@MainActor ()->Void
    init(action:@escaping @MainActor ()->Void) {self.action=action}
    @objc func choose(_ sender:NSMenuItem) {action()}
}
