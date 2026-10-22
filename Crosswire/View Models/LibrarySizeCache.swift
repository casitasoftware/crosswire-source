//
//  LibrarySizeCache.swift
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

/// On-disk sizes for library entries, measured once per launch in the
/// background.
///
/// The library shows size in a sortable column and in the inspector, so it is
/// needed for every entry rather than one at a time. Measuring it is not
/// cheap: `du -sk` on a 14 GB app walks the whole tree, and doing that from a
/// view body would stall the window.
///
/// So sizes arrive late and the interface says so. An entry with no size yet
/// shows a dash rather than zero, because zero sorts and reads as a fact, and
/// "not measured yet" is not the same as "empty".
///
/// Deliberately not persisted. A stale size is worse than a missing one: apps
/// grow as they are patched, and a number that silently disagrees with Finder
/// is a bug report. One measurement per launch is the compromise.
@MainActor
final class LibrarySizeCache: ObservableObject {

    /// Bytes per entry, for the entries measured so far.
    @Published private(set) var sizes: [URL: Int64] = [:]

    /// Entries whose measurement finished but found nothing readable. Kept
    /// apart from `sizes` so the interface can tell "unknown" from "pending"
    /// and stop asking.
    @Published private(set) var unmeasurable: Set<URL> = []

    private var inFlight: Set<URL> = []
    private var stale: Set<URL> = []

    /// At most two `du` walks at a time. One is needlessly slow on a library
    /// of thirty apps; unbounded turns a launch into a disk thrash, and the
    /// walks compete with whatever the user is actually doing.
    private let gate = AsyncSemaphore(limit: 2)

    /// The measured size, or nil while it is still being measured or could not
    /// be read.
    func size(of bottle: Bottle) -> Int64? {
        sizes[bottle.url]
    }

    /// Whether this entry has been measured, either way. Lets a view show a
    /// dash rather than a spinner once the answer is known to be unavailable.
    func isMeasured(_ bottle: Bottle) -> Bool {
        sizes[bottle.url] != nil || unmeasurable.contains(bottle.url)
    }

    /// Measure anything not measured yet. Safe to call repeatedly: entries
    /// already known or already being measured are skipped, so a view can call
    /// it on every appearance.
    func measure(_ bottles: [Bottle]) {
        for bottle in bottles {
            let url = bottle.url
            guard sizes[url] == nil, !unmeasurable.contains(url), !inFlight.contains(url) else { continue }
            inFlight.insert(url)
            Task { await measure(url) }
        }
    }

    /// Forget one entry's size so the next `measure` remeasures it. Used after
    /// an install finishes, when the old number is certainly wrong.
    func invalidate(_ bottle: Bottle) {
        sizes.removeValue(forKey: bottle.url)
        unmeasurable.remove(bottle.url)
        // A walk already running started before the change. Its result would
        // be stale, so mark it to be thrown away and redone.
        if inFlight.contains(bottle.url) { stale.insert(bottle.url) }
    }

    private func measure(_ url: URL) async {
        await gate.wait()
        defer { Task { await gate.signal() } }
        let measured = await Task.detached(priority: .utility) {
            BottleDiskUsage.approximateSize(of: url)
        }.value
        inFlight.remove(url)
        if stale.remove(url) != nil {
            inFlight.insert(url)
            await measure(url)
            return
        }
        if let measured {
            sizes[url] = measured
        } else {
            unmeasurable.insert(url)
        }
    }
}

/// A plain counting semaphore for async callers.
///
/// `DispatchSemaphore` cannot be used here: waiting on one from an async
/// context blocks a cooperative-pool thread, and blocking those is how you
/// deadlock Swift concurrency rather than merely slow it down.
actor AsyncSemaphore {
    private var available: Int
    private var waiting: [CheckedContinuation<Void, Never>] = []

    init(limit: Int) {
        available = limit
    }

    func wait() async {
        if available > 0 {
            available -= 1
            return
        }
        await withCheckedContinuation { waiting.append($0) }
    }

    func signal() {
        if waiting.isEmpty {
            available += 1
        } else {
            waiting.removeFirst().resume()
        }
    }
}
