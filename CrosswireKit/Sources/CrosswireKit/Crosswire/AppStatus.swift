//
//  AppStatus.swift
//  CrosswireKit
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

import Foundation

/// What a library entry is doing, or what is wrong with it.
///
/// This replaces the single word "Unavailable", which was shown for every
/// failure the library could not otherwise describe: a disconnected drive, a
/// folder the user moved, an installer that produced nothing. Three different
/// problems, three different fixes, one word that named none of them.
///
/// A healthy app has no status at all. `ready` carries no label, and the row
/// shows when the app was last opened instead. A label appears only when
/// something needs saying, which is what keeps the library quiet.
///
/// The type is deliberately pure: no strings, no colours, no `Bottle`. Labels
/// and sentences live in the app target, where the string catalogue is, and
/// the derivation below can be exercised without building any of it.
public enum AppStatus: Equatable, Sendable {

    /// Installed, opened before, nothing to report. Carries no label.
    case ready
    /// Installed but never opened.
    case notOpenedYet
    /// A window is open. Opening again brings that window forward rather than
    /// starting a second copy.
    case running
    /// Being got ready, before its installer runs.
    case preparing
    /// Its installer is running.
    case installing
    /// It was added to the library, but its installer could not be opened.
    case didNotInstall
    /// Several programs, none set as the one to open.
    case chooseProgram
    /// The installer finished and left nothing that can be opened.
    case nothingInstalled
    /// Stored on a volume that is not mounted. Carries the volume's name so
    /// the app can say which drive to connect.
    case driveNotConnected(volumeName: String?)
    /// Its folder was moved or deleted outside Crosswire, on a volume that is
    /// present. Distinct from `driveNotConnected` because the fix differs:
    /// locate the folder rather than plug something in.
    case filesNotFound
    /// Windows support is updating, so nothing can open until it finishes.
    case waitingForUpdate
    /// The last run ended without quitting normally.
    case quitUnexpectedly

    /// How strongly the label should read. The app maps these onto colours;
    /// the model does not know what a colour is.
    public enum Emphasis: Equatable, Sendable {
        /// Informational, same weight as the rest of the metadata line.
        case neutral
        /// Something is happening right now.
        case inProgress
        /// Needs the user to do something.
        case attention
        /// Something went wrong.
        case failure
    }

    public var emphasis: Emphasis {
        switch self {
        case .ready, .notOpenedYet, .waitingForUpdate:
            return .neutral
        case .running:
            return .inProgress
        case .preparing, .installing:
            return .inProgress
        case .chooseProgram, .nothingInstalled, .didNotInstall,
             .driveNotConnected, .filesNotFound:
            return .attention
        case .quitUnexpectedly:
            return .failure
        }
    }

    /// Whether the entry should carry a status dot. `ready` and
    /// `notOpenedYet` are the quiet states: they say what is normal, so they
    /// get no marker.
    public var showsIndicator: Bool {
        switch self {
        case .ready, .notOpenedYet: return false
        default: return true
        }
    }

    /// Whether the entry can be opened right now. Everything that is mid-flight
    /// or broken says no, so one check covers the Open button, the double-click
    /// and the Return key.
    public var canOpen: Bool {
        switch self {
        case .ready, .notOpenedYet, .running, .quitUnexpectedly:
            return true
        case .preparing, .installing, .didNotInstall, .chooseProgram,
             .nothingInstalled, .driveNotConnected, .filesNotFound, .waitingForUpdate:
            return false
        }
    }
}

extension AppStatus {

    /// Everything the status depends on, gathered in one place.
    ///
    /// A struct rather than a long argument list because the precedence rules
    /// below are the interesting part and they are much easier to test when
    /// the inputs can be built one field at a time.
    public struct Inputs: Equatable, Sendable {
        /// The entry is being created and its installer has not started.
        public var isPreparing: Bool
        /// Its installer is running now.
        public var isInstalling: Bool
        /// Its installer could not be opened at all.
        public var installerFailedToStart: Bool
        /// The entry's folder is reachable on disk.
        public var isAvailable: Bool
        /// The volume the entry lives on is not mounted.
        public var volumeIsMissing: Bool
        /// The name of that volume, when it is known.
        public var volumeName: String?
        /// How many programs the user would be offered.
        public var visibleProgramCount: Int
        /// Any program at all was found, including ones hidden from the user.
        public var hasAnyProgram: Bool
        /// One program is set as the one Open uses.
        public var hasPrimaryProgram: Bool
        /// A process from this entry is alive.
        public var isRunning: Bool
        /// Windows support is being replaced right now.
        public var isWindowsSupportUpdating: Bool
        /// It has been opened at least once.
        public var hasEverOpened: Bool
        /// The last run ended abnormally.
        public var lastRunCrashed: Bool

        public init(
            isPreparing: Bool = false,
            isInstalling: Bool = false,
            installerFailedToStart: Bool = false,
            isAvailable: Bool = true,
            volumeIsMissing: Bool = false,
            volumeName: String? = nil,
            visibleProgramCount: Int = 1,
            hasAnyProgram: Bool = true,
            hasPrimaryProgram: Bool = true,
            isRunning: Bool = false,
            isWindowsSupportUpdating: Bool = false,
            hasEverOpened: Bool = true,
            lastRunCrashed: Bool = false
        ) {
            self.isPreparing = isPreparing
            self.isInstalling = isInstalling
            self.installerFailedToStart = installerFailedToStart
            self.isAvailable = isAvailable
            self.volumeIsMissing = volumeIsMissing
            self.volumeName = volumeName
            self.visibleProgramCount = visibleProgramCount
            self.hasAnyProgram = hasAnyProgram
            self.hasPrimaryProgram = hasPrimaryProgram
            self.isRunning = isRunning
            self.isWindowsSupportUpdating = isWindowsSupportUpdating
            self.hasEverOpened = hasEverOpened
            self.lastRunCrashed = lastRunCrashed
        }
    }

    /// The one status to show, given everything that might be true at once.
    ///
    /// Order is the whole design here. Several conditions are routinely true
    /// together (an entry mid-install has no programs yet and has never been
    /// opened), and showing the wrong one of them sends the user after the
    /// wrong fix. The rules, most urgent first:
    ///
    /// 1. An update to Windows support stops everything, so it outranks the
    ///    rest: acting on any other status would fail until it finishes.
    /// 2. Then whatever the entry is doing right now, because that is both
    ///    temporary and self-explanatory.
    /// 3. Then reasons it cannot be opened, in fix order: a missing drive
    ///    before missing files, because a disconnected volume also makes the
    ///    files look gone and only one of the two fixes is right.
    /// 4. Then states that need a choice.
    /// 5. Then the quiet states.
    public static func resolve(_ inputs: Inputs) -> AppStatus {
        inProgressStatus(inputs) ?? blockingStatus(inputs) ?? quietStatus(inputs)
    }

    /// Whatever the entry is doing right now. Temporary and self-explanatory,
    /// so it outranks everything else: an update to Windows support stops all
    /// of it, and acting on any other status would fail until it finishes.
    private static func inProgressStatus(_ inputs: Inputs) -> AppStatus? {
        if inputs.isWindowsSupportUpdating { return .waitingForUpdate }
        if inputs.isPreparing { return .preparing }
        if inputs.isInstalling { return .installing }
        if inputs.installerFailedToStart { return .didNotInstall }
        // A running app is reachable by definition, so this sits above the
        // unavailable checks: a stale availability flag must never hide a
        // window the user can see.
        if inputs.isRunning { return .running }
        return nil
    }

    /// Reasons it cannot be opened, in fix order. A missing drive comes before
    /// missing files because a disconnected volume also makes the files look
    /// gone, and only one of the two fixes is right.
    private static func blockingStatus(_ inputs: Inputs) -> AppStatus? {
        if inputs.volumeIsMissing { return .driveNotConnected(volumeName: inputs.volumeName) }
        if !inputs.isAvailable { return .filesNotFound }
        if !inputs.hasAnyProgram { return .nothingInstalled }
        // Only ask when there is a real choice to make. One program, or a
        // primary already set, is not a question.
        if inputs.visibleProgramCount > 1 && !inputs.hasPrimaryProgram { return .chooseProgram }
        return nil
    }

    /// Nothing is wrong. At most this reports how the last run ended.
    private static func quietStatus(_ inputs: Inputs) -> AppStatus {
        if inputs.lastRunCrashed { return .quitUnexpectedly }
        if !inputs.hasEverOpened { return .notOpenedYet }
        return .ready
    }
}
