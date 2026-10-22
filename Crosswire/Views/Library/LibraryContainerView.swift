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

/// A compact app list beside the selected app, or a full-width cover grid.
struct LibraryContainerView: View {
    let bottles: [Bottle]
    @Binding var searchText: String
    @ObservedObject var selection: LibrarySelection
    let actions: BottleActions
    let onOpen: (Bottle) -> Void
    let onShowDetails: (Bottle) -> Void
    let onAdd: () -> Void

    @State private var renameTarget: Bottle?
    @AppStorage(LibraryViewMode.defaultsKey) private var modeRaw = LibraryViewMode.fallback.rawValue

    private var mode: LibraryViewMode { LibraryViewMode(rawValue: modeRaw) ?? .fallback }
    private var filtered: [Bottle] {
        searchText.isEmpty ? bottles : bottles.filter {
            $0.displayName.localizedCaseInsensitiveContains(searchText)
        }
    }

    private var selectedID: Binding<Bottle.ID?> {
        Binding(get: { selection.selectedID }, set: { id in
            if let bottle = bottles.first(where: { $0.id == id }) { selection.select(bottle) }
        })
    }

    var body: some View {
        if mode == .sidebar {
            HSplitView {
                appList
                    .frame(minWidth: 180, idealWidth: 240, maxWidth: 300, maxHeight: .infinity)
                selectedApp
                    .frame(minWidth: 340, maxWidth: .infinity, maxHeight: .infinity)
            }
        } else {
            VStack(alignment: .leading, spacing: 0) {
                libraryHeader
                if filtered.isEmpty {
                    noMatch
                } else {
                    LibraryGrid(bottles: filtered, selectedID: selection.selectedID, actions: actions,
                                onSelect: { selection.select($0); onShowDetails($0) },
                                onOpen: onOpen,
                                onHighlight: { selection.select($0) },
                                onRequestRename: { selection.select($0); renameTarget = $0 },
                                onAdd: bottles.count < 6 ? onAdd : nil)
                }
            }
            .sheet(item: $renameTarget) { bottle in
                LibraryRenameSheet(bottle: bottle)
            }
        }
    }

    private var libraryHeader: some View {
        HStack(alignment: .firstTextBaseline) {
            Text("library.title").font(.headline).accessibilityAddTraits(.isHeader)
            Text("^[\(bottles.count) app](inflect: true)").foregroundStyle(.secondary)
        }
        .padding()
    }

    private var appList: some View {
        VStack(spacing: 0) {
            if filtered.isEmpty {
                noMatch
            } else {
                List(filtered, selection: selectedID) { bottle in
                    NativeLibraryRow(bottle: bottle, actions: actions.bound(to: bottle))
                        .tag(bottle.id)
                        .onTapGesture(count: 2) { onOpen(bottle) }
                }
                .listStyle(.sidebar)
                .onKeyPress(.return) {
                    guard let bottle = bottles.first(where: { $0.id == selection.selectedID }) else {
                        return .ignored
                    }
                    onOpen(bottle)
                    return .handled
                }
            }
            Divider()
            Button("Install App…", systemImage: "plus", action: onAdd)
                .buttonStyle(.borderless)
                .padding(12)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    @ViewBuilder
    private var selectedApp: some View {
        if let bottle = bottles.first(where: { $0.id == selection.selectedID }) {
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    HeroArtView(bottle: bottle)
                    BottleDetailContent(bottle: bottle, actions: actions.bound(to: bottle))
                }
                .padding(24)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .background(.background)
            .id(bottle.id)
        } else {
            ContentUnavailableView("Select an App", systemImage: "app.dashed")
        }
    }

    private var noMatch: some View {
        ContentUnavailableView {
            Label("No Matching Apps", systemImage: "magnifyingglass")
        } description: {
            Text("No apps match “\(searchText)”.")
        } actions: {
            Button("Clear Search") { searchText = "" }
        }
    }
}

private struct NativeLibraryRow: View {
    @ObservedObject var bottle: Bottle
    let actions: BoundBottleActions
    @State private var isRenaming = false

    var body: some View {
        HStack(spacing: 10) {
            AppIcon(bottle: bottle, side: 36).accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 3) {
                BottleRenameField(bottle: bottle, isEditing: $isRenaming,
                                  font: .headline)
                Text(bottle.appStatus().label ?? bottle.librarySecondaryLine)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
        }
        .padding(.vertical, 5)
        .contextMenu {
            Button("Open", action: actions.run).disabled(!bottle.canLaunch)
            Button("Rename…") { isRenaming = true }
            Button("Show in Finder") { bottle.revealInFinder() }
            Divider()
            Button("Uninstall…", role: .destructive, action: actions.uninstall)
        }
        .onAppear {
            if bottle.isAvailable && bottle.programs.isEmpty { bottle.updateInstalledPrograms() }
        }
    }
}

private struct LibraryRenameSheet: View {
    @ObservedObject var bottle: Bottle
    @Environment(\.dismiss) private var dismiss
    @State private var name = ""
    @FocusState private var focused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Rename App").font(.headline)
            TextField("App name", text: $name).focused($focused).onSubmit { save() }
            HStack {
                Spacer()
                Button("Cancel") { dismiss() }.keyboardShortcut(.cancelAction)
                Button("Rename", action: save).keyboardShortcut(.defaultAction)
            }
        }
        .padding(20)
        .frame(width: 320)
        .onAppear { name = bottle.displayName; focused = true }
    }

    private func save() {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        bottle.settings.appDisplayName = trimmed.isEmpty ? nil : trimmed
        dismiss()
    }
}
