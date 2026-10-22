//
//  WineLaunchRouting.swift
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

internal enum WineLaunchRouting {
    static func arguments(at url: URL, args: [String], observed: Bool) -> [String] {
        let path = url.path(percentEncoded: false)
        guard observed else { return ["start", "/unix", path] + args }
        switch url.pathExtension.lowercased() {
        case "exe", "com": return [path] + args
        case "msi": return ["msiexec", "/i", path] + args
        case "bat", "cmd": return ["cmd", "/c", path] + args
        default: return ["start", "/wait", "/unix", path] + args
        }
    }
}

/// One invocation owns its stop flag. Removing it never resets another run.
@MainActor
internal final class WineRunObservation {
    let id = UUID()
    let bottleURL: URL
    var process: Process?
    var requestedStop = false

    init(bottleURL: URL) {
        self.bottleURL = bottleURL
    }
}

@MainActor
internal final class WineRunRegistry {
    private var active: [UUID: WineRunObservation] = [:]

    func begin(bottleURL: URL) -> WineRunObservation {
        let run = WineRunObservation(bottleURL: bottleURL)
        active[run.id] = run
        return run
    }

    func finish(_ run: WineRunObservation) {
        active.removeValue(forKey: run.id)
    }

    func withStopRequest<T>(bottleURL: URL, _ start: () throws -> T) rethrows -> T {
        // This closure must start the stop process synchronously on MainActor.
        // There is no suspension between selecting runs and issuing the stop.
        let affected = active.values.filter {
            $0.bottleURL == bottleURL && !$0.requestedStop && $0.process?.isRunning == true
        }
        for run in affected { run.requestedStop = true }
        do {
            return try start()
        } catch {
            // A failed spawn did not issue a stop. Preserve any earlier request.
            for run in affected { run.requestedStop = false }
            throw error
        }
    }
}
