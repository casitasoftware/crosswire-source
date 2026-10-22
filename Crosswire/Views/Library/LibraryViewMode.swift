//
//  LibraryViewMode.swift
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

/// Stored raw values preserve existing library preferences.
enum LibraryViewMode: String, CaseIterable {
    case grid
    case sidebar
    static let defaultsKey = "libraryViewMode"
    static let fallback: LibraryViewMode = .sidebar

    var icon: String { self == .grid ? "square.grid.2x2" : "sidebar.left" }
    var accessibilityLabel: String { self == .grid ? "Grid View" : "Sidebar View" }
}

struct LibraryViewModeSwitcher: View {
    @AppStorage(LibraryViewMode.defaultsKey) private var raw = LibraryViewMode.fallback.rawValue

    var body: some View {
        Picker("Library View", selection: $raw) {
            ForEach(LibraryViewMode.allCases, id: \.self) { option in
                Label(option.accessibilityLabel, systemImage: option.icon).tag(option.rawValue)
            }
        }
        .pickerStyle(.segmented)
        .labelStyle(.iconOnly)
    }
}

struct LibraryViewCommands: Commands {
    @AppStorage(LibraryViewMode.defaultsKey) private var raw = LibraryViewMode.fallback.rawValue

    var body: some Commands {
        CommandGroup(before: .toolbar) {
            Toggle("as Grid", isOn: selected(.grid)).keyboardShortcut("1", modifiers: .command)
            Toggle("as Sidebar", isOn: selected(.sidebar)).keyboardShortcut("2", modifiers: .command)
        }
    }

    private func selected(_ mode: LibraryViewMode) -> Binding<Bool> {
        Binding(get: { raw == mode.rawValue }, set: { if $0 { raw = mode.rawValue } })
    }
}
