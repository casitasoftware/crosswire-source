//
//  WindowsUserNameTests.swift
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

/// A bottle created by this version names its Windows user `crosswire`
/// instead of the Mac account name. Older bottles must never be switched: the
/// engine regenerates part of the profile under the new name while leaving
/// the rest where it was, which splits one user's data across two profile
/// folders. Reproduced against the shipped engine before this change.
final class WindowsUserNameTests: XCTestCase {

    private var tempDir: URL!

    override func setUpWithError() throws {
        tempDir = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: tempDir)
    }

    func testLegacyBottleHasNoOverride() throws {
        // Metadata written before this change carries no windowsUserName key.
        let url = tempDir.appending(path: "Metadata.plist")
        try BottleSettings().encode(to: url)
        var plist = try XCTUnwrap(
            PropertyListSerialization.propertyList(from: Data(contentsOf: url), format: nil) as? [String: Any]
        )
        var info = try XCTUnwrap(plist["info"] as? [String: Any])
        info.removeValue(forKey: "windowsUserName")
        plist["info"] = info
        try PropertyListSerialization.data(fromPropertyList: plist, format: .xml, options: 0).write(to: url)

        let settings = try BottleSettings.decode(from: url)
        XCTAssertNil(settings.windowsUserName)
        XCTAssertEqual(settings.windowsUserEnvironment, [:])
    }

    func testStampedBottleSetsUserAndLogname() {
        var settings = BottleSettings()
        settings.windowsUserName = BottleSettings.defaultWindowsUserName
        // USER is what the engine names the profile from; LOGNAME is what
        // Winetricks uses, so both must agree.
        XCTAssertEqual(settings.windowsUserEnvironment, ["USER": "crosswire", "LOGNAME": "crosswire"])
    }

    func testStampSurvivesARoundTrip() throws {
        let url = tempDir.appending(path: "Metadata.plist")
        var settings = BottleSettings()
        settings.windowsUserName = "crosswire"
        try settings.encode(to: url)
        XCTAssertEqual(try BottleSettings.decode(from: url).windowsUserName, "crosswire")
    }

    @MainActor
    func testOverrideWinsOverCallerEnvironment() throws {
        // A per-program environment that happens to set USER must not be able
        // to launch a stamped bottle under a different name.
        let bottle = Bottle(bottleUrl: tempDir)
        bottle.settings.windowsUserName = "crosswire"
        let env = Wine.constructWineEnvironment(for: bottle, environment: ["USER": "nick", "FOO": "1"])
        XCTAssertEqual(env["USER"], "crosswire")
        XCTAssertEqual(env["LOGNAME"], "crosswire")
        XCTAssertEqual(env["FOO"], "1")
        XCTAssertEqual(Wine.constructWineServerEnvironment(for: bottle)["USER"], "crosswire")
    }

    @MainActor
    func testLegacyBottleEnvironmentIsUnchanged() throws {
        let bottle = Bottle(bottleUrl: tempDir)
        let env = Wine.constructWineEnvironment(for: bottle)
        XCTAssertNil(env["USER"])
        XCTAssertNil(env["LOGNAME"])
    }
}
