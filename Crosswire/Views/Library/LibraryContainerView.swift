//
//  LibraryContainerView.swift
//  Crosswire
//
//  This file is part of Crosswire.
//
//  Crosswire is free software: you can redistribute it and/or modify it under the terms
//  of the GNU General Public License as published by the Free Software Foundation,
//  either version 3 of the License, or (at your option) any later version.
//
//  Crosswire is distributed in the hope that it will be useful, but WITHOUT ANY WARRANTY;
//  without even the implied warranty of MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.
//  See the GNU General Public License for more details.
//
//  You should have received a copy of the GNU General Public License along with Crosswire.
//  If not, see https://www.gnu.org/licenses/.
//

import CrosswireKit
import SwiftUI

/// The library: a list or a grid on the left, the inspector always on the
/// right.
///
/// Grid mode used to be a different layout rather than a different way of
/// drawing the same thing. Selecting a tile slid a full-width detail view in
/// over the library, so looking at one app meant losing sight of the rest, and
/// the two modes disagreed about what selection even meant. Now the split is
/// fixed and only the left half changes, which is why selection survives
/// switching between them: both halves read the same `LibrarySelection`.
///
/// The inspector is a fixed 300 pt. It is a reference column, not content, so
/// it does not compete with the library for width when the window grows.
struct LibraryContainerView: View {
    let bottles: [Bottle]
    @Binding var searchText: String
    @ObservedObject var selection: LibrarySelection
    let actions: BottleActions
    /// Return, or a double-click. Selection alone never opens anything, so
    /// arrow keys can move through the library without launching apps.
    let onOpen: (Bottle) -> Void
    /// The toolbar's Install action, offered again inside a small library.
    let onAdd: () -> Void

    @AppStorage(LibraryViewMode.defaultsKey) private var modeRaw = LibraryViewMode.fallback.rawValue
    @StateObject private var sizes = LibrarySizeCache()
    @State private var renameRequestID: Bottle.ID?
    /// Bumped when a rescan changes an app's programs, so rows read the new
    /// status. Rows are built from plain values and would otherwise keep the
    /// status they had when the list last redrew.
    @State private var refreshTick = 0
    @State private var sortOrder = [KeyPathComparator(\LibraryRowItem.name)]

    private var mode: LibraryViewMode { LibraryViewMode(rawValue: modeRaw) ?? .fallback }

    /// Search narrows what is visible, never what is selected: the inspector
    /// keeps showing the selected app while the user types.
    private var filtered: [Bottle] {
        if searchText.isEmpty { return bottles }
        return bottles.filter { $0.displayName.localizedCaseInsensitiveContains(searchText) }
    }

    private var rows: [LibraryRowItem] {
        _ = refreshTick
        return filtered.map { bottle in
            LibraryRowItem(
                id: bottle.id,
                name: bottle.displayName,
                status: bottle.appStatus(),
                lastOpened: bottle.settings.lastLaunched,
                sizeInBytes: sizes.size(of: bottle)
            )
        }
        .sorted(using: sortOrder)
    }

    var body: some View {
        // Below this width the detail pane would squeeze the list, so it steps
        // aside and the list takes the window. Return and double-click still
        // open the selected app, and widening the window brings the pane back.
        ViewThatFits(in: .horizontal) {
            HStack(spacing: 0) {
                libraryHalf
                    .frame(minWidth: 400, maxWidth: .infinity, maxHeight: .infinity)
                Rectangle()
                    .fill(CrosswireLauncherTheme.stroke)
                    .frame(width: 1)
                LibraryDetailPane(bottle: bottles.first { $0.id == selection.selectedID },
                                  actions: actions,
                                  sizes: sizes,
                                  renameRequestID: $renameRequestID)
                    .frame(width: 300)
            }
            .frame(minWidth: 701, maxWidth: .infinity, maxHeight: .infinity)
            libraryHalf
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .task(id: bottles.map(\.id)) { sizes.measure(bottles) }
        .onReceive(NotificationCenter.default.publisher(for: Bottle.programsDidChange)) { note in
            // An install finished or a rescan found new programs: the number
            // measured before that is wrong, so measure again.
            guard let bottle = note.object as? Bottle else { return }
            refreshTick += 1
            sizes.invalidate(bottle)
            sizes.measure([bottle])
        }
    }

    // MARK: - The left half

    @ViewBuilder
    private var libraryHalf: some View {
        VStack(spacing: 0) {
            libraryHeader
            if filtered.isEmpty && !searchText.isEmpty {
                noMatch
            } else {
                switch mode {
                case .grid: gridBody
                case .sidebar: listBody
                }
            }
        }
    }

    /// The window's title and how many apps it holds. It lives above the list
    /// instead of in the toolbar, where a custom item could not be sized to
    /// sit beside the window buttons.
    private var libraryHeader: some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Text("library.title")
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(CrosswireLauncherTheme.textPrimary)
                .accessibilityAddTraits(.isHeader)
            Text("^[\(bottles.count) app](inflect: true)")
                .font(.system(size: 12))
                .foregroundStyle(CrosswireLauncherTheme.textSecondary)
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 16)
        .padding(.top, 12)
        .padding(.bottom, 8)
        .background(CrosswireLauncherTheme.backgroundBase)
    }

    /// Up to this many entries, the library still needs to tell the user how
    /// to add things to it. Past it, the library speaks for itself.
    private static let smallLibrary = 6
    /// The list is denser, so its hint earns its place for fewer rows.
    private static let smallList = 3

    private var listBody: some View {
        LibraryTable(
            items: rows,
            selection: Binding(
                get: { selection.selectedID },
                // A table can deselect by clicking empty space. The inspector
                // has nothing to show then, so keep the last selection rather
                // than blanking the right half on a stray click.
                set: { if let new = $0 { selection.selectedID = new } }
            ),
            sortOrder: $sortOrder,
            onOpen: { id in
                if let bottle = bottles.first(where: { $0.id == id }) { onOpen(bottle) }
            },
            icon: { id in
                if let bottle = bottles.first(where: { $0.id == id }) {
                    AppIcon(bottle: bottle, side: 18)
                } else {
                    Color.clear.frame(width: 18, height: 18)
                }
            }
        )
        .background(CrosswireLauncherTheme.backgroundBase)
        .safeAreaInset(edge: .bottom) {
            if filtered.count <= Self.smallList {
                dropHint
            }
        }
    }

    /// A dashed strip under a short list. The grid gets a tile; a table cannot
    /// carry one, so the same invitation goes below the rows.
    private var dropHint: some View {
        Button(action: onAdd) {
            HStack(spacing: 7) {
                Image(systemName: "plus")
                Text("library.addTile")
            }
            .font(.system(size: 12))
            .foregroundStyle(CrosswireLauncherTheme.textSecondary)
            .frame(maxWidth: .infinity)
            .frame(height: 44)
            .background(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .strokeBorder(CrosswireLauncherTheme.stroke,
                                  style: StrokeStyle(lineWidth: 1, dash: [7, 5]))
            )
        }
        .buttonStyle(.plain)
        .padding(.horizontal, 12)
        .padding(.bottom, 12)
    }

    private var gridBody: some View {
        LibraryGrid(bottles: filtered,
                    selectedID: selection.selectedID,
                    actions: actions,
                    // Clicking a tile selects it. It used to slide a detail
                    // view over the library; the inspector makes that
                    // unnecessary and it was the reason grid mode felt like a
                    // different app.
                    onSelect: { selection.select($0) },
                    onHighlight: { selection.select($0) },
                    onRequestRename: { bottle in
                        selection.select(bottle)
                        renameRequestID = bottle.id
                    },
                    // Only while the library is small. Once there are enough
                    // tiles to fill the pane, a permanent dashed square at the
                    // end is clutter, and the toolbar's Install is right there.
                    onAdd: filtered.count <= Self.smallLibrary ? onAdd : nil)
        .background(CrosswireLauncherTheme.backgroundBase)
    }

    private var noMatch: some View {
        VStack(spacing: 10) {
            Spacer()
            Image(systemName: "magnifyingglass")
                .font(.system(size: 28, weight: .light))
                .foregroundStyle(CrosswireLauncherTheme.textTertiary)
                .accessibilityHidden(true)
            Text("No matching apps.")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(CrosswireLauncherTheme.textPrimary)
            Text("Nothing in your library matches “\(searchText)”.")
                .font(.system(size: 12))
                .foregroundStyle(CrosswireLauncherTheme.textSecondary)
                .multilineTextAlignment(.center)
            Button("Clear Search") { searchText = "" }
                .controlSize(.regular)
                .padding(.top, 4)
            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(CrosswireLauncherTheme.backgroundBase)
    }
}
