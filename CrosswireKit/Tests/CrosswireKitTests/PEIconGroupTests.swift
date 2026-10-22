//
//  PEIconGroupTests.swift
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

import AppKit
import XCTest
@testable import CrosswireKit

/// `bestIcon()` must return the icon Windows Explorer shows for an exe: the
/// largest member of the FIRST icon group, decoded with correct colours.
///
/// Both fixtures were built with mingw + windres from hand-written .ico files
/// whose pixels are known: left half red, right half blue, top-left 4x4
/// transparent through the AND mask. Each also carries a second, LARGER icon
/// group in solid green that is not the app icon, which is how real exes are
/// laid out (7zFM.exe ships its 32/48px app icon in group 1 and a 110px image
/// in group 100).
///
/// - `icon-named-group-pe.exe` (x64): the app icon lives in a NAMED group,
///   `MAINICON`, holding 16px and 32px 4bpp images; group id 100 holds a 64px
///   32bpp decoy. Named entries sort before ID entries, so MAINICON is first.
/// - `icon-idgroups-pe.exe` (x86): group id 1 holds a 30px 8bpp image, whose
///   30-byte rows need padding to a 4-byte stride; group id 100 holds a 110px
///   8bpp decoy.
final class PEIconGroupTests: XCTestCase {

    private func icon(_ name: String) throws -> NSImage {
        let url = try XCTUnwrap(Bundle.module.url(forResource: name, withExtension: "exe"))
        return try XCTUnwrap(try PEFile(url: url).bestIcon(), "\(name) should yield an icon")
    }

    private struct RGBA: CustomStringConvertible {
        let red: UInt8, green: UInt8, blue: UInt8, alpha: UInt8
        var description: String { "rgba(\(red), \(green), \(blue), \(alpha))" }
    }

    /// Renders `image` into an RGBA buffer at its own pixel size and returns
    /// the colour at (column, row), with (0, 0) at the TOP-left.
    private func pixel(_ image: NSImage, _ column: Int, _ row: Int) throws -> RGBA {
        let cgImage = try XCTUnwrap(image.cgImage(forProposedRect: nil, context: nil, hints: nil))
        let width = cgImage.width, height = cgImage.height
        var buffer = [UInt8](repeating: 0, count: width * height * 4)
        let ctx = try XCTUnwrap(CGContext(
            data: &buffer, width: width, height: height, bitsPerComponent: 8, bytesPerRow: width * 4,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ))
        ctx.draw(cgImage, in: CGRect(x: 0, y: 0, width: width, height: height))
        let index = (row * width + column) * 4
        return RGBA(red: buffer[index], green: buffer[index + 1], blue: buffer[index + 2], alpha: buffer[index + 3])
    }

    private func assertPattern(_ image: NSImage, side: Int, file: StaticString = #filePath, line: UInt = #line) throws {
        let cgImage = try XCTUnwrap(image.cgImage(forProposedRect: nil, context: nil, hints: nil))
        XCTAssertEqual(cgImage.width, side, "picked the wrong icon", file: file, line: line)
        XCTAssertEqual(cgImage.height, side, "picked the wrong icon", file: file, line: line)

        let left = try pixel(image, side / 4, side / 2)
        XCTAssertTrue(left.red > 200 && left.green < 40 && left.blue < 40 && left.alpha == 255,
                      "left half should be opaque red, got \(left)", file: file, line: line)
        let right = try pixel(image, side * 3 / 4, side / 2)
        XCTAssertTrue(right.blue > 200 && right.red < 40 && right.green < 40 && right.alpha == 255,
                      "right half should be opaque blue, got \(right)", file: file, line: line)
        let corner = try pixel(image, 1, 1)
        XCTAssertEqual(corner.alpha, 0, "AND-masked corner should be transparent, got \(corner)",
                       file: file, line: line)
    }

    func testNamedFirstGroupBeatsLargerDecoy() throws {
        try assertPattern(try icon("icon-named-group-pe"), side: 32)
    }

    func testFirstIDGroupBeatsLargerDecoyWithPaddedStride() throws {
        try assertPattern(try icon("icon-idgroups-pe"), side: 30)
    }

    // MARK: - The whole group, not just its largest member

    private func iconSet(_ name: String) throws -> PEIconSet {
        let url = try XCTUnwrap(Bundle.module.url(forResource: name, withExtension: "exe"))
        return try XCTUnwrap(try PEFile(url: url).iconSet(), "\(name) should yield an icon set")
    }

    /// MAINICON holds 16px and 32px. Both must survive as representations: a
    /// 22 pt list row has to be able to draw the file's own 16 or 32 px art
    /// instead of shrinking the largest member.
    func testEveryGroupMemberBecomesARepresentation() throws {
        let set = try iconSet("icon-named-group-pe")
        let sizes = set.image.representations.map(\.pixelsWide).sorted()
        XCTAssertEqual(sizes, [16, 32])
        XCTAssertEqual(set.maxPixelSize, 32)
        XCTAssertEqual(set.image.size, NSSize(width: 32, height: 32))
    }

    /// Each representation declares its own pixel size, which is what makes
    /// AppKit choose between them by draw size rather than treating them as
    /// 1x/2x copies of one size.
    func testRepresentationsDeclareTheirOwnSizes() throws {
        let set = try iconSet("icon-named-group-pe")
        for rep in set.image.representations {
            XCTAssertEqual(Int(rep.size.width), rep.pixelsWide, "rep should be sized in its own pixels")
        }
    }

    /// Both fixtures are palette art, so drawing code must scale them
    /// nearest-neighbour rather than interpolating. 4bpp and 8bpp both count.
    func testPaletteDepthIsCarriedThrough() throws {
        let named = try iconSet("icon-named-group-pe")
        XCTAssertEqual(named.maxBitCount, 4)
        XCTAssertTrue(named.isPalette)

        let ids = try iconSet("icon-idgroups-pe")
        XCTAssertEqual(ids.maxBitCount, 8)
        XCTAssertTrue(ids.isPalette, "8bpp is the top of the palette range, not past it")
    }

    /// A group routinely lists one size at several depths. Keeping both would
    /// leave AppKit to pick between same-sized representations arbitrarily.
    func testOneRepresentationPerSizeKeepingTheDeepest() throws {
        // Notepad++'s real first group, trimmed: 48px appears at both depths.
        let members = [
            PEIcon.GroupMember(width: 48, height: 48, bitCount: 8, iconID: 1),
            PEIcon.GroupMember(width: 48, height: 48, bitCount: 32, iconID: 2),
            PEIcon.GroupMember(width: 16, height: 16, bitCount: 32, iconID: 3)
        ]
        let kept = PEIcon.deepestPerSize(members)
        XCTAssertEqual(kept.map(\.width), [16, 48], "smallest first, one per size")
        XCTAssertEqual(kept.last?.iconID, 2, "the 32bpp 48px member should win")
    }

    /// The set still resolves to one image for the callers that just want an
    /// icon, and that image is the largest member.
    func testBestIconStillReturnsTheLargestMember() throws {
        try assertPattern(try icon("icon-named-group-pe"), side: 32)
    }
}
