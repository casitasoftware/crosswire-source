//
//  FailureMonitoringTests.swift
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

@MainActor
final class FailureMonitoringTests: XCTestCase {
    private func report(exitCode: Int32 = 0, failure: ProgramRunReport.Failure? = nil,
                        completion: ProgramRunReport.Completion = .completed,
                        kind: ProgramRunReport.InvocationKind = .program) -> ProgramRunReport {
        ProgramRunReport(executableURL: URL(filePath: "/test/steam.exe"),
                         bottleURL: URL(filePath: "/test"), bottleDisplayName: "Steam",
                         exitCode: exitCode, duration: 1, logFileURL: nil, failure: failure,
                         completion: completion, kind: kind)
    }

    func testSteamNestedExceptionIsFailureEvenWhenParentExitsZero() {
        let line = "0194:err:virtual:virtual_setup_exception nested exception on signal stack addr 0x2086ead79"
        let failure = ProgramRunReport.Failure.detect(in: line)
        XCTAssertEqual(failure, .runtimeException)
        XCTAssertTrue(report(failure: failure).isAbnormal)
    }

    func testOrdinaryRuntimeNoiseIsNotClassifiedAsFatal() {
        for line in ["fixme:thread:SetThreadDescription stub", "[mvk-info] Created VkInstance",
                     "err:setupapi:SetupDefaultQueueCallbackW copy error 1812",
                     "err:module:import_dll Library optional.dll not found",
                     "Download complete.", "unhandled exception handling enabled"] {
            XCTAssertNil(ProgramRunReport.Failure.detect(in: line), line)
        }
        XCTAssertFalse(report().isAbnormal)
    }

    func testNonzeroExitStillReportsFailure() {
        XCTAssertTrue(report(exitCode: 1).isAbnormal)
    }

    func testMissingLibraryHasSpecificRecoveryReason() {
        let line = "err:module:loader_init Importing dlls for app.exe failed, status c0000135"
        XCTAssertEqual(ProgramRunReport.Failure.detect(in: line), .missingDependency)
    }

    func testObservedProcessCapturesFatalOutputWithZeroExit() async throws {
        let process = Process()
        process.executableURL = URL(filePath: "/bin/sh")
        let fatalLine = "0194:err:virtual:virtual_setup_exception nested exception on signal stack"
        process.arguments = ["-c", "printf '%s\\n' '\(fatalLine)' >&2; exit 0"]
        let observed = await report().observing(
            try process.runStream(name: "monitor-regression", fileHandle: nil), startedAt: Date()
        )
        XCTAssertEqual(observed.exitCode, 0)
        XCTAssertEqual(observed.failure, .runtimeException)
        XCTAssertTrue(observed.isAbnormal)
    }

    func testConcurrentLogsHaveDifferentPaths() throws {
        let first = try Wine.makeRunLog()
        let second = try Wine.makeRunLog()
        defer {
            try? first.handle.close()
            try? second.handle.close()
            try? FileManager.default.removeItem(at: first.url)
            try? FileManager.default.removeItem(at: second.url)
        }
        XCTAssertNotEqual(first.url, second.url)
        try first.handle.write(contentsOf: Data("first".utf8))
        try second.handle.write(contentsOf: Data("second".utf8))
        XCTAssertEqual(try String(contentsOf: first.url, encoding: .utf8), "first")
        XCTAssertEqual(try String(contentsOf: second.url, encoding: .utf8), "second")
    }

    func testIncompleteStreamDoesNotReportSuccessfulExit() async {
        let stream = AsyncStream<ProcessOutput> { $0.finish() }
        let observed = await report().observing(stream, startedAt: Date())
        XCTAssertEqual(observed.completion, .incomplete)
        XCTAssertFalse(observed.didSucceed)
        XCTAssertNotEqual(observed.exitCode, 0)
        XCTAssertTrue(observed.isAbnormal)
    }

    func testCancelledObservationDoesNotReportSuccessfulExit() async {
        let (stream, continuation) = AsyncStream<ProcessOutput>.makeStream()
        defer { continuation.finish() }
        let seed = report()
        let task = Task { await seed.observing(stream, startedAt: Date()) }
        task.cancel()
        let observed = await task.value
        XCTAssertEqual(observed.completion, .cancelled)
        XCTAssertFalse(observed.didSucceed)
        XCTAssertNotEqual(observed.exitCode, 0)
        XCTAssertFalse(observed.isAbnormal)
    }

    func testMSIUsesObservedInstallerDispatch() {
        XCTAssertEqual(WineLaunchRouting.arguments(at: URL(filePath: "/test/My Setup.MSI"),
                                                  args: ["/quiet"], observed: true),
                       ["msiexec", "/i", "/test/My Setup.MSI", "/quiet"])
    }

    func testBatchAndCommandScriptsUseCommandInterpreter() {
        for filename in ["setup.bat", "setup.CMD"] {
            XCTAssertEqual(WineLaunchRouting.arguments(at: URL(filePath: "/test/" + filename),
                                                      args: ["argument"], observed: true),
                           ["cmd", "/c", "/test/" + filename, "argument"])
        }
    }

    func testOtherFileTypesRetainAssociationDispatch() {
        XCTAssertEqual(WineLaunchRouting.arguments(at: URL(filePath: "/test/readme.txt"),
                                                  args: [], observed: true),
                       ["start", "/wait", "/unix", "/test/readme.txt"])
    }

    func testExecutableIsDirectAndExplicitDetachedModeIsPreserved() {
        let url = URL(filePath: "/test/app.EXE")
        XCTAssertEqual(WineLaunchRouting.arguments(at: url, args: ["--flag"], observed: true),
                       ["/test/app.EXE", "--flag"])
        XCTAssertEqual(WineLaunchRouting.arguments(at: url, args: ["--flag"], observed: false),
                       ["start", "/unix", "/test/app.EXE", "--flag"])
    }

    func testRequestedStopRetainsEvidenceWithoutReportingCrash() {
        let stopped = report(exitCode: 9, failure: .runtimeException, completion: .requestedStop)
        XCTAssertFalse(stopped.isAbnormal)
        XCTAssertFalse(stopped.didSucceed)
        XCTAssertEqual(stopped.failure, .runtimeException)
    }

    func testCancelledReportRetainsFatalEvidenceWithoutReportingCrash() {
        let cancelled = report(failure: .runtimeException, completion: .cancelled)
        XCTAssertFalse(cancelled.isAbnormal)
        XCTAssertFalse(cancelled.didSucceed)
        XCTAssertEqual(cancelled.failure, .runtimeException)
    }

    func testInstallerKindSurvivesObservation() async throws {
        let process = Process()
        process.executableURL = URL(filePath: "/usr/bin/true")
        let observed = await report(kind: .installer).observing(
            try process.runStream(name: "installer-kind", fileHandle: nil), startedAt: Date()
        )
        XCTAssertEqual(observed.completion, .completed)
        XCTAssertTrue(observed.didSucceed)
        XCTAssertTrue(observed.isInstaller)
    }

    private func sleepingProcess() throws -> Process {
        let process = Process()
        process.executableURL = URL(filePath: "/bin/sleep")
        process.arguments = ["30"]
        try process.run()
        return process
    }

    private func stop(_ process: Process) {
        if process.isRunning { process.terminate() }
        process.waitUntilExit()
    }

    func testStopMarksOnlyCurrentRunsInTargetBottle() async throws {
        let registry = WineRunRegistry()
        let process = try sleepingProcess()
        let otherProcess = try sleepingProcess()
        defer { stop(process); stop(otherProcess) }
        let old = registry.begin(bottleURL: URL(filePath: "/test"))
        old.process = process
        let other = registry.begin(bottleURL: URL(filePath: "/other"))
        other.process = otherProcess
        registry.withStopRequest(bottleURL: URL(filePath: "/test")) {}
        let fresh = registry.begin(bottleURL: URL(filePath: "/test"))
        fresh.process = process
        registry.finish(old)
        let stream = AsyncStream<ProcessOutput> {
            $0.yield(.error("wine: unhandled exception"))
            $0.finish()
        }
        let observed = await report().observing(stream, startedAt: Date(), requestedStop: { old.requestedStop })
        XCTAssertEqual(observed.completion, .requestedStop)
        XCTAssertEqual(observed.failure, .runtimeException)
        XCTAssertFalse(observed.isAbnormal)
        XCTAssertFalse(fresh.requestedStop)
        XCTAssertFalse(other.requestedStop)
    }

    func testStopDoesNotMaskAlreadyExitedRun() throws {
        let registry = WineRunRegistry()
        let process = try sleepingProcess()
        let run = registry.begin(bottleURL: URL(filePath: "/test"))
        run.process = process
        stop(process)
        registry.withStopRequest(bottleURL: URL(filePath: "/test")) {}
        XCTAssertFalse(run.requestedStop)
    }

    func testFailedStopRequestDoesNotSuppressFutureFailure() throws {
        let registry = WineRunRegistry()
        let process = try sleepingProcess()
        defer { stop(process) }
        let run = registry.begin(bottleURL: URL(filePath: "/test"))
        run.process = process
        XCTAssertThrowsError(try registry.withStopRequest(bottleURL: URL(filePath: "/test")) {
            throw CocoaError(.fileNoSuchFile)
        })
        XCTAssertFalse(run.requestedStop)
        registry.withStopRequest(bottleURL: URL(filePath: "/test")) {}
        XCTAssertThrowsError(try registry.withStopRequest(bottleURL: URL(filePath: "/test")) {
            throw CocoaError(.fileNoSuchFile)
        })
        XCTAssertTrue(run.requestedStop)
    }

    func testRunLogRecordsCompletionWithoutInventingCleanExit() throws {
        for completion in [ProgramRunReport.Completion.cancelled, .requestedStop, .incomplete] {
            let log = try Wine.makeRunLog()
            try log.handle.close()
            defer { try? FileManager.default.removeItem(at: log.url) }
            let report = ProgramRunReport(executableURL: URL(filePath: "/test/app.exe"),
                                          bottleURL: URL(filePath: "/test"), bottleDisplayName: "App",
                                          exitCode: -1, duration: 0, logFileURL: log.url,
                                          completion: completion, kind: .installer)
            Wine.recordOutcome(report)
            let text = try String(contentsOf: log.url, encoding: .utf8)
            XCTAssertTrue(text.contains("Observed completion: " + completion.rawValue))
            XCTAssertTrue(text.contains("Invocation kind: installer"))
            XCTAssertTrue(text.contains("Observed exit code: not observed"))
            XCTAssertFalse(text.contains("noneObserved"))
            XCTAssertFalse(text.contains("nonzeroExit"))
        }
    }

    func testNewLaunchFailureRemainsAbnormalAfterPriorStop() async throws {
        let registry = WineRunRegistry()
        let bottleURL = URL(filePath: "/test")
        let oldProcess = try sleepingProcess()
        defer { stop(oldProcess) }
        let old = registry.begin(bottleURL: bottleURL)
        old.process = oldProcess
        registry.withStopRequest(bottleURL: bottleURL) {}
        let fresh = registry.begin(bottleURL: bottleURL)
        let process = Process()
        fresh.process = process
        process.executableURL = URL(filePath: "/usr/bin/false")
        try process.run()
        process.waitUntilExit()
        registry.finish(old)
        let stream = AsyncStream<ProcessOutput> {
            $0.yield(.error("wine: unhandled exception"))
            $0.yield(.terminated(process))
            $0.finish()
        }
        let observed = await report().observing(stream, startedAt: Date(), requestedStop: { fresh.requestedStop })
        XCTAssertTrue(old.requestedStop)
        XCTAssertEqual(observed.completion, .completed)
        XCTAssertEqual(observed.exitCode, 1)
        XCTAssertEqual(observed.failure, .runtimeException)
        XCTAssertTrue(observed.isAbnormal)
    }

    func testLatePipeOutputDoesNotOverwriteCancellationSummary() throws {
        let log = try Wine.makeRunLog()
        defer {
            try? log.handle.close()
            try? FileManager.default.removeItem(at: log.url)
        }
        try log.handle.write(contentsOf: Data("before cancellation\n".utf8))
        let report = ProgramRunReport(executableURL: URL(filePath: "/test/app.exe"),
                                      bottleURL: URL(filePath: "/test"), bottleDisplayName: "App",
                                      exitCode: -1, duration: 0, logFileURL: log.url, completion: .cancelled)
        Wine.recordOutcome(report)
        try log.handle.write(contentsOf: Data("late pipe output\n".utf8))
        let text = try String(contentsOf: log.url, encoding: .utf8)
        XCTAssertTrue(text.contains("Observed completion: cancelled"))
        XCTAssertTrue(text.contains("late pipe output"))
    }

}
