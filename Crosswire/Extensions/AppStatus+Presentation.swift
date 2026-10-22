//
//  AppStatus+Presentation.swift
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
import SwiftUI

/// What each status says, and what the user can do about it.
///
/// Three pieces per state, and every state has all three: a label short enough
/// for a grid caption, one sentence in the inspector that says what happened,
/// and at least one action. A status with nothing to do about it is just a
/// complaint, so the only state with no action is the one where waiting is the
/// answer.
///
/// Labels have a hard width budget: 118 pt at 11 pt, set by the caption under
/// a 124 pt grid tile. That is roughly 22 characters of average German, but it
/// is a width and not a character count, so it has to be checked in a build
/// with SF Pro rather than counted. Each key's comment carries the budget.
extension AppStatus {

    /// The short label in a list row or under a grid tile. `nil` for `ready`,
    /// which is the whole point of the vocabulary: a healthy app shows when it
    /// was last opened, not a status.
    var label: String? {
        switch self {
        case .ready:
            return nil
        case .notOpenedYet:
            return String(localized: "status.notOpenedYet")
        case .running:
            return String(localized: "status.running")
        case .preparing:
            return String(localized: "status.preparing")
        case .installing:
            return String(localized: "status.installing")
        case .didNotInstall:
            return String(localized: "status.didNotInstall")
        case .chooseProgram:
            return String(localized: "status.chooseProgram")
        case .nothingInstalled:
            return String(localized: "status.nothingInstalled")
        case .driveNotConnected:
            return String(localized: "status.driveNotConnected")
        case .filesNotFound:
            return String(localized: "status.filesNotFound")
        case .waitingForUpdate:
            return String(localized: "status.waitingForUpdate")
        case .quitUnexpectedly:
            return String(localized: "status.quitUnexpectedly")
        }
    }

    /// The sentence in the inspector. Says what happened in terms of things
    /// the user can see: the library, the installer file, the drive. Never the
    /// software underneath.
    ///
    /// - Parameter appName: the app's display name, for the states that read
    ///   better naming it.
    func sentence(appName: String) -> String? {
        inProgressSentence ?? problemSentence(appName: appName)
    }

    /// Sentences for the states that describe what is happening now. None of
    /// them needs the app's name: the inspector is already showing it.
    private var inProgressSentence: String? {
        switch self {
        case .running: return String(localized: "status.running.detail")
        case .preparing: return String(localized: "status.preparing.detail")
        case .installing: return String(localized: "status.installing.detail")
        case .waitingForUpdate: return String(localized: "status.waitingForUpdate.detail")
        case .quitUnexpectedly: return String(localized: "status.quitUnexpectedly.detail")
        default: return nil
        }
    }

    /// Sentences for the states that need fixing. These do name the app, and
    /// the drive, because the sentence is what tells the user where to look.
    private func problemSentence(appName: String) -> String? {
        switch self {
        case .didNotInstall:
            return String(format: String(localized: "status.didNotInstall.detail"), appName)
        case .chooseProgram:
            return String(localized: "status.chooseProgram.detail")
        case .nothingInstalled:
            return String(localized: "status.nothingInstalled.detail")
        case .driveNotConnected(let volumeName):
            guard let volumeName else { return String(localized: "status.driveNotConnected.detail.unnamed") }
            return String(format: String(localized: "status.driveNotConnected.detail"), appName, volumeName)
        case .filesNotFound:
            return String(format: String(localized: "status.filesNotFound.detail"), appName)
        default:
            return nil
        }
    }

    /// What the inspector offers. First is the one most people want.
    var actions: [AppStatusAction] {
        switch self {
        case .ready, .notOpenedYet:
            return [.open]
        case .running:
            return [.showWindow, .quit]
        case .preparing:
            return [.cancelInstall]
        case .installing:
            return [.finishSetup, .cancelInstall]
        case .didNotInstall:
            return [.tryAgain, .removeFromLibrary, .showLog]
        case .chooseProgram:
            return [.chooseProgram]
        case .nothingInstalled:
            return [.chooseProgram, .installAgain, .removeFromLibrary]
        case .driveNotConnected, .filesNotFound:
            return [.locate, .removeFromLibrary]
        case .waitingForUpdate:
            return []
        case .quitUnexpectedly:
            return [.open, .openWithDiagnostics, .reportProblem]
        }
    }

    /// The colour the label and its dot take.
    var tint: Color {
        switch emphasis {
        case .neutral: return CrosswireTheme.textSecondary
        case .inProgress: return CrosswireTheme.accent
        case .attention: return CrosswireTheme.warning
        case .failure: return CrosswireTheme.danger
        }
    }
}

/// Something the user can do about a status.
///
/// An identifier rather than a closure so the vocabulary stays testable and
/// the wiring lives with the view that owns the behaviour. Titles are here
/// because they belong with the rest of the copy.
enum AppStatusAction: Equatable {
    case open
    case showWindow
    case quit
    case cancelInstall
    case finishSetup
    case tryAgain
    case chooseProgram
    case installAgain
    case locate
    case removeFromLibrary
    case showLog
    case openWithDiagnostics
    case reportProblem

    var title: String {
        switch self {
        case .open: return String(localized: "action.open")
        case .showWindow: return String(localized: "action.showWindow")
        case .quit: return String(localized: "action.quit")
        case .cancelInstall: return String(localized: "action.cancelInstall")
        case .finishSetup: return String(localized: "action.finishSetup")
        case .tryAgain: return String(localized: "action.tryAgain")
        case .chooseProgram: return String(localized: "action.chooseProgram")
        case .installAgain: return String(localized: "action.installAgain")
        case .locate: return String(localized: "action.locate")
        case .removeFromLibrary: return String(localized: "action.removeFromLibrary")
        case .showLog: return String(localized: "action.showLog")
        case .openWithDiagnostics: return String(localized: "action.openWithDiagnostics")
        case .reportProblem: return String(localized: "action.reportProblem")
        }
    }

    /// Removing an app deletes everything it installed, so it is never the
    /// default and it is never the same colour as the rest.
    var isDestructive: Bool {
        self == .removeFromLibrary
    }
}
