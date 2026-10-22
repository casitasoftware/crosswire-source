//
//  BottleDetailContent.swift
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

import SwiftUI
import CrosswireKit

/// The bottle detail content shared by Sidebar's permanent pane
/// (`LibraryDetailPane`) and Grid's slide-over (`EntryDetailView`): name row,
/// Play button, secondary actions, and the Advanced disclosure. Both call
/// sites render `HeroArtView(bottle:)` themselves immediately before this
/// view, at their own appropriate width — see the width note in
/// `EntryDetailView.swift`.
///
/// `@ObservedObject`, not `let` — without it, `updateInstalledPrograms()`
/// completing asynchronously (the scan that makes `canLaunch` true for a
/// bottle nothing has scanned yet) never triggers a re-render, and Play
/// stays visibly disabled even after the scan succeeds. This is the same
/// mistake `GameTile` and `LibraryRow` avoid by declaring `bottle` as
/// `@ObservedObject` themselves.
struct BottleDetailContent: View {
    @ObservedObject var bottle: Bottle
    let actions: BoundBottleActions
    /// Sidebar-only: an external trigger (context menu on a different row)
    /// that should open this content already in rename mode. Grid has no
    /// such trigger and omits this parameter.
    var renameRequestID: Binding<Bottle.ID?>?

    @State private var isRenaming = false
    @State private var showRuntimesSheet = false

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            nameRow
            playRow
            if let sentence = bottle.appStatus().sentence(appName: bottle.displayName) {
                GroupBox(bottle.appStatus().label ?? "App Status") {
                    Text(sentence).frame(maxWidth: .infinity, alignment: .leading)
                }
            }
            secondaryActions
            EntryDetailAdvancedSection(bottle: bottle,
                                       onRunProgram: actions.runProgram,
                                       onLaunchDiagnostics: actions.launchDiagnostics)
        }
        .id(bottle.id)
        .onAppear {
            if bottle.isAvailable, bottle.programs.isEmpty {
                bottle.updateInstalledPrograms()
            }
        }
        .onChange(of: renameRequestID?.wrappedValue) { _, id in
            guard let renameRequestID, id == bottle.id else { return }
            isRenaming = true
            renameRequestID.wrappedValue = nil
        }
    }

    // MARK: - Name

    @ViewBuilder
    private var nameRow: some View {
        if isRenaming {
            HStack(spacing: 8) {
                BottleRenameField(bottle: bottle,
                                  isEditing: $isRenaming,
                                  font: .system(size: 18, weight: .semibold),
                                  maxWidth: 320)
            }
        }
    }

    // MARK: - Play

    private var playRow: some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: 12) { launchControls }
            VStack(alignment: .leading, spacing: 12) { launchControls }
        }
    }

    @ViewBuilder
    private var launchControls: some View {
        Button(action: actions.run) {
            Label("Play", systemImage: "play.fill")
                .font(.headline)
                .frame(minWidth: 140)
        }
        .buttonStyle(.borderedProminent)
        .controlSize(.large)
        .disabled(!bottle.canLaunch)
        .accessibilityLabel("Launch \(bottle.displayName)")
        if bottle.userVisiblePrograms.count > 1 {
            Menu("Other Programs") {
                ForEach(bottle.userVisiblePrograms) { program in
                    Button(program.displayName) { actions.runProgram(program) }
                }
            }
            .fixedSize()
            .accessibilityLabel("Choose another program to open")
        }
        Text(bottle.appStatus().label ?? bottle.librarySecondaryLine)
            .font(.callout)
            .foregroundStyle(.secondary)
    }

    // MARK: - Secondary actions

    private var secondaryActions: some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: 10) { actionButtons }
            VStack(alignment: .leading, spacing: 10) { actionButtons }
        }
        .sheet(isPresented: $showRuntimesSheet) {
            CommonRuntimesView(bottle: bottle)
        }
    }

    @ViewBuilder
    private var actionButtons: some View {
        secondaryButton("Rename…", systemImage: "pencil") { isRenaming = true }
        secondaryButton("Check Dependencies…", systemImage: "shippingbox") { showRuntimesSheet = true }
        secondaryButton("Show in Finder", systemImage: "folder") { bottle.revealInFinder() }
        secondaryButton("Uninstall…", systemImage: "trash", destructive: true) { actions.uninstall() }
    }

    @ViewBuilder
    private func secondaryButton(
        _ title: String, systemImage: String, destructive: Bool = false, action: @escaping () -> Void
    ) -> some View {
        Button(role: destructive ? .destructive : nil, action: action) {
            HStack(spacing: 6) {
                Image(systemName: systemImage)
                Text(title)
            }
            .font(.system(size: 12))
        }
        .buttonStyle(.bordered)
        .accessibilityLabel(title)
    }
}
