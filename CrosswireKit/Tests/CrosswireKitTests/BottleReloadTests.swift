//
//  BottleReloadTests.swift
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
final class BottleReloadTests: XCTestCase {
    private func makeBottleFolder() throws -> URL {
        let folder = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        FileManager.default.createFile(
            atPath: folder.appending(path: "Metadata").appendingPathExtension("plist").path(percentEncoded: false),
            contents: nil
        )
        addTeardownBlock { try? FileManager.default.removeItem(at: folder) }
        return folder
    }

    func testReloadKeepsTheSameBottleObjects() throws {
        let first = try makeBottleFolder()
        let second = try makeBottleFolder()
        var data = BottleData()
        data.paths = [first, second]

        let loaded = data.loadBottles()
        XCTAssertEqual(loaded.count, 2)
        let kept = try XCTUnwrap(loaded.first { $0.url == first })
        kept.programs = [Program(url: first.appending(path: "drive_c/app.exe"), bottle: kept)]

        // File > Import App appends a path and reloads.
        let third = try makeBottleFolder()
        data.paths.append(third)
        let reloaded = data.loadBottles(reusing: loaded)

        XCTAssertEqual(reloaded.count, 3)
        let again = try XCTUnwrap(reloaded.first { $0.url == first })
        XCTAssertTrue(again === kept)
        XCTAssertEqual(again.programs.count, 1)
    }

    func testReloadDropsRemovedBottles() throws {
        let first = try makeBottleFolder()
        let second = try makeBottleFolder()
        var data = BottleData()
        data.paths = [first, second]
        let loaded = data.loadBottles()

        data.paths.removeAll { $0 == second }
        let reloaded = data.loadBottles(reusing: loaded)

        XCTAssertEqual(reloaded.map(\.url), [first])
    }

    func testPersistedProgramCountReadsSavedShortcuts() throws {
        let folder = try makeBottleFolder()
        let bottle = Bottle(bottleUrl: folder, isAvailable: true)
        XCTAssertEqual(bottle.persistedVisibleProgramCount, 0)
        bottle.settings.userVisibleProgramURLs = [folder.appending(path: "a.exe")]
        XCTAssertEqual(bottle.persistedVisibleProgramCount, 1)
    }
    func testFreshLoadRestoresExistingSavedLaunchers() throws {
        let folder = try makeBottleFolder()
        let executable = folder.appending(path: "Steam/steam.exe")
        try FileManager.default.createDirectory(at: executable.deletingLastPathComponent(),
                                                withIntermediateDirectories: true)
        try Data().write(to: executable)
        let original = Bottle(bottleUrl: folder, isAvailable: true)
        original.settings.userVisibleProgramURLs = [executable]
        original.settings.primaryProgramURL = executable

        let restored = Bottle(bottleUrl: folder, isAvailable: true)
        XCTAssertEqual(restored.programs.map(\.url), [executable])
    }

    func testFreshLoadDoesNotRestoreDeletedLaunchers() throws {
        let folder = try makeBottleFolder()
        let original = Bottle(bottleUrl: folder, isAvailable: true)
        original.settings.userVisibleProgramURLs = [folder.appending(path: "missing.exe")]
        let restored = Bottle(bottleUrl: folder, isAvailable: true)
        XCTAssertTrue(restored.programs.isEmpty)
    }

}
