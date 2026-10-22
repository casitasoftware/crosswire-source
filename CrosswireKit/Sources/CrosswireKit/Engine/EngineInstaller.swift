//
//  EngineInstaller.swift
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

/// Progress reported by a running engine install.
public enum EngineInstallEvent: Sendable, Equatable {
    case fetchingManifest
    case downloading(written: Int64, total: Int64)
    case verifying
    case installed
}

/// Single-flight coordinator for engine installs.
///
/// The guard lives here rather than in the view because a SwiftUI view's
/// `@State` does not survive re-insertion: a re-inserted `EngineSetupView`
/// gets a fresh `isRunning = false` and would start a second download that
/// races the first one's install. #147.
///
/// Callers that arrive while an install is running join it instead of starting
/// another, and receive the same progress events, so a replacement view keeps
/// rendering a live progress bar rather than a frozen one.
public actor EngineInstaller {
    public typealias EventHandler = @Sendable (EngineInstallEvent) -> Void
    public typealias Operation = @Sendable (@escaping EventHandler) async throws -> Void

    public static let shared = EngineInstaller()

    private let operation: Operation
    private var inFlight: Task<Void, Error>?
    private var observers: [UUID: EventHandler] = [:]

    init(operation: @escaping Operation = { onEvent in
        try await CrosswireEngine.performInstall(onEvent: onEvent)
    }) {
        self.operation = operation
    }

    /// Runs an engine install, or joins the one already running.
    ///
    /// Returns when the install finishes. Throws whatever the install threw,
    /// to every caller that was waiting on it.
    public func install(onEvent: @escaping EventHandler) async throws {
        let id = UUID()
        observers[id] = onEvent
        defer { observers[id] = nil }

        let task: Task<Void, Error>
        if let existing = inFlight {
            task = existing
        } else {
            let started = Task { [operation] in
                // Clear the slot as the LAST thing inside the task, before it
                // completes. Two alternatives are both wrong: the caller's
                // `defer` frees the slot on cancellation while the download is
                // still running, and a separately spawned clean-up task leaves
                // a window where the task has finished but the slot still
                // points at it, so a new caller joins a dead install and gets
                // its result, or its stale error, instead of a fresh attempt.
                let outcome: Result<Void, Error>
                do {
                    try await operation { event in
                        Task { await self.broadcast(event) }
                    }
                    outcome = .success(())
                } catch {
                    outcome = .failure(error)
                }
                // No `await`: this Task inherits the actor's isolation.
                self.clearInFlight()
                return try outcome.get()
            }
            inFlight = started
            task = started
        }

        try await task.value
    }

    /// Stops the running install, if any.
    ///
    /// Only safe before the verify step: `performInstall` checks for
    /// cancellation once more right before it replaces the installed files, so
    /// a cancelled download never reaches the step that deletes the old copy.
    /// Callers waiting on the install receive a `CancellationError`.
    public func cancel() {
        inFlight?.cancel()
    }

    /// Number of callers currently waiting on an install.
    ///
    /// Test seam: lets a test wait until a second caller has genuinely joined,
    /// instead of assuming it from timing.
    var observerCount: Int { observers.count }

    private func clearInFlight() {
        inFlight = nil
    }

    private func broadcast(_ event: EngineInstallEvent) {
        for observer in observers.values {
            observer(event)
        }
    }
}
