//
//  ProgramRunReport.swift
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

/// Outcome of a single `Wine.runProgram` invocation. Produced after the
/// process exits and posted via `NotificationCenter` so the app can decide
/// whether to surface a failure-report dialog.
public struct ProgramRunReport: Sendable {
    /// The .exe / .bat file the user launched.
    public let executableURL: URL
    /// The bottle the program ran in.
    public let bottleURL: URL
    /// Display name of the bottle/app at launch time.
    public let bottleDisplayName: String
    /// The observed exit status, or -1 if no termination event was received.
    /// Check completion before interpreting this value as a process exit.
    public let exitCode: Int32
    /// Wall-clock time between exec and exit.
    public let duration: TimeInterval
    /// Path to the run log written by `Wine.runWineProcess`. Used to attach
    /// the tail of the log to a GitHub issue.
    public let logFileURL: URL?

    /// Explicit fatal output is evidence even if an installer or starter exits zero.
    public enum Failure: String, Sendable {
        case runtimeException
        case missingDependency

        public static func detect(in line: String) -> Failure? {
            let line = line.lowercased()
            if line.contains("err:virtual:virtual_setup_exception nested exception on signal stack")
                || line.contains("wine: unhandled exception")
                || line.contains("wine: unhandled page fault") {
                return .runtimeException
            }
            if line.contains("err:module:loader_init importing dlls for")
                && line.contains("failed, status c0000135") {
                return .missingDependency
            }
            return nil
        }

        public var recoveryAdvice: String {
            switch self {
            case .runtimeException:
                return "The app stopped while running. Save the log before trying again."
            case .missingDependency:
                return "The app could not load a required component. Use Check Dependencies, then try again."
            }
        }
    }

    public enum Completion: String, Sendable {
        case completed
        case cancelled
        case requestedStop
        case incomplete
    }

    public enum InvocationKind: String, Sendable {
        case program
        case installer
    }

    public let completion: Completion
    public let kind: InvocationKind
    public var isInstaller: Bool { kind == .installer }
    public var didSucceed: Bool { completion == .completed && exitCode == 0 && failure == nil }
    public let failure: Failure?
    public var isAbnormal: Bool {
        switch completion {
        case .cancelled, .requestedStop: return false
        case .incomplete: return true
        case .completed: return exitCode != 0 || failure != nil
        }
    }

    /// Shared by app and installer launches, and exercised with real process
    /// streams in tests. No generic warning is promoted to a crash.
    @MainActor
    public func observing(
        _ stream: AsyncStream<ProcessOutput>, startedAt: Date,
        requestedStop: @MainActor () -> Bool = { false }
    ) async -> ProgramRunReport {
        var observedExitCode: Int32?
        var observedFailure: Failure?
        for await output in stream {
            switch output {
            case .terminated(let process): observedExitCode = process.terminationStatus
            case .message(let line), .error(let line):
                observedFailure = observedFailure ?? Failure.detect(in: line)
            case .started: break
            }
        }
        let completion: Completion
        if requestedStop() {
            completion = .requestedStop
        } else if observedExitCode != nil {
            completion = .completed
        } else {
            completion = Task.isCancelled ? .cancelled : .incomplete
        }
        return ProgramRunReport(executableURL: executableURL, bottleURL: bottleURL,
                                bottleDisplayName: bottleDisplayName, exitCode: observedExitCode ?? -1,
                                duration: Date().timeIntervalSince(startedAt), logFileURL: logFileURL,
                                failure: observedFailure, completion: completion, kind: kind)
    }

    public init(
        executableURL: URL,
        bottleURL: URL,
        bottleDisplayName: String,
        exitCode: Int32,
        duration: TimeInterval,
        logFileURL: URL?,
        failure: Failure? = nil,
        completion: Completion = .completed,
        kind: InvocationKind = .program
    ) {
        self.executableURL = executableURL
        self.bottleURL = bottleURL
        self.bottleDisplayName = bottleDisplayName
        self.exitCode = exitCode
        self.duration = duration
        self.logFileURL = logFileURL
        self.failure = failure
        self.completion = completion
        self.kind = kind
    }
}

public extension Notification.Name {
    /// Posted after every `Wine.runProgram` invocation. The notification
    /// `object` is the `ProgramRunReport`. UI layers subscribe to decide
    /// whether to show a failure-report dialog.
    static let crosswireProgramDidExit = Notification.Name("crosswireProgramDidExit")
}
