//
//  ShellLinkPathTests.swift
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

final class ShellLinkPathTests: XCTestCase {
    private let driveC = "/bottle/drive_c"

    func testUppercaseDriveIsRewritten() {
        XCTAssertEqual(
            LinkInfo.unixPath(fromWindowsPath: "C:\\Program Files (x86)\\Steam\\Steam.exe", driveC: driveC),
            "/bottle/drive_c/Program Files (x86)/Steam/Steam.exe"
        )
    }

    func testLowercaseDriveIsRewritten() {
        XCTAssertEqual(
            LinkInfo.unixPath(fromWindowsPath: "c:\\Program Files\\Foo\\foo.exe", driveC: driveC),
            "/bottle/drive_c/Program Files/Foo/foo.exe"
        )
    }

    func testOnlyTheLeadingDriveIsRewritten() {
        XCTAssertEqual(
            LinkInfo.unixPath(fromWindowsPath: "C:\\Games\\C:\\odd\\x.exe", driveC: driveC),
            "/bottle/drive_c/Games/C:/odd/x.exe"
        )
    }

    func testOtherDrivesAreLeftAlone() {
        XCTAssertEqual(
            LinkInfo.unixPath(fromWindowsPath: "Z:\\Applications\\Foo.exe", driveC: driveC),
            "Z:/Applications/Foo.exe"
        )
    }

    func testPathsDifferingOnlyByCaseAreTheSameFile() {
        let fromShortcut = URL(filePath: "/bottle/drive_c/Program Files (x86)/Steam/Steam.exe")
        let onDisk = URL(filePath: "/bottle/drive_c/Program Files (x86)/Steam/steam.exe")
        XCTAssertNotEqual(fromShortcut, onDisk)
        XCTAssertTrue(fromShortcut.isSameWindowsPath(as: onDisk))
    }

    func testDifferentFilesAreNotTheSame() {
        let first = URL(filePath: "/bottle/drive_c/Foo/a.exe")
        let second = URL(filePath: "/bottle/drive_c/Foo/b.exe")
        XCTAssertFalse(first.isSameWindowsPath(as: second))
        XCTAssertFalse(first.isSameWindowsPath(as: nil))
    }
}
