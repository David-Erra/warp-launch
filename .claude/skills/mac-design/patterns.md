# SwiftUI patterns for macOS

> **Warp Launch:** copied from BAMA (daveebbelaar/bama, commit 639893c, MIT, see LICENSE-BAMA) and modified.
> Removed: global shortcut, quick-capture panel, search with saved recent searches,
> drag to Finder (writes files), CLI wake-up through a shared SQLite, Services menu (it launches the app),
> notifications and the Dock badge, floating capture panel. Where this file and `docs/disseny.md` disagree, `docs/disseny.md` wins. Never launch the app,
> take snapshots or run a self-test to check a rule: visual checks are done by David, or with his explicit OK.

Code written for BAMA's `new-mac-app` template (Swift 6.2, main-actor default isolation, SwiftData `Item`).
Warp Launch has no template and no SwiftData: the model is a Codable struct in WarpLaunchCore, and UI types
are marked `@MainActor` explicitly. Adapt the snippets; do not copy template helpers that do not exist here.

Imports used across these snippets:

```swift
import AppKit
import SwiftUI
import UniformTypeIdentifiers
```

## Commands that reach the focused window

Menu commands act on whatever the focused window has selected. Add `.commands { ItemCommands() }` to the scene and `.focusedSceneValue(\.selectedItem, ...)` in the view.

```swift
struct SelectedItemKey: FocusedValueKey { typealias Value = Item }

extension FocusedValues {
    var selectedItem: Item? {
        get { self[SelectedItemKey.self] }
        set { self[SelectedItemKey.self] = newValue }
    }
}

struct ItemCommands: Commands {
    @FocusedValue(\.selectedItem) private var item

    var body: some Commands {
        CommandMenu("Item") {
            Button(item?.isStarred == true ? "Unstar" : "Star", systemImage: "star") {
                item?.isStarred.toggle()
            }
            .keyboardShortcut("s", modifiers: [.command, .shift])
            .disabled(item == nil)
        }
    }
}
```

## Toolbar that follows the columns

A window with a sidebar, a list, and an inspector has three toolbar areas,
one over each column. Each button sits over the column it acts on:

```text
[traffic lights] [sidebar]  | Title           [+] [Search...] | [inspector]
     over the sidebar       |       over the list             | over the inspector
```

- The sidebar button comes with `NavigationSplitView` at the sidebar's
  trailing edge.
- Put `.inspector` on the `NavigationSplitView`, not inside the detail
  view. The inspector is then a full-height column with its own toolbar
  area. Inside the detail view it shares the detail's toolbar, and items
  slide over the inspector.
- The inspector button goes in the inspector's own `.toolbar`, after a
  flexible spacer. SwiftUI keeps it at the window's trailing edge while the
  inspector is hidden. Do not add a second button to the detail toolbar:
  it then shows twice.
- `.searchable(placement: .toolbar)` always moves to the window's trailing
  edge, over the inspector. To keep search over the list, put a native
  `NSSearchField` in a detail `ToolbarItem` (fixed width about 220 pt).
- Add `InspectorCommands()` to the scene's `.commands`: View > Show
  Inspector, Control-Command-I. No second inspector command elsewhere.

```swift
NavigationSplitView {
    Sidebar()
} detail: {
    ListPage()
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button("New Item", systemImage: "plus") { model.add() }
            }
            ToolbarItem(placement: .primaryAction) {
                ToolbarSearchField(text: $model.searchText, prompt: "Search")   // NSViewRepresentable around NSSearchField
            }
        }
}
.inspector(isPresented: $model.showInspector) {
    InspectorView()
        .inspectorColumnWidth(min: 240, ideal: 280, max: 360)
        .toolbar {
            ToolbarSpacer(.flexible)
            ToolbarItem(placement: .primaryAction) {
                Button { model.showInspector.toggle() } label: {
                    Label(model.showInspector ? "Hide Inspector" : "Show Inspector",
                          systemImage: "sidebar.trailing")
                }
                .help("Show or hide the inspector (Control-Command-I)")
            }
        }
}
```

Check both states in a real window capture (inspector open and closed),
and once at the window's minimum width: nothing overlaps the column edge,
each button appears once, and search is still reachable (toolbars.md,
"Title and search").

## Search, inspector, keyboard, context menu, feedback

One list that shows search with a result count, an inspector, the Delete key, a context menu, and a symbol animation as feedback.

```swift
struct SearchableList: View {
    @Environment(\.modelContext) private var context
    @Query(sort: \Item.createdAt, order: .reverse) private var items: [Item]
    @State private var query = ""
    @State private var selection: Item.ID?
    @State private var showInspector = true

    private var results: [Item] {
        query.isEmpty ? items : items.filter {
            $0.title.localizedStandardContains(query) || $0.notes.localizedStandardContains(query)
        }
    }

    var body: some View {
        List(results, selection: $selection) { item in
            Label(item.title, systemImage: item.isStarred ? "star.fill" : "circle")
                .contentTransition(.symbolEffect(.replace))  // visible feedback when starring
                .tag(item.id)
                .contextMenu {
                    Button(item.isStarred ? "Unstar" : "Star", systemImage: "star") {
                        withAnimation { item.isStarred.toggle() }
                    }
                    Divider()
                    Button("Delete", systemImage: "trash", role: .destructive) { context.delete(item) }
                }
        }
        .searchable(text: $query, placement: .toolbar, prompt: "Search items")
        .navigationSubtitle(query.isEmpty ? "" : "\(results.count) results")
        .onDeleteCommand {  // the Delete key and Edit > Delete
            if let item = results.first(where: { $0.id == selection }) { context.delete(item) }
        }
        .focusedSceneValue(\.selectedItem, results.first { $0.id == selection })
        .inspector(isPresented: $showInspector) {
            Text("Details of the selection")
                .inspectorColumnWidth(min: 220, ideal: 280)
        }
        .toolbar {
            ToolbarItem {
                Button("Inspector", systemImage: "sidebar.trailing") { showInspector.toggle() }
                    .help("Show or hide details (Control-Command-I)")
                    // Same key as InspectorCommands(). Use one or the other, not both.
                    .keyboardShortcut("i", modifiers: [.command, .control])
            }
        }
    }
}
```

## Sortable table

Header click sorts and reverses, columns resize and remember their widths,
rows alternate, and long names truncate in the middle (rule 73).

```swift
struct ItemTable: View {
    @Query private var items: [Item]
    @State private var sortOrder = [KeyPathComparator(\Item.createdAt, order: .reverse)]
    @State private var selection = Set<Item.ID>()
    @SceneStorage("ItemTable.columns") private var columns = TableColumnCustomization<Item>()

    var body: some View {
        Table(items.sorted(using: sortOrder), selection: $selection,
              sortOrder: $sortOrder, columnCustomization: $columns) {
            TableColumn("Title", value: \.title) { item in
                Text(item.title).truncationMode(.middle)
            }
            .customizationID("title")
            TableColumn("Created", value: \.createdAt) { item in
                Text(item.createdAt, format: .dateTime.day().month().year())
            }
            .width(min: 90, ideal: 120)
            .customizationID("created")
        }
        .alternatingRowBackgrounds()
    }
}
```

## Restore the selection on relaunch

Windows restore their frame on their own. `@SceneStorage` brings back UI
state per window: the selection, the open tab, column widths. Store a
stable id, never the data itself (rule 75).

```swift
struct RestoringList: View {
    @Query private var items: [Item]
    @SceneStorage("selectedItem") private var selectedID = ""  // the item's uuid

    var body: some View {
        List(items, id: \.uuid.uuidString, selection: Binding(
            get: { selectedID.isEmpty ? nil : selectedID },
            set: { selectedID = $0 ?? "" })) { item in
            Text(item.title)
        }
    }
}
```

## Custom chrome that follows the window

A custom selection fill turns gray when the window is not in front, keeps
concentric corners with a minimum radius, and lets a rich background run
under the sidebar (rules 14, 62, 63).

```swift
struct CustomSidebarRow: View {
    @Environment(\.appearsActive) private var appearsActive
    let title: String
    let selected: Bool

    private var fill: AnyShapeStyle {
        guard selected else { return AnyShapeStyle(.clear) }
        return appearsActive ? AnyShapeStyle(.tint) : AnyShapeStyle(.quaternary)
    }

    var body: some View {
        Text(title)
            .padding(.horizontal, 8)
            .frame(maxWidth: .infinity, minHeight: 24, alignment: .leading)
            .background(fill, in: ConcentricRectangle(corners: .concentric(minimum: 8)))
    }
}

// On a hero image or tinted header that an inset sidebar covers:
HeroImage().backgroundExtensionEffect()
```

## Undo with SwiftData

Register the reverse of each action yourself, on the window's undo manager.
Do not set `mainContext.undoManager = UndoManager()`: a separate manager
never reaches Edit > Undo. SwiftData's automatic undo also failed to save
the reverted values in testing (the next fetch returned the old state).

```swift
@Environment(\.undoManager) private var undoManager

func complete(_ todo: Todo) {
    let uid = todo.uid                       // your own UUID, stable across saves
    todo.isDone = true
    try? context.save()
    undoManager?.registerUndo(withTarget: store) { store in
        store.find(uid)?.isDone = false     // look up again; the object may be new
        try? store.context.save()
    }
    undoManager?.setActionName("Complete")
}
```

When `groupsByEvent` is off, wrap registrations in `beginUndoGrouping()` and
`endUndoGrouping()`, or the undo manager throws an exception that crashes
later inside SwiftUI. Test undo with swift-testing on the editor model: do, undo, check the configuration.

## Menu bar extra

Add `MenuBarExtra` next to the main `Window` scene in `App.swift` for an always-available entry point. In Warp Launch the icon is always shown (no `isInserted:` setting) and there is no Dock menu: the app is LSUIElement. The icon is a template SF Symbol, so it follows the menu bar's light and dark look. Show a menu, as below. Use `.menuBarExtraStyle(.window)` only when the feature is too complex for a menu (a timer with controls, a small player). [HIG The menu bar]

```swift
struct MenuBarScenePreview: Scene {
    var body: some Scene {
        MenuBarExtra("Starter", systemImage: "checkmark.circle") {
            Button("Quick Add") {}
                .keyboardShortcut("a")
            Divider()
            Button("Quit") { NSApp.terminate(nil) }
                .keyboardShortcut("q")
        }
    }
}
```

## More patterns from real apps

Each one was built and checked in a shipped app.

### Highlight parts of a text field while typing

SwiftUI's `TextField` cannot color part of its text. For inline
highlights (dates, tags), wrap a one-line `NSTextView` in an
`NSViewRepresentable` and color ranges with temporary attributes, which
change the look without changing the text:

```swift
let range = NSRange(span.range, in: textView.string)
textView.layoutManager?.addTemporaryAttribute(.backgroundColor, value: NSColor.systemPurple.withAlphaComponent(0.16), forCharacterRange: range)
textView.layoutManager?.addTemporaryAttribute(.foregroundColor, value: NSColor.systemPurple, forCharacterRange: range)
```

Override `keyDown` for Return (keyCode 36) and Escape (53), and
`mouseDown` with `characterIndexForInsertion(at:)` to react to clicks on a
highlight. Draw a placeholder in `draw(_:)` when the string is empty.

### Menu bar extra that keeps the app alive

`MenuBarExtra("App", systemImage: "checklist", isInserted: $showMenuBar) { ... }`
(a menu; add `.menuBarExtraStyle(.window)` only for a feature too complex for one),
and return `false` from `applicationShouldTerminateAfterLastWindowClosed`
so closing the main window keeps the menu bar and global shortcuts working.

Hide the main window instead of closing it. On macOS 26, closing a SwiftUI
`Window` scene, opening it again, and then changing state crashed AppKit in
a constraint loop every time. Set a forwarding `NSWindowDelegate` whose
`windowShouldClose` calls `orderOut(nil)` and returns false. Warp Launch checks this by hand, with David's OK (test 1 in docs/disseny.md),
and records the result in docs/fets-verificats.md.

