//
//  BottleData.swift
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
import SemanticVersion

public struct BottleData: Codable {
    /// Pre-2026-09 root, inherited from Whisky: `~/Library/Containers/<id>`.
    /// That is a sandbox-managed path and Crosswire is not sandboxed (it holds
    /// no `com.apple.security.app-sandbox` entitlement), so it was never the
    /// right home. It is still read for the one-time index migration below,
    /// and apps created before the move are still stored there and stay there.
    public static let legacyContainerDir = FileManager.default.homeDirectoryForCurrentUser
        .appending(path: "Library")
        .appending(path: "Containers")
        .appending(path: Bundle.CrosswireBundleIdentifier)

    static let legacyBottleEntriesDir = legacyContainerDir
        .appending(path: "BottleVM")
        .appendingPathExtension("plist")

    /// Shares `CrosswireEngine.applicationFolder` deliberately, so the app has
    /// one data root rather than two that can drift apart.
    public static let bottleEntriesDir = CrosswireEngine.applicationFolder
        .appending(path: "BottleVM")
        .appendingPathExtension("plist")

    /// `Apps`, not `Bottles`: the internal word never reaches a user.
    public static let defaultBottleDir = CrosswireEngine.applicationFolder
        .appending(path: "Apps")

    static let currentVersion = SemanticVersion(1, 0, 0)

    private var fileVersion: SemanticVersion
    public var paths: [URL] = [] {
        didSet {
            persist(newPaths: paths, oldPaths: oldValue)
        }
    }

    public init() {
        fileVersion = Self.currentVersion

        // Before `decode()`, never after: a miss makes `decode()` fail and the
        // `encode` below write a fresh EMPTY index at the new location, which
        // is an existing user opening Crosswire to an empty library with every
        // app still on disk.
        Self.migrateLegacyIndexIfNeeded()

        if !decode() {
            encode(paths: paths)
        }
    }

    /// Builds the bottle list from the index.
    ///
    /// Pass the bottles already in memory as `existing`. A bottle whose folder
    /// is still in the index is reused rather than rebuilt, because a rebuilt
    /// one starts with an empty `programs` list. Reloading after File > Import
    /// App, a remove, or a move would otherwise blank every other app's
    /// program list until a view happened to rescan it.
    @MainActor public mutating func loadBottles(reusing existing: [Bottle] = []) -> [Bottle] {
        var bottles: [Bottle] = []
        let known = Dictionary(existing.map { ($0.url, $0) }, uniquingKeysWith: { first, _ in first })

        for path in paths {
            if let kept = known[path] {
                kept.isAvailable = FileManager.default.fileExists(
                    atPath: path.appending(path: "Metadata").appendingPathExtension("plist").path(percentEncoded: false)
                )
                bottles.append(kept)
                continue
            }
            let bottleMetadata = path
                .appending(path: "Metadata")
                .appendingPathExtension("plist")
                .path(percentEncoded: false)

            if FileManager.default.fileExists(atPath: bottleMetadata) {
                bottles.append(Bottle(bottleUrl: path, isAvailable: true))
            } else {
                bottles.append(Bottle(bottleUrl: path))
            }
        }

        return bottles
    }

    /// One-time copy of the bottle index from the legacy Containers location
    /// to Application Support.
    ///
    /// This COPIES rather than moves, and that is a deliberate trade, not a
    /// free one. Copying leaves a downgrade working: an older build still
    /// finds its index where it expects. The cost is that the two files then
    /// diverge -- an app added in this build, followed by a downgrade, leaves
    /// the old plist stale, so that app is invisible to the older build until
    /// it is added again. A move would avoid the divergence and instead leave
    /// a downgrade with an empty library and no obvious cause, which is worse,
    /// so the copy stays. Nothing re-syncs the two files afterwards.
    ///
    /// The `UserDefaults` flag mirrors `removeLegacyEngineIfNeeded`, but is
    /// only a shortcut: correctness rests on the file checks below, so a copy
    /// that fails (disk full, permissions) is retried on the next launch
    /// rather than being permanently skipped by a flag set up front.
    static func migrateLegacyIndexIfNeeded() {
        let flagKey = "CrosswireBottleIndexMigrated"
        guard !UserDefaults.standard.bool(forKey: flagKey) else { return }

        let fileManager = FileManager.default
        let newPath = bottleEntriesDir.path(percentEncoded: false)
        let oldPath = legacyBottleEntriesDir.path(percentEncoded: false)

        // Nothing to carry over: a fresh install, or already migrated.
        guard !fileManager.fileExists(atPath: newPath),
              fileManager.fileExists(atPath: oldPath) else {
            UserDefaults.standard.set(true, forKey: flagKey)
            return
        }

        do {
            try fileManager.createDirectory(at: CrosswireEngine.applicationFolder,
                                            withIntermediateDirectories: true)
            try fileManager.copyItem(at: legacyBottleEntriesDir, to: bottleEntriesDir)
            UserDefaults.standard.set(true, forKey: flagKey)
        } catch {
            // Leave the flag unset so the next launch tries again.
        }
    }

    @discardableResult
    private mutating func decode() -> Bool {
        let decoder = PropertyListDecoder()
        do {
            let data = try Data(contentsOf: Self.bottleEntriesDir)
            self = try decoder.decode(BottleData.self, from: data)
            if self.fileVersion != Self.currentVersion {
                print("Invalid file version \(self.fileVersion)")
                return false
            }
            return true
        } catch {
            return false
        }
    }

    /// Reconciles this mutation against whatever is currently on disk before
    /// persisting, rather than trusting this instance's in-memory `paths` as
    /// authoritative. `didSet` fires with the full resulting array, and a
    /// plain re-encode of that array would silently drop any entry disk has
    /// but this instance's memory doesn't -- e.g. a second Crosswire process
    /// wrote a path after this instance last loaded, or this instance was
    /// initialized from a stale read. Diffing `oldPaths` against `newPaths`
    /// recovers what this mutation actually intended (add this one path, or
    /// remove that one path) and replays only that delta against a fresh
    /// read of disk, so an out-of-sync in-memory list can no longer clobber
    /// entries neither side asked to touch.
    private func persist(newPaths: [URL], oldPaths: [URL]) {
        let added = newPaths.filter { !oldPaths.contains($0) }
        let removed = oldPaths.filter { !newPaths.contains($0) }

        var reconciled = Self.readPathsFromDisk() ?? oldPaths
        reconciled.removeAll { removed.contains($0) }
        for path in added where !reconciled.contains(path) {
            reconciled.append(path)
        }

        encode(paths: reconciled)
    }

    /// Reads just the paths currently on disk, independent of this
    /// instance's in-memory state. Decoding a fresh `BottleData` does not
    /// trigger `paths`' `didSet` (Swift's synthesized `init(from:)` sets
    /// stored properties directly, bypassing property observers, the same
    /// way `decode()` below already relies on for app-launch loads), so this
    /// is safe to call from within `persist` without recursing.
    private static func readPathsFromDisk() -> [URL]? {
        let decoder = PropertyListDecoder()
        guard let data = try? Data(contentsOf: bottleEntriesDir) else { return nil }
        guard let decoded = try? decoder.decode(BottleData.self, from: data) else { return nil }
        guard decoded.fileVersion == currentVersion else { return nil }
        return decoded.paths
    }

    @discardableResult
    private func encode(paths: [URL]) -> Bool {
        let encoder = PropertyListEncoder()
        encoder.outputFormat = .xml

        do {
            try FileManager.default.createDirectory(at: CrosswireEngine.applicationFolder,
                                                    withIntermediateDirectories: true)
            let payload = Payload(fileVersion: fileVersion, paths: paths)
            let data = try encoder.encode(payload)
            try data.write(to: Self.bottleEntriesDir)
            return true
        } catch {
            return false
        }
    }

    /// Mirrors `BottleData`'s own two stored properties for encoding only.
    /// Encoding a `BottleData` value directly would require assigning to its
    /// `paths` property to set the reconciled array, which would re-trigger
    /// `didSet` -> `persist` recursively. This has the identical property
    /// names and types, so its synthesized Codable output is byte-identical
    /// to `BottleData`'s own, keeping the on-disk plist format unchanged.
    private struct Payload: Codable {
        var fileVersion: SemanticVersion
        var paths: [URL]
    }
}
