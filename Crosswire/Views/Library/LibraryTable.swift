//
//  LibraryTable.swift
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

/// One row of the library list, flattened for sorting.
///
/// A value type rather than the `Bottle` itself because two of the three
/// columns are not properties of a bottle: size comes from
/// `LibrarySizeCache`, and the status is derived. `Table` sorts by key path,
/// so the sort keys have to exist somewhere concrete.
struct LibraryRowItem: Identifiable, Equatable {
    let id: Bottle.ID
    let name: String
    let status: AppStatus
    let lastOpened: Date?
    let sizeInBytes: Int64?

    /// Never-opened entries sort as the oldest thing there is, which puts them
    /// last when the column is newest-first. That is the direction people
    /// actually use, so it is the one optimised for.
    var lastOpenedSortKey: Date { lastOpened ?? .distantPast }

    /// Unmeasured sorts below empty, so a library still being measured fills
    /// in from the bottom rather than shuffling rows already read.
    var sizeSortKey: Int64 { sizeInBytes ?? -1 }

    /// "Today", "Yesterday", "19 Sep" or, when it has never been opened, an
    /// em-free dash. A date rather than "3 days ago" because the column is
    /// narrow and a list is scanned, not read.
    @MainActor var lastOpenedText: String {
        guard let lastOpened else { return "-" }
        return Self.dateFormatter.localizedString(for: lastOpened, relativeTo: Date())
    }

    @MainActor var sizeText: String {
        guard let sizeInBytes else { return "-" }
        return Self.byteFormatter.string(fromByteCount: sizeInBytes)
    }

    @MainActor private static let dateFormatter: RelativeDateTimeFormatter = {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .abbreviated
        formatter.dateTimeStyle = .named
        return formatter
    }()

    @MainActor private static let byteFormatter: ByteCountFormatter = {
        let formatter = ByteCountFormatter()
        formatter.countStyle = .file
        formatter.allowsNonnumericFormatting = false
        return formatter
    }()
}

/// The library as a sortable table: Name, Last Opened, Size.
///
/// `Table` rather than a hand-built list so the column headers, click to sort,
/// sort indicator and column resizing are the system's and behave the way
/// every other Mac list does. The cost is that rows are less freely drawn than
/// the old stack was, which is why the status lives in the name cell rather
/// than a column of its own: a healthy app has no status, so a dedicated
/// column would be empty most of the time.
struct LibraryTable<Icon: View>: View {
    let items: [LibraryRowItem]
    @Binding var selection: Bottle.ID?
    @Binding var sortOrder: [KeyPathComparator<LibraryRowItem>]
    /// Return or a double-click. Selection alone never opens anything, so that
    /// arrow keys can move through the library without launching apps.
    let onOpen: (Bottle.ID) -> Void
    /// The row's icon. The library passes the same view the detail pane uses,
    /// so a row and its detail always show the same icon.
    @ViewBuilder let icon: (Bottle.ID) -> Icon

    var body: some View {
        Table(items, selection: $selection, sortOrder: $sortOrder) {
            TableColumn("library.column.name", value: \.name) { item in
                nameCell(item)
            }
            .width(min: 180, ideal: 280)

            TableColumn("library.column.lastOpened", value: \.lastOpenedSortKey) { item in
                Text(item.lastOpenedText)
                    .foregroundStyle(CrosswireTheme.textSecondary)
            }
            .width(min: 90, ideal: 120)

            TableColumn("library.column.size", value: \.sizeSortKey) { item in
                Text(item.sizeText)
                    .foregroundStyle(CrosswireTheme.textSecondary)
                    .monospacedDigit()
            }
            .width(min: 70, ideal: 90)
        }
        .tableStyle(.inset(alternatesRowBackgrounds: false))
        .contextMenu(forSelectionType: Bottle.ID.self) { _ in
            EmptyView()
        } primaryAction: { ids in
            if let id = ids.first { onOpen(id) }
        }
    }

    @ViewBuilder
    private func nameCell(_ item: LibraryRowItem) -> some View {
        HStack(spacing: 8) {
            icon(item.id)
            Text(item.name)
                .lineLimit(1)
                .truncationMode(.tail)
            if let label = item.status.label {
                HStack(spacing: 4) {
                    if item.status.showsIndicator {
                        Circle().fill(item.status.tint).frame(width: 6, height: 6)
                    }
                    Text(label)
                        .font(.system(size: 11))
                        .foregroundStyle(item.status.tint)
                        .lineLimit(1)
                }
            }
        }
    }
}
