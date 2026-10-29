# Antille integration

## Embed in a native app

Add this directory as a local Swift package dependency and import the `Antille` library. Retain the store and controller for the lifetime of the surface:

```swift
import Antille
import SwiftUI

@MainActor
func makeIsland() throws -> IslandController {
    let store = IslandStore()
    try store.upsert(IslandActivity(
        producerID: "my.app", activityID: "download",
        title: "Downloading", progress: 0.4, symbol: "arrow.down"
    ))
    let controller = IslandController(store: store)
    controller.show()
    return controller
}
```

`IslandController` accepts custom compact and expanded SwiftUI view providers. The compact provider is reused by the default expanded selector and extraction preview. `IslandStore` owns activities, profile, selection, presentation, and named action callbacks. Call `close()` to remove observers/monitors; `hide()` preserves the controller without reopening on store updates.

The expanded body keeps its resolved target dimensions while one black outer mask animates. Ordinary collapse retains the mounted body and local drafts. Custom content should read `@Environment(\.islandContentActive)` and pause animation clocks, focus requests, subscriptions and drag regions while it is false. The default is true outside the expanded pane, so compact and desktop views remain active. Hidden content is excluded from hit testing and accessibility; `hide()` and `close()` cancel pending presentation work.

Use `dismiss()` for an explicit close, Escape or repeated selection: it releases a pin. `collapse()` is an automatic dismissal that respects a pin. `activateCompact(_:)` selects and opens a different activity, or dismisses the current open selection. Compact items are native buttons; the overflow and expanded All activities menus keep off-screen items reachable. Updates to a streamed timestamp preserve compact positions within the same attention/priority rank.

`islandContextMenu(onOpen:onClose:items:)` builds an AppKit menu once per opening instead of rebuilding its native items with every SwiftUI refresh. Return `IslandContextMenuItem` values with actions, `enabled`, `checked`, `children` or `.separator`. Resolve current domain state inside an action when it is chosen; the visible choices remain a snapshot until close. The optional lifecycle callbacks allow a moving source to pause and resume. Ordinary left clicks, hover and drags pass through; right-click, Control-click and an accessible Show menu action open it. The controller uses this for compact activity actions, deferring compact roster/layout changes until close while the store continues accepting updates. No additional permission is required.

`IslandDefaultExpanded(store:icon:content:)` can replace only a selected activity's body while retaining the shared roster, header, field identity and focus lifecycle. Return `nil` from `content` to use the ordinary component renderer. Antille's own music, timer and power consumers use this override under the reserved host identity `local.utilities`; external producers retain their existing data renderer. The library's countdown, now-playing and power value types do not launch system services.

Use `dropTarget`, `reserveLanding(_:)`, `setDropInteraction(sessionID:active:revision:)`, `setMagnet(_:at:)`, and `pulse()` for direct manipulation. Refresh active drop sessions at least every three seconds. Drop mode suppresses ordinary content and presents a liquid receptive target. Reservations grow the wings before landing and avoid the camera cutout. A `detach` action opts into extraction and a named accessibility equivalent. Call `completeExtraction(activityID:)` when the desktop view exists.

The engine handles camera-cutout safe areas, top-center placement on notchless displays, transparent hit regions, hover dwell, Escape, pinning, screen changes, and native overlay lifecycle. Each controller targets one display.

## Publish from another app or script

```sh
dist/antille pair --producer my.tool
# Approve my.tool in Antille's Sources tab, then repeat the pair command.
dist/antille publish --producer my.tool --id build --title 'Building' --progress 0.4
dist/antille publish --producer my.tool --id build --title 'Ready' --action open --action-title Open
dist/antille actions --producer my.tool
dist/antille ack --producer my.tool --id ACTION_EVENT_ID --result Done
dist/antille clear --producer my.tool --id build
```

`antille --help` lists the CLI. `antille asset FILE` imports a permitted image. `publish --file ACTIVITY.json` accepts a complete `IslandActivity` document; `list` provides the serialized shape.

External producers send data. Blocks include text, symbols, images, sprites, progress, timers, buttons, toggles, text inputs, native single/multiple choices, rows, columns, lists, and spacers. Actions carry form `fields` and optional screen `position`. Choice fields encode JSON string arrays. Focus/blur action IDs let a producer subscribe only to selected content. Form reset IDs clear unchanged submitted input while preserving newer drafts. Consumer-supplied `celebrationID` values trigger a generic success effect. Native view providers support other controls.

## Local protocol

The version 1 transport is newline-delimited JSON over `~/Library/Application Support/Antille/host.sock`. Dates use ISO 8601. `IslandWire` supplies matching Swift codecs. Requests have `version`, `operation`, and operation-specific fields; responses have `ok` and optional `message`, `activities`, or `actions`.

Operations: `ping`, `pair`, `hello`, `snapshot`, `upsert`, `remove`, `stale`, `actions`, `actions.wait`, `ack`, `drop-session`, `landing`, `magnet`, and `pulse`. Writes require approval and a scoped token. `hello` registers the generation; revisions reject older updates. `actions.wait` delivers immediately, supports excluded IDs, and times out after 1.4 seconds. Action IDs repeat until acknowledged; producers must deduplicate execution. Supply a monotonic revision on removes and detach acknowledgments to prevent late updates from resurrecting a moved activity or a late removal from deleting a newer docking. `landing` returns a reserved position/drop bounds. An acknowledged detach closes its preview and removes the hosted head.

The socket is private to the current user, checks the peer UID, limits payloads/connections, and bounds request time and producer update rate. Assets must be in permitted local directories with bounded file size. The host does not execute producer shell commands. Sources become visibly stale after missed heartbeats; stale never means finished. This is an unsandboxed local developer build; sandboxed-client transport has not been established.


## Conversation and motion options

These additive `IslandActivity` fields are optional; absent fields preserve earlier producers’ behavior.

- `showsInCompact: false`: keep an activity in the expanded roster without reserving a compact head/overflow slot. Omission preserves the earlier compact behavior. Producers own the domain rule, such as Pikminions' active-project membership.
- `compactLabel`: optional compact text instead of an icon (maximum 256 UTF-8 bytes). Priority still determines admission; admitted text renders on the trailing wing with measured, screen-bounded slot widths. Omit it for ordinary 28-point sprites. Landing geometry uses the same slot widths and keeps the physical camera clear. Antille's built-in sticky note uses its first line, up to 24 characters; the full local note remains editable in its expanded card.

- `requiresClickToExpand: true`: hover only grows the compact surface slightly. An explicit click opens content; outside click or Escape dismisses it. Drag extraction/drop does not trigger expansion.
- `actionsInMenu: true`: show secondary named actions in the header ellipsis menu instead of a bottom button row. The menu receives current form fields.
- `preferredExpandedHeight: 520`: allow a content-driven surface up to this height (160–640 points, limited by the screen). Short content remains short. Useful for actual question forms in a shared host.
- `spriteStartedAt`: fractional **Unix seconds**, encoded as a JSON number. `spriteRepeats: false` plays the pack once and holds the final frame. Supply a neutral final pose. Omitting these retains the loop.

For a Markdown text block, set `markdown: true`, give it a stable `textIdentity` for the source message, and optionally set `lineLimit` to bound its preview viewport in approximate text rows. Append chunks under that same identity; a new message uses a new identity. Existing rendered characters remain steady while the new suffix fades over 160 ms; Reduce Motion uses immediate updates. Long previews follow the end and offer Follow output after scrolling back. `IslandMarkdown.tail` bounds a Unicode tail and preserves an open code fence. Plain text blocks remain plain by default. Supported Markdown includes headings, inline emphasis/code/links, lists, quotes, rules, fenced code and simple pipe tables. Remote images are not fetched and HTML is not executed.

The engine registers Down only while the pointer is over a rendered extractable activity region. It invokes the existing `detach` action with normal source ownership; menus and drag/drop release the key. Transient native registration contention retries at most four times per second while the same head remains eligible, then stops on success or leave. Hit regions follow measured local bounds and the current panel frame. `IslandHoverArrowShortcut` also supports Up for desktop consumers. It uses public Carbon hotkeys with zero modifiers, not a keyboard event tap or typed-key history.
