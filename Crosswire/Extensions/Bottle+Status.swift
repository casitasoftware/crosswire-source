//
//  Bottle+Status.swift
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
import Foundation

extension Bottle {

    /// What to show for this entry right now.
    ///
    /// `AppStatus.resolve` holds the precedence rules and knows nothing about
    /// bottles; this only gathers the inputs. Anything the app cannot observe
    /// yet is passed as false rather than guessed: an install in progress is
    /// known only to the view driving it, and a crashed last run needs run
    /// bookkeeping that does not exist. Both are parameters so the install
    /// flow can supply them without this having to reach into the view layer.
    /// - Parameter isRunning: whether a process from this entry is alive.
    ///   Passed in rather than looked up, because finding out runs `ps` and
    ///   this is called for every row on every redraw. Callers that already
    ///   know, such as the inspector, pass the real answer.
    func appStatus(
        isPreparing: Bool? = nil,
        isInstalling: Bool = false,
        installerFailedToStart: Bool = false,
        isRunning: Bool = false,
        isWindowsSupportUpdating: Bool = false,
        lastRunCrashed: Bool = false
    ) -> AppStatus {
        // Only ask the file system about volumes when something is actually
        // wrong. For a healthy entry, which is nearly all of them nearly all
        // of the time, this does no I/O at all.
        let volume = isAvailable ? (isMissing: false, name: nil) : Self.volumeState(for: url)
        return AppStatus.resolve(.init(
            isPreparing: isPreparing ?? inFlight,
            isInstalling: isInstalling,
            installerFailedToStart: installerFailedToStart,
            isAvailable: isAvailable,
            volumeIsMissing: volume.isMissing,
            volumeName: volume.name,
            visibleProgramCount: programs.isEmpty ? persistedVisibleProgramCount : userVisiblePrograms.count,
            hasAnyProgram: !programs.isEmpty || persistedVisibleProgramCount > 0,
            hasPrimaryProgram: settings.primaryProgramURL != nil,
            isRunning: isRunning,
            isWindowsSupportUpdating: isWindowsSupportUpdating,
            hasEverOpened: settings.lastLaunched != nil,
            lastRunCrashed: lastRunCrashed
        ))
    }

    /// Whether the volume an entry lives on is mounted, and what it is called.
    ///
    /// A disconnected drive and a deleted folder look identical from the
    /// entry's own path: both are simply not there. They are told apart by
    /// asking the system which volumes are mounted, because the fixes differ
    /// and offering the wrong one wastes the user's time.
    ///
    /// Anything on the boot volume is never reported missing, so an app in the
    /// default location can only ever be "files not found".
    static func volumeState(for url: URL) -> (isMissing: Bool, name: String?) {
        let mounted = FileManager.default.mountedVolumeURLs(
            includingResourceValuesForKeys: [.volumeNameKey], options: []
        ) ?? []

        // Longest match wins: "/" is a prefix of everything, so a nested
        // volume has to beat it.
        let path = url.standardizedFileURL.path(percentEncoded: false)
        let containing = mounted
            .filter { path.hasPrefix($0.standardizedFileURL.path(percentEncoded: false)) }
            .max { $0.path(percentEncoded: false).count < $1.path(percentEncoded: false).count }

        if let containing {
            let name = try? containing.resourceValues(forKeys: [.volumeNameKey]).volumeName
            return (false, name ?? nil)
        }

        // Not under any mounted volume. If it was on an external drive the
        // path still records which one, which is the name worth showing.
        let components = url.standardizedFileURL.pathComponents
        if components.count > 2, components[1] == "Volumes" {
            return (true, components[2])
        }
        return (true, nil)
    }
}

extension Bottle {

    /// Who made the Windows app, read from the executable's own version
    /// information. Nil when the exe does not carry one, which plenty of older
    /// games do not.
    ///
    /// Read on demand and not cached: the inspector asks for one selected app
    /// at a time, and a cached publisher would outlive a reinstall.
    var publisher: String? {
        guard let url = artCandidateURLs.first,
              let executable = try? PEFile(url: url) else { return nil }
        let strings = executable.versionStrings()
        for key in ["CompanyName", "LegalCopyright"] {
            if let value = strings[key]?.trimmingCharacters(in: .whitespacesAndNewlines),
               !value.isEmpty {
                return value
            }
        }
        return nil
    }

    /// "Today at 8:14 PM" or "19 Sep 2026 at 10:02 PM". The inspector has room
    /// for the time, unlike the list column, and the time is what tells you
    /// whether "today" was this morning or a minute ago.
    var lastOpenedFact: String {
        guard let last = settings.lastLaunched else {
            return String(localized: "inspector.fact.notOpenedYet")
        }
        return Self.factDateFormatter.string(from: last)
    }

    /// When the entry was added, taken from the folder's creation date. There
    /// is no recorded "added" timestamp in the metadata, and back-filling one
    /// would be a guess for every app already in the library.
    var addedFact: String {
        let created = try? url.resourceValues(forKeys: [.creationDateKey]).creationDate
        guard let created else { return "-" }
        return Self.factDateFormatter.string(from: created)
    }

    private static let factDateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        formatter.doesRelativeDateFormatting = true
        return formatter
    }()
}
