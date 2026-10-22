//
//  InstallerKindTests.swift
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

/// The inputs are copied from real files: four installers from a user's
/// Downloads folder, StarCraft's 1998 disc installer, and two installed apps
/// that must never be mistaken for installers.
final class InstallerKindTests: XCTestCase {

    private func classify(_ fileName: String, _ strings: [String: String] = [:],
                          sections: [String] = [".text", ".rdata", ".data", ".rsrc"]) -> InstallerKind? {
        InstallerKind.classify(fileName: fileName, versionStrings: strings, sectionNames: sections)
    }

    func testNSISIsRecognisedByItsDataSection() {
        XCTAssertEqual(classify("npp.8.9.8.Installer.x64.exe",
                                ["FileDescription": "Notepad++ : a free (GNU) source code editor",
                                 "ProductName": "Notepad++"],
                                sections: [".text", ".rdata", ".data", ".ndata", ".rsrc"]), .nsis)
    }

    func testInnoSetupIsRecognisedByItsComment() {
        XCTAssertEqual(classify("SWGLegendsSetup.exe",
                                ["FileDescription": "SWG Legends Setup",
                                 "Comments": "This installation was built with Inno Setup."]), .innoSetup)
        XCTAssertEqual(classify("lotrolive.exe",
                                ["FileDescription": "The Lord of the Rings Online",
                                 "Comments": "This installation was built with Inno Setup."]), .innoSetup)
    }

    func testDescriptionNamingAnInstallerIsAnInstaller() {
        // 7-Zip's installer: nothing in the filename says so.
        XCTAssertEqual(classify("7z2603-x64.exe",
                                ["FileDescription": "7-Zip Installer", "ProductName": "7-Zip"]), .other)
    }

    func testFilenameAloneIdentifiesADiscInstaller() {
        // StarCraft's SETUP.EXE has no version resource at all.
        XCTAssertEqual(classify("SETUP.EXE"), .other)
        XCTAssertEqual(classify("install.exe"), .other)
    }

    func testInstalledAppsAreNotInstallers() {
        XCTAssertNil(classify("7zFM.exe", ["FileDescription": "7-Zip File Manager", "ProductName": "7-Zip"]))
        XCTAssertNil(classify("SWGLegendsLauncher.exe",
                              ["FileDescription": "SWG Legends Launcher", "ProductName": "SWG Legends Launcher"]))
        XCTAssertNil(classify("notepad++.exe", ["ProductName": "Notepad++"]))
    }

    // MARK: - Silent install arguments
    //
    // Verified by running the real Notepad++ (NSIS) and SWG Legends (Inno
    // Setup) installers with these flags in a throwaway prefix under the
    // shipped engine: both exited 0, opened no window, installed their app
    // and created Start Menu shortcuts.

    func testNSISSilentFlag() {
        XCTAssertEqual(InstallerKind.nsis.silentArguments, ["/S"])
    }

    func testInnoSetupSilentFlags() {
        // /SP- drops the "This will install... Continue?" prompt that some
        // Inno installers show before the wizard, even in silent mode.
        XCTAssertEqual(InstallerKind.innoSetup.silentArguments,
                       ["/VERYSILENT", "/SUPPRESSMSGBOXES", "/NORESTART", "/SP-"])
    }

    func testUnknownEngineHasNoSilentMode() {
        // Flags differ per engine and a wrong one can be ignored or treated as
        // a file path, so an unidentified installer always runs visibly.
        XCTAssertNil(InstallerKind.other.silentArguments)
    }

    func testWordsInsideOtherWordsDoNotCount() {
        // "Setup" must be a word, not a substring: a game called "Upsetupper"
        // or a tool whose description merely mentions installing is not one.
        XCTAssertNil(classify("Upsetupper.exe"))
        XCTAssertNil(classify("tool.exe", ["FileDescription": "Reinstallation helper"]))
    }
}
