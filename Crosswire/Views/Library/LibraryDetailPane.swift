//
//  LibraryDetailPane.swift
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

/// The inspector: whatever is selected, always on screen, never covering the
/// library.
///
/// It is icon-led rather than banner-led. The banner was decorative art
/// stretched across the top of a pane that is only 300 pt wide, which left no
/// room for the things a person actually comes here for: what this app is,
/// whether it can be opened, and the four facts about it.
///
/// `bottle` has to be optional since there might be no selection, but an
/// `@ObservedObject` cannot be declared optional and still reliably notice a
/// `@Published` change, so the moment a bottle exists it is handed to a view
/// that observes it directly.
struct LibraryDetailPane: View {
    let bottle: Bottle?
    let actions: BottleActions
    @ObservedObject var sizes: LibrarySizeCache
    @Binding var renameRequestID: Bottle.ID?

    var body: some View {
        Group {
            if let bottle {
                LibraryInspector(bottle: bottle,
                                 actions: actions,
                                 sizes: sizes,
                                 renameRequestID: $renameRequestID)
            } else {
                placeholder
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(CrosswireLauncherTheme.backgroundRaised)
    }

    private var placeholder: some View {
        VStack(spacing: 8) {
            Image(systemName: "square.grid.2x2")
                .font(.system(size: 26, weight: .light))
                .foregroundStyle(CrosswireLauncherTheme.textTertiary)
            Text("Select an app from your library")
                .font(.system(size: 13))
                .foregroundStyle(CrosswireLauncherTheme.textSecondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

/// One app's inspector.
private struct LibraryInspector: View {
    @ObservedObject var bottle: Bottle
    let actions: BottleActions
    @ObservedObject var sizes: LibrarySizeCache
    @Binding var renameRequestID: Bottle.ID?

    @State private var isRenaming = false
    @State private var optionsExpanded = false
    @State private var programsExpanded = false
    @State private var troubleshootingExpanded = false

    private var status: AppStatus { bottle.appStatus() }
    private var bound: BoundBottleActions { actions.bound(to: bottle) }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                header
                primaryAction
                if let sentence = status.sentence(appName: bottle.displayName) {
                    StatusNotice(status: status, sentence: sentence)
                }
                facts
                disclosures
            }
            .padding(16)
        }
        .safeAreaInset(edge: .bottom) { footer }
        .id(bottle.id)
        .onAppear {
            if bottle.isAvailable, bottle.programs.isEmpty {
                bottle.updateInstalledPrograms()
            }
        }
        .onChange(of: renameRequestID) { _, id in
            guard id == bottle.id else { return }
            isRenaming = true
            renameRequestID = nil
        }
    }

    // MARK: - Header

    private var header: some View {
        HStack(alignment: .center, spacing: 12) {
            AppIcon(bottle: bottle, side: 56)
            VStack(alignment: .leading, spacing: 2) {
                if isRenaming {
                    BottleRenameField(bottle: bottle,
                                      isEditing: $isRenaming,
                                      font: .system(size: 15, weight: .semibold),
                                      maxWidth: 200)
                } else {
                    Text(bottle.displayName)
                        .font(.system(size: 16, weight: .bold))
                        .lineLimit(2)
                        .foregroundStyle(CrosswireLauncherTheme.textPrimary)
                }
                if let publisher = bottle.publisher {
                    Text(publisher)
                        .font(.system(size: 12))
                        .foregroundStyle(CrosswireLauncherTheme.textSecondary)
                        .lineLimit(1)
                }
            }
            Spacer(minLength: 0)
        }
    }

    // MARK: - Primary action

    /// One button, full width. It becomes a split button only when there is a
    /// real choice: several programs the user might mean. With one program the
    /// arrow would open a menu of one.
    @ViewBuilder
    private var primaryAction: some View {
        let programs = bottle.userVisiblePrograms
        HStack(spacing: 0) {
            Button {
                bound.run()
            } label: {
                Text(status.actions.first?.title ?? String(localized: "action.open"))
                    .font(.system(size: 13, weight: .semibold))
                    .frame(maxWidth: .infinity)
                    .frame(height: 32)
            }
            .buttonStyle(.plain)
            .disabled(!status.canOpen || !bottle.canLaunch)

            if programs.count > 1 {
                Rectangle()
                    .fill(Color.white.opacity(0.32))
                    .frame(width: 1, height: 18)
                Menu {
                    ForEach(programs, id: \.url) { program in
                        Button(program.displayName) { bound.runProgram(program) }
                    }
                } label: {
                    Image(systemName: "chevron.down").font(.system(size: 10, weight: .semibold))
                }
                .menuStyle(.borderlessButton)
                .menuIndicator(.hidden)
                .frame(width: 34, height: 32)
                .disabled(!status.canOpen)
            }
        }
        .foregroundStyle(CrosswireTheme.textOnAccent)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(status.canOpen && bottle.canLaunch
                      ? CrosswireTheme.accent
                      : CrosswireTheme.accent.opacity(CrosswireTheme.disabledOpacity))
        )
    }

    // MARK: - Facts

    /// The four facts, in the order the questions get asked: when did I last
    /// use this, how much room is it taking, where did it come from, how long
    /// have I had it.
    private var facts: some View {
        VStack(spacing: 0) {
            factRow(String(localized: "inspector.fact.lastOpened"), bottle.lastOpenedFact, first: true)
            factRow(String(localized: "inspector.fact.size"), sizeFact, first: false)
            factRow(String(localized: "inspector.fact.installedFrom"), bottle.settings.name, first: false)
            factRow(String(localized: "inspector.fact.added"), bottle.addedFact, first: false)
        }
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(CrosswireLauncherTheme.surface)
        )
    }

    private var sizeFact: String {
        if let bytes = sizes.size(of: bottle) {
            return ByteCountFormatter.string(fromByteCount: bytes, countStyle: .file)
        }
        // A dash while it is still being walked, rather than a zero that
        // reads as a fact.
        return sizes.isMeasured(bottle) ? "-" : String(localized: "inspector.fact.measuring")
    }

    private func factRow(_ key: String, _ value: String, first: Bool) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 12) {
            Text(key)
                .foregroundStyle(CrosswireLauncherTheme.textSecondary)
            Spacer(minLength: 8)
            Text(value)
                .multilineTextAlignment(.trailing)
                .lineLimit(1)
                .truncationMode(.middle)
                .foregroundStyle(CrosswireLauncherTheme.textPrimary)
        }
        .font(.system(size: 12))
        .padding(.horizontal, 10)
        .padding(.vertical, 7)
        .overlay(alignment: .top) {
            if !first {
                Rectangle().fill(CrosswireLauncherTheme.stroke).frame(height: 0.5)
            }
        }
    }

    // MARK: - Disclosures

    private var disclosures: some View {
        VStack(alignment: .leading, spacing: 0) {
            InspectorDisclosure(title: String(localized: "inspector.section.options"),
                                isExpanded: $optionsExpanded) {
                EntryDetailAdvancedSection(bottle: bottle,
                                           onRunProgram: bound.runProgram,
                                           onLaunchDiagnostics: bound.launchDiagnostics)
            }
            InspectorDisclosure(title: String(localized: "inspector.section.programs"),
                                badge: "\(bottle.userVisiblePrograms.count)",
                                isExpanded: $programsExpanded) {
                ProgramPickerList(programs: bottle.userVisiblePrograms, onPick: bound.runProgram)
            }
            InspectorDisclosure(title: String(localized: "inspector.section.troubleshooting"),
                                isExpanded: $troubleshootingExpanded) {
                troubleshooting
            }
        }
    }

    private var troubleshooting: some View {
        VStack(alignment: .leading, spacing: 8) {
            Button(String(localized: "action.openWithDiagnostics")) { bound.launchDiagnostics() }
            Button(String(localized: "button.rescanPrograms")) { bottle.updateInstalledPrograms() }
        }
        .font(.system(size: 12))
        .buttonStyle(.link)
    }

    // MARK: - Footer

    private var footer: some View {
        // Side by side when they fit at full length. Otherwise stacked, so the
        // label is never cut to "Remove from Libra…".
        ViewThatFits(in: .horizontal) {
            HStack(spacing: 8) {
                showInFinderButton
                Spacer(minLength: 0)
                removeButton
            }
            VStack(spacing: 8) {
                showInFinderButton.frame(maxWidth: .infinity)
                removeButton.frame(maxWidth: .infinity)
            }
        }
        .font(.system(size: 12))
        .buttonStyle(.bordered)
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(.bar)
    }
}

extension LibraryInspector {
    fileprivate var showInFinderButton: some View {
        Button(String(localized: "button.showInFinder")) { bottle.revealInFinder() }
            .lineLimit(1)
            .fixedSize(horizontal: true, vertical: false)
    }

    fileprivate var removeButton: some View {
        Button(String(localized: "action.removeFromLibrary")) { bound.uninstall() }
            .foregroundStyle(CrosswireTheme.danger)
            .lineLimit(1)
            .fixedSize(horizontal: true, vertical: false)
    }
}

/// The coloured block that carries a status and what to do about it.
private struct StatusNotice: View {
    let status: AppStatus
    let sentence: String

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 7) {
                Circle().fill(status.tint).frame(width: 8, height: 8)
                Text(status.label ?? "")
                    .font(.system(size: 13, weight: .semibold))
            }
            Text(sentence)
                .font(.system(size: 12))
                .foregroundStyle(CrosswireLauncherTheme.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 12)
        .padding(.vertical, 11)
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(status.tint.opacity(0.13))
        )
    }
}

/// A disclosure row that looks like the rest of the inspector rather than like
/// a `DisclosureGroup`, which draws its own chrome and indents its contents.
private struct InspectorDisclosure<Content: View>: View {
    let title: String
    var badge: String?
    @Binding var isExpanded: Bool
    @ViewBuilder let content: () -> Content

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Button {
                withAnimation(CrosswireTheme.Motion.hover) { isExpanded.toggle() }
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: isExpanded ? "chevron.down" : "chevron.right")
                        .font(.system(size: 9, weight: .semibold))
                        .foregroundStyle(CrosswireLauncherTheme.textSecondary)
                        .frame(width: 10)
                    Text(title)
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(CrosswireLauncherTheme.textPrimary)
                    if let badge {
                        Text(badge)
                            .font(.system(size: 13))
                            .foregroundStyle(CrosswireLauncherTheme.textSecondary)
                    }
                    Spacer(minLength: 0)
                }
                .contentShape(Rectangle())
                .padding(.vertical, 9)
            }
            .buttonStyle(.plain)
            if isExpanded { content() }
        }
        .overlay(alignment: .top) {
            Rectangle().fill(CrosswireLauncherTheme.stroke).frame(height: 0.5)
        }
    }
}
