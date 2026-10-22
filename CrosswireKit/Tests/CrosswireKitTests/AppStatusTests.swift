//
//  AppStatusTests.swift
//  CrosswireKitTests
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

import XCTest
@testable import CrosswireKit

/// The status rules exist because several of these conditions are routinely
/// true at once, and the old code showed one word, "Unavailable", for three
/// unrelated problems with three different fixes. What matters is which status
/// wins when they collide, so most of these tests set two conditions and
/// assert which one the user is told about.
final class AppStatusTests: XCTestCase {

    // MARK: - The quiet states

    func testInstalledAndOpenedBeforeSaysNothing() {
        let status = AppStatus.resolve(.init())
        XCTAssertEqual(status, .ready)
        XCTAssertFalse(status.showsIndicator, "a healthy app must carry no marker")
        XCTAssertTrue(status.canOpen)
    }

    func testNeverOpenedIsQuietButLabelled() {
        let status = AppStatus.resolve(.init(hasEverOpened: false))
        XCTAssertEqual(status, .notOpenedYet)
        XCTAssertFalse(status.showsIndicator, "never opened is normal, not a problem")
        XCTAssertTrue(status.canOpen)
    }

    // MARK: - Precedence

    func testUpdatingWindowsSupportOutranksEverything() {
        // Every other action would fail until the update finishes, so telling
        // the user to reconnect a drive or pick a program would waste a trip.
        let status = AppStatus.resolve(.init(
            isAvailable: false,
            volumeIsMissing: true,
            volumeName: "Games SSD",
            hasAnyProgram: false,
            isWindowsSupportUpdating: true
        ))
        XCTAssertEqual(status, .waitingForUpdate)
        XCTAssertFalse(status.canOpen)
    }

    func testRunningBeatsAStaleAvailabilityFlag() {
        // If a window is on screen, the app is plainly reachable. Saying the
        // files are missing while the user is looking at it destroys trust in
        // every other status.
        let status = AppStatus.resolve(.init(isAvailable: false, isRunning: true))
        XCTAssertEqual(status, .running)
    }

    func testMissingDriveBeatsMissingFiles() {
        // A disconnected volume also makes the folder look deleted. Only one
        // of the two fixes works, so the drive has to win.
        let status = AppStatus.resolve(.init(
            isAvailable: false, volumeIsMissing: true, volumeName: "Games SSD"
        ))
        XCTAssertEqual(status, .driveNotConnected(volumeName: "Games SSD"))
    }

    func testMissingFilesWhenTheVolumeIsPresent() {
        let status = AppStatus.resolve(.init(isAvailable: false, volumeIsMissing: false))
        XCTAssertEqual(status, .filesNotFound)
    }

    func testPreparingBeatsHavingNoProgramsYet() {
        // Mid-provision an entry has no programs. "Nothing installed" would be
        // both wrong and alarming.
        let status = AppStatus.resolve(.init(
            isPreparing: true, hasAnyProgram: false, hasEverOpened: false
        ))
        XCTAssertEqual(status, .preparing)
    }

    func testInstallingBeatsHavingNoProgramsYet() {
        let status = AppStatus.resolve(.init(
            isInstalling: true, hasAnyProgram: false, hasEverOpened: false
        ))
        XCTAssertEqual(status, .installing)
    }

    func testInstallerThatNeverStarted() {
        let status = AppStatus.resolve(.init(
            installerFailedToStart: true, hasAnyProgram: false, hasEverOpened: false
        ))
        XCTAssertEqual(status, .didNotInstall)
    }

    func testInstallerThatFinishedAndLeftNothing() {
        let status = AppStatus.resolve(.init(
            visibleProgramCount: 0, hasAnyProgram: false, hasEverOpened: false
        ))
        XCTAssertEqual(status, .nothingInstalled)
    }

    // MARK: - Choosing a program

    func testSeveralProgramsAndNoPrimaryAsksForAChoice() {
        let status = AppStatus.resolve(.init(visibleProgramCount: 3, hasPrimaryProgram: false))
        XCTAssertEqual(status, .chooseProgram)
        XCTAssertFalse(status.canOpen, "there is nothing to open until one is picked")
    }

    func testSeveralProgramsWithAPrimarySetIsNotAQuestion() {
        let status = AppStatus.resolve(.init(visibleProgramCount: 3, hasPrimaryProgram: true))
        XCTAssertEqual(status, .ready)
    }

    func testASingleProgramIsNeverAQuestion() {
        // One program with no primary recorded is the common case, and it is
        // unambiguous: there is only one thing Open could mean.
        let status = AppStatus.resolve(.init(visibleProgramCount: 1, hasPrimaryProgram: false))
        XCTAssertEqual(status, .ready)
    }

    // MARK: - Crashes

    func testACrashIsReportedOnceTheAppIsOtherwiseHealthy() {
        let status = AppStatus.resolve(.init(lastRunCrashed: true))
        XCTAssertEqual(status, .quitUnexpectedly)
        XCTAssertTrue(status.canOpen, "a crash last time must not block trying again")
    }

    func testACrashDoesNotHideAMissingDrive() {
        let status = AppStatus.resolve(.init(
            isAvailable: false, volumeIsMissing: true, volumeName: "Games SSD",
            lastRunCrashed: true
        ))
        XCTAssertEqual(status, .driveNotConnected(volumeName: "Games SSD"))
    }

    // MARK: - Shape of the vocabulary

    func testOnlyTheQuietStatesLackAnIndicator() {
        let quiet: [AppStatus] = [.ready, .notOpenedYet]
        let loud: [AppStatus] = [
            .running, .preparing, .installing, .didNotInstall, .chooseProgram,
            .nothingInstalled, .driveNotConnected(volumeName: nil), .filesNotFound,
            .waitingForUpdate, .quitUnexpectedly
        ]
        for status in quiet { XCTAssertFalse(status.showsIndicator, "\(status)") }
        for status in loud { XCTAssertTrue(status.showsIndicator, "\(status)") }
    }

    func testNothingInProgressOrBrokenCanBeOpened() {
        let blocked: [AppStatus] = [
            .preparing, .installing, .didNotInstall, .chooseProgram, .nothingInstalled,
            .driveNotConnected(volumeName: nil), .filesNotFound, .waitingForUpdate
        ]
        for status in blocked { XCTAssertFalse(status.canOpen, "\(status)") }
    }

    func testDriveNameIsCarriedSoTheAppCanNameIt() {
        // The sentence is "The app is on <name>, which isn't connected", so
        // losing the name loses the only actionable part of it.
        guard case let .driveNotConnected(name) = AppStatus.resolve(
            .init(isAvailable: false, volumeIsMissing: true, volumeName: "Games SSD")
        ) else { return XCTFail("expected driveNotConnected") }
        XCTAssertEqual(name, "Games SSD")
    }
}
