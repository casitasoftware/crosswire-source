//
//  EngineInstallerTests.swift
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

final class EngineInstallerTests: XCTestCase {

    /// Counts the two destructive steps a duplicate install would repeat:
    /// pulling the archive down, and unpacking it over the installed engine.
    private actor InstallCounters {
        private(set) var downloads = 0
        private(set) var extracts = 0

        func startedDownload() { downloads += 1 }
        func startedExtract() { extracts += 1 }
    }

    /// A one-shot latch. `wait()` suspends until `open()` is called, and
    /// returns immediately ever after, so the order of the two is irrelevant.
    private actor Gate {
        private var isOpen = false
        private var waiters: [CheckedContinuation<Void, Never>] = []

        func open() {
            guard !isOpen else { return }
            isOpen = true
            let resuming = waiters
            waiters = []
            for waiter in resuming { waiter.resume() }
        }

        func wait() async {
            if isOpen { return }
            await withCheckedContinuation { continuation in
                waiters.append(continuation)
            }
        }
    }

    /// Two callers arriving while an install is running must share one run.
    /// This is the #147 case: SwiftUI re-inserts EngineSetupView, `.onAppear`
    /// fires a second time, and the view's own `@State` guard is back to false
    /// because the new instance got fresh state.
    ///
    /// The install holds at `holdInstall` until the second caller has actually
    /// joined, so the test proves single-flight rather than proving that one
    /// sleep outlasted another.
    func testConcurrentInstallsRunDownloadAndExtractOnce() async throws {
        let counters = InstallCounters()
        let downloadStarted = Gate()
        let holdInstall = Gate()

        let installer = EngineInstaller(operation: { onEvent in
            await counters.startedDownload()
            onEvent(.downloading(written: 0, total: 100))

            // Tell the test the install is underway, then block until it says
            // the second caller has joined.
            await downloadStarted.open()
            await holdInstall.wait()

            await counters.startedExtract()
            onEvent(.verifying)
            onEvent(.installed)
        })

        async let first: Void = installer.install { _ in }

        // Do not race the first caller: wait until its install is genuinely
        // running before the second one arrives.
        await downloadStarted.wait()

        async let second: Void = installer.install { _ in }

        // Wait for the second caller to actually register on the actor. Opening
        // the gate before it joined would let the install finish first, and the
        // second caller would start a fresh run through no fault of the code.
        while await installer.observerCount < 2 {
            await Task.yield()
        }

        await holdInstall.open()
        _ = try await (first, second)

        let downloads = await counters.downloads
        let extracts = await counters.extracts
        XCTAssertEqual(downloads, 1, "second caller started a second download")
        XCTAssertEqual(extracts, 1, "second caller started a second extract")
    }

    private struct InstallFailure: Error {}

    /// A caller arriving after an install finished must get a fresh attempt,
    /// not the finished task's result. The failure case is the one that bites:
    /// a retry that replays the previous error looks like a reproducible fault
    /// when nothing was actually retried.
    func testRetryAfterFailureStartsAFreshInstall() async throws {
        let attempts = InstallCounters()
        let installer = EngineInstaller(operation: { _ in
            let attempt = await attempts.downloads
            await attempts.startedDownload()
            if attempt == 0 { throw InstallFailure() }
        })

        do {
            try await installer.install { _ in }
            XCTFail("first install should have thrown")
        } catch is InstallFailure {
            // expected
        }

        // Must not re-throw the first attempt's error.
        try await installer.install { _ in }

        let total = await attempts.downloads
        XCTAssertEqual(total, 2, "retry joined the finished task instead of starting over")
    }

    /// Cancel stops the running install, the waiting caller gets a
    /// cancellation, and the next caller starts a fresh install rather than
    /// joining the cancelled one.
    func testCancelStopsTheInstallAndTheNextCallStartsFresh() async throws {
        let attempts = InstallCounters()
        let started = Gate()
        let installer = EngineInstaller(operation: { _ in
            let attempt = await attempts.downloads
            await attempts.startedDownload()
            guard attempt == 0 else { return }
            await started.open()
            // Stands in for the download: runs until cancelled.
            try await Task.sleep(for: .seconds(60))
        })

        let first = Task { try await installer.install { _ in } }
        await started.wait()
        await installer.cancel()

        do {
            try await first.value
            XCTFail("a cancelled install should throw")
        } catch is CancellationError {
            // expected
        }

        try await installer.install { _ in }
        let total = await attempts.downloads
        XCTAssertEqual(total, 2, "the install after a cancel joined the cancelled one")
    }
}
