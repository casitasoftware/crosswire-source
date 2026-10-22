//
//  DisplayNameTests.swift
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

/// Real names seen in a library, and what a user should read instead.
final class DisplayNameTests: XCTestCase {

    // MARK: - Product names (VERSIONINFO, registry, Start Menu)

    func testCodeStyleProductNameIsSplitAndKnownAcronymUppercased() {
        // LotroLauncher.exe really ships ProductName = "lotroLauncher".
        XCTAssertEqual(DisplayName.fromProductName("lotroLauncher"), "LOTRO Launcher")
    }

    func testLauncherIsKept() {
        XCTAssertEqual(DisplayName.fromProductName("SWG Legends Launcher"), "SWG Legends Launcher")
    }

    func testRealNamesWithPunctuationAreUntouched() {
        XCTAssertEqual(DisplayName.fromProductName("7-Zip"), "7-Zip")
        XCTAssertEqual(DisplayName.fromProductName("Notepad++"), "Notepad++")
    }

    func testBrandsWithALowercasePrefixAreNotSplit() {
        XCTAssertEqual(DisplayName.fromProductName("iTunes"), "iTunes")
        XCTAssertEqual(DisplayName.fromProductName("eBay"), "eBay")
    }

    func testLeadingAcronymIsKeptTogether() {
        XCTAssertEqual(DisplayName.fromProductName("3DMark"), "3D Mark")
    }

    func testInstallerNoiseWordIsDropped() {
        XCTAssertEqual(DisplayName.fromProductName("Steam Setup"), "Steam")
        XCTAssertEqual(DisplayName.fromProductName("SWGLegendsSetup"), "SWG Legends")
    }

    func testAllNoiseKeepsTheOriginalRatherThanNothing() {
        XCTAssertEqual(DisplayName.fromProductName("Setup"), "Setup")
    }

    func testBlankIsNil() {
        XCTAssertNil(DisplayName.fromProductName("   "))
        XCTAssertNil(DisplayName.fromProductName(""))
    }

    func testKnownAcronymInsideSpacedName() {
        XCTAssertEqual(DisplayName.fromProductName("Lotro Launcher"), "LOTRO Launcher")
    }

    // MARK: - Installer filenames (placeholder while an install runs)

    func testInstallerFilenameDropsVersionArchAndNoise() {
        XCTAssertEqual(DisplayName.fromInstallerFilename("npp.8.9.8.Installer.x64"), "npp")
        XCTAssertEqual(DisplayName.fromInstallerFilename("SWGLegendsSetup"), "SWG Legends")
        XCTAssertEqual(DisplayName.fromInstallerFilename("7z2603-x64"), "7z2603")
        XCTAssertEqual(DisplayName.fromInstallerFilename("MyGame-Win64-Shipping"), "My Game")
    }

    func testInstallerFilenameThatIsAllNoiseIsKept() {
        XCTAssertEqual(DisplayName.fromInstallerFilename("SETUP"), "SETUP")
    }
}
