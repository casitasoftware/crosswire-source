//
//  PEIcon.swift
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

import AppKit
import ImageIO

/// Finds and decodes the icon Windows Explorer shows for an executable.
///
/// Explorer does not pick the largest icon in the file. It takes the FIRST
/// RT_GROUP_ICON in resource order (named groups sort before numbered ones)
/// and uses the members of that group. Everything else in RT_ICON belongs to
/// other groups: toolbar glyphs, file-type icons, about-box art. Picking the
/// tallest RT_ICON anywhere, which the old code did, chose 7zFM.exe's 110px
/// group-100 image over its real 32/48px app icon.
///
/// Decoding goes through ImageIO rather than a hand-written DIB decoder. An
/// RT_ICON payload is either a PNG, or a BITMAPINFOHEADER DIB of exactly the
/// shape an .ico file carries. Prefixing the DIB with a one-entry ICONDIR
/// turns it into a valid .ico, which ImageIO decodes at every bit depth, with
/// row padding, palettes and the AND transparency mask all handled.
enum PEIcon {
    static let rtIcon: UInt32 = 3
    static let rtGroupIcon: UInt32 = 14

    /// One member of a GRPICONDIR: the size and depth Explorer would compare,
    /// plus the RT_ICON id holding the pixels.
    struct GroupMember: Equatable {
        let width: Int
        let height: Int
        let bitCount: Int
        let iconID: UInt32
    }

    /// Parses a GRPICONDIR blob. A width or height byte of 0 means 256.
    static func parseGroup(_ data: Data) -> [GroupMember] {
        let bytes = [UInt8](data)
        guard bytes.count >= 6 else { return [] }
        let type = UInt16(bytes[2]) | UInt16(bytes[3]) << 8
        let count = Int(UInt16(bytes[4]) | UInt16(bytes[5]) << 8)
        guard type == 1 else { return [] }
        var members: [GroupMember] = []
        for index in 0..<count {
            let base = 6 + index * 14
            guard base + 14 <= bytes.count else { break }
            let width = bytes[base] == 0 ? 256 : Int(bytes[base])
            let height = bytes[base + 1] == 0 ? 256 : Int(bytes[base + 1])
            let bitCount = Int(UInt16(bytes[base + 6]) | UInt16(bytes[base + 7]) << 8)
            let iconID = UInt32(UInt16(bytes[base + 12]) | UInt16(bytes[base + 13]) << 8)
            members.append(GroupMember(width: width, height: height, bitCount: bitCount, iconID: iconID))
        }
        return members
    }

    /// Largest member first, then deepest colour, which is Explorer's
    /// preference when it has room to show the icon large.
    static func preferenceOrder(_ members: [GroupMember]) -> [GroupMember] {
        members.sorted { lhs, rhs in
            let lhsArea = lhs.width * lhs.height, rhsArea = rhs.width * rhs.height
            return lhsArea != rhsArea ? lhsArea > rhsArea : lhs.bitCount > rhs.bitCount
        }
    }

    /// Decodes one RT_ICON payload. PNG payloads (Vista-style 256px icons)
    /// pass straight through; DIB payloads are wrapped as a single-image .ico.
    static func decode(_ data: Data) -> NSImage? {
        let pngSignature: [UInt8] = [0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A]
        let payload = data.starts(with: pngSignature) ? data : wrapAsICO(data)
        guard let payload,
              let source = CGImageSourceCreateWithData(payload as CFData, nil),
              let cgImage = CGImageSourceCreateImageAtIndex(source, 0, nil) else { return nil }
        return NSImage(cgImage: cgImage, size: NSSize(width: cgImage.width, height: cgImage.height))
    }

    /// Wraps a decoded member as a bitmap representation whose own size is its
    /// pixel size, so `NSImage` treats the members as alternative sizes (what
    /// an .icns does) rather than as 1x/2x variants of one size.
    static func representation(from image: NSImage) -> NSBitmapImageRep? {
        guard let cgImage = image.cgImage(forProposedRect: nil, context: nil, hints: nil) else { return nil }
        let rep = NSBitmapImageRep(cgImage: cgImage)
        rep.size = NSSize(width: cgImage.width, height: cgImage.height)
        return rep
    }

    /// One representation per pixel size, deepest wins. A group routinely
    /// lists the same size at several depths (Notepad++ ships 48px at both 8
    /// and 32 bpp), and two representations of one size would leave AppKit
    /// picking between them arbitrarily.
    static func deepestPerSize(_ members: [GroupMember]) -> [GroupMember] {
        var best: [Int: GroupMember] = [:]
        for member in members {
            guard let existing = best[member.width] else { best[member.width] = member; continue }
            if member.bitCount > existing.bitCount { best[member.width] = member }
        }
        return best.values.sorted { $0.width < $1.width }
    }

    /// Decodes each member the group names and collects them into one set.
    /// Members whose pixels will not decode are skipped rather than failing
    /// the whole group.
    static func set(from members: [GroupMember], pixels: [UInt32: Data]) -> PEIconSet? {
        var reps: [NSBitmapImageRep] = []
        var maxBitCount = 0
        for member in deepestPerSize(members) {
            guard let data = pixels[member.iconID],
                  let decoded = decode(data),
                  let rep = representation(from: decoded) else { continue }
            reps.append(rep)
            maxBitCount = max(maxBitCount, member.bitCount)
        }
        return assemble(reps, maxBitCount: maxBitCount)
    }

    /// Collects representations into one image sized to the largest member.
    /// Returns nil for an empty set so callers move on to the next candidate
    /// executable rather than showing a blank plate.
    static func assemble(_ reps: [NSBitmapImageRep], maxBitCount: Int) -> PEIconSet? {
        guard let largest = reps.max(by: { $0.size.width < $1.size.width }) else { return nil }
        let image = NSImage(size: largest.size)
        for rep in reps { image.addRepresentation(rep) }
        return PEIconSet(image: image, maxBitCount: maxBitCount, maxPixelSize: largest.pixelsWide)
    }

    /// Builds a one-image .ico around a DIB. The DIB's BITMAPINFOHEADER holds
    /// the true width and a DOUBLED height (colour rows plus mask rows), which
    /// is also what an .ico's embedded image looks like, so the DIB bytes are
    /// used unchanged.
    static func wrapAsICO(_ dib: Data) -> Data? {
        let bytes = [UInt8](dib)
        guard bytes.count >= 40 else { return nil }
        func le32(_ offset: Int) -> Int32 {
            Int32(bitPattern: UInt32(bytes[offset]) | UInt32(bytes[offset + 1]) << 8
                | UInt32(bytes[offset + 2]) << 16 | UInt32(bytes[offset + 3]) << 24)
        }
        let headerSize = le32(0)
        guard headerSize >= 40 else { return nil }
        let width = Int(le32(4))
        let height = Int(abs(le32(8))) / 2
        let bitCount = Int(UInt16(bytes[14]) | UInt16(bytes[15]) << 8)
        guard width > 0, height > 0, width <= 256, height <= 256 else { return nil }

        var ico = Data()
        func append16(_ value: Int) { ico.append(contentsOf: [UInt8(value & 0xFF), UInt8((value >> 8) & 0xFF)]) }
        func append32(_ value: Int) {
            ico.append(contentsOf: (0..<4).map { UInt8((value >> ($0 * 8)) & 0xFF) })
        }
        append16(0)                                   // reserved
        append16(1)                                   // type: icon
        append16(1)                                   // one image
        ico.append(UInt8(width == 256 ? 0 : width))
        ico.append(UInt8(height == 256 ? 0 : height))
        ico.append(bitCount < 8 ? UInt8(1 << bitCount) : 0) // palette size, 0 when 8bpp+
        ico.append(0)                                 // reserved
        append16(1)                                   // planes
        append16(bitCount)
        append32(bytes.count)                         // bytes in resource
        append32(22)                                  // image data follows the 6+16 byte header
        ico.append(dib)
        return ico
    }
}

extension PEIcon {
    /// A minimal walk of the resource tree that, unlike `ResourceDirectoryTable`,
    /// keeps each entry's name or ID and does not skip named entries. Named
    /// entries come first in every directory, matching Windows' own order.
    /// One row of a resource directory.
    struct ResourceEntry {
        let named: Bool
        let id: UInt32
        let isDirectory: Bool
        /// Offset from the start of .rsrc: a subdirectory or a data entry.
        let target: UInt64
    }

    struct Tree {
        let handle: FileHandle
        let rsrcBase: UInt64
        let sections: [PEFile.Section]

        /// Entries of the directory at `offset`, in on-disk order: named first.
        func entries(atDirectory offset: UInt64) -> [ResourceEntry] {
            let base = rsrcBase + offset
            guard let named = handle.extract(UInt16.self, offset: base + 12),
                  let numbered = handle.extract(UInt16.self, offset: base + 14) else { return [] }
            let total = Int(named) + Int(numbered)
            guard total < 4096 else { return [] }   // guard against a corrupt count
            var result: [ResourceEntry] = []
            for index in 0..<total {
                let entry = base + 16 + UInt64(index * 8)
                guard let nameField = handle.extract(UInt32.self, offset: entry),
                      let dataField = handle.extract(UInt32.self, offset: entry + 4) else { break }
                result.append(ResourceEntry(named: nameField & 0x8000_0000 != 0,
                                    id: nameField & 0x7FFF_FFFF,
                                    isDirectory: dataField & 0x8000_0000 != 0,
                                    target: UInt64(dataField & 0x7FFF_FFFF)))
            }
            return result
        }

        /// Descends through subdirectories (name -> language) to the first data leaf.
        func firstLeaf(from entry: ResourceEntry, depth: Int = 0) -> Data? {
            if entry.isDirectory {
                guard depth < 4, let first = entries(atDirectory: entry.target).first else { return nil }
                return firstLeaf(from: first, depth: depth + 1)
            }
            guard let dataEntry = ResourceDataEntry(handle: handle, offset: rsrcBase + entry.target),
                  let fileOffset = dataEntry.resolveRVA(sections: sections),
                  dataEntry.size > 0, dataEntry.size < 16 * 1024 * 1024 else { return nil }
            do {
                try handle.seek(toOffset: UInt64(fileOffset))
                return try handle.read(upToCount: Int(dataEntry.size))
            } catch {
                return nil
            }
        }

        func typeDirectory(_ type: UInt32) -> ResourceEntry? {
            entries(atDirectory: 0).first { !$0.named && $0.id == type && $0.isDirectory }
        }
    }
}

/// Every decodable member of an executable's icon group, as one image.
///
/// An exe does not carry one icon, it carries a set: the same artwork drawn
/// again at each size it will be shown at, often by hand. A real library is
/// mostly 16 and 32 px art, so collapsing the set to its largest member and
/// letting the view scale meant a 22 pt list row drew a downscaled 256, which
/// is exactly where hand-tuned small art turns to mush.
///
/// `image` therefore carries one representation per member and lets AppKit
/// pick the closest one at draw time. `maxBitCount` is the deepest member's
/// colour depth, which drawing code needs because the two kinds of source art
/// have to be scaled differently: full-colour art is interpolated and stops at
/// 2x, palette art is nearest-neighbour at whole multiples up to 4x and then
/// stops growing rather than blurring.
/// Deliberately not `Sendable`: it holds an `NSImage`, which is not thread
/// safe. Build it on the thread that will draw it.
public struct PEIconSet {
    /// All members, one representation each, largest member's size as the
    /// image size.
    public let image: NSImage
    /// The deepest member's bits per pixel, from the group directory rather
    /// than the decoded bitmap: ImageIO hands back 32-bit RGBA whatever the
    /// source was, so the source depth has to be carried separately.
    public let maxBitCount: Int
    /// The largest member's pixel width.
    public let maxPixelSize: Int

    /// True when the whole set is palette art (8-bit or fewer). These scale by
    /// whole-number nearest-neighbour, never interpolated.
    public var isPalette: Bool { maxBitCount <= 8 }
}

extension PEFile {
    /// Every decodable member of the first RT_GROUP_ICON, as one image plus the
    /// colour depth drawing code needs. Falls back to the largest decodable
    /// RT_ICON when an exe has icons but no group. Returns nil when there is
    /// nothing decodable, never an empty image, so callers trying several
    /// candidate executables actually move on to the next one.
    public func iconSet() -> PEIconSet? {
        guard let handle = try? FileHandle(forReadingFrom: url) else { return nil }
        defer { try? handle.close() }
        guard let rsrcSection = sections.first(where: { $0.name == ".rsrc" }) else { return nil }
        let tree = PEIcon.Tree(handle: handle, rsrcBase: UInt64(rsrcSection.pointerToRawData), sections: sections)

        var iconsByID: [UInt32: Data] = [:]
        if let iconDir = tree.typeDirectory(PEIcon.rtIcon) {
            for entry in tree.entries(atDirectory: iconDir.target) where !entry.named {
                if let data = tree.firstLeaf(from: entry) { iconsByID[entry.id] = data }
            }
        }

        if let groupDir = tree.typeDirectory(PEIcon.rtGroupIcon),
           let firstGroup = tree.entries(atDirectory: groupDir.target).first,
           let groupData = tree.firstLeaf(from: firstGroup),
           let set = PEIcon.set(from: PEIcon.parseGroup(groupData), pixels: iconsByID) {
            return set
        }

        // No usable group: largest icon that decodes, on its own.
        guard let largest = iconsByID.values
            .compactMap(PEIcon.decode)
            .max(by: { $0.size.width * $0.size.height < $1.size.width * $1.size.height }),
            let rep = PEIcon.representation(from: largest) else { return nil }
        // Depth is unknown without a group directory. Treat it as full colour:
        // over-interpolating a palette icon is a softer failure than blocking
        // up a photographic one.
        return PEIcon.assemble([rep], maxBitCount: 32)
    }

    /// The executable's icon as a single image. Prefer `iconSet()` in new
    /// drawing code, which also reports the colour depth scaling depends on.
    public func bestIcon() -> NSImage? {
        iconSet()?.image
    }
}
