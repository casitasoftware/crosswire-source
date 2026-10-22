//
//  DisplayName.swift
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

/// Turns the names Windows software reports about itself into names a user
/// should read in the library.
///
/// There are two entry points because the inputs differ. A product name comes
/// from the vendor (VERSIONINFO, the uninstall registry, a Start Menu
/// shortcut) and is usually right, so it is only touched when it is plainly a
/// code identifier: `lotroLauncher` becomes `LOTRO Launcher`, while `7-Zip`
/// and `Notepad++` pass through untouched. An installer filename is a
/// placeholder shown while an install runs, and is aggressively stripped of
/// versions, architectures and installer words.
///
/// "Launcher" is deliberately not treated as noise: for many games the
/// launcher is the thing the user runs, and the word says so.
public enum DisplayName {

    /// Short game titles vendors write in lowercase inside identifiers. Keys
    /// are lowercase. Only titles whose correct casing cannot be inferred
    /// belong here; add to it when a real library shows one.
    static let knownTitles: [String: String] = [
        "lotro": "LOTRO",
        "ddo": "DDO",
        "swg": "SWG"
    ]

    /// Words that describe the installer, not the app.
    static let installerWords: Set<String> = ["setup", "installer", "install"]

    /// Build and platform words that appear in filenames but never in a title.
    static let buildWords: Set<String> = [
        "x64", "x86", "amd64", "arm64", "win32", "win64", "32bit", "64bit", "shipping"
    ]

    /// Cleans a vendor-supplied product name. Returns nil when there is
    /// nothing usable, so callers can fall through to another source.
    public static func fromProductName(_ raw: String) -> String? {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }

        let words: [String]
        var wasIdentifier = false
        if trimmed.contains(" ") {
            words = trimmed.split(separator: " ").map(String.init)
        } else {
            words = splitCamelCase(trimmed)
            wasIdentifier = words.count > 1
        }
        return assemble(words, drop: installerWords, capitalizeFirst: wasIdentifier) ?? trimmed
    }

    /// Cleans an installer's filename stem for use as a placeholder name.
    public static func fromInstallerFilename(_ raw: String) -> String? {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }

        let pieces = trimmed
            .split(whereSeparator: { ".-_ ".contains($0) })
            .map(String.init)
        var words: [String] = []
        var splitAny = false
        for piece in pieces {
            let parts = splitCamelCase(piece)
            splitAny = splitAny || parts.count > 1
            words.append(contentsOf: parts)
        }
        let kept = words.filter { !isVersion($0) }
        return assemble(kept, drop: installerWords.union(buildWords), capitalizeFirst: splitAny) ?? trimmed
    }

    // MARK: - Pieces

    /// Splits at lowercase-to-uppercase boundaries and at the end of an
    /// uppercase run: `lotroLauncher` -> [lotro, Launcher],
    /// `SWGLegendsSetup` -> [SWG, Legends, Setup]. Punctuation is never a
    /// boundary, so `7-Zip` and `Notepad++` stay whole. A single lowercase
    /// letter before a capital is a brand (`iTunes`, `eBay`), not a word.
    static func splitCamelCase(_ text: String) -> [String] {
        let chars = Array(text)
        var parts: [String] = []
        var current = ""
        for (index, char) in chars.enumerated() {
            if index > 0, !current.isEmpty {
                let previous = chars[index - 1]
                let next: Character? = index + 1 < chars.count ? chars[index + 1] : nil
                let lowerToUpper = previous.isLowercase && char.isUppercase
                let endOfAcronym = previous.isUppercase && char.isUppercase && (next?.isLowercase ?? false)
                let brandPrefix = parts.isEmpty && current.count == 1 && current.first?.isLowercase == true
                if (lowerToUpper || endOfAcronym) && !brandPrefix {
                    parts.append(current)
                    current = ""
                }
            }
            current.append(char)
        }
        if !current.isEmpty { parts.append(current) }
        return parts
    }

    /// `8`, `2603`, `1.2.3`, `v2`: a version or build number on its own.
    static func isVersion(_ word: String) -> Bool {
        var body = Substring(word)
        if body.first == "v" || body.first == "V" { body = body.dropFirst() }
        guard !body.isEmpty else { return false }
        return body.allSatisfy { $0.isNumber || $0 == "." }
    }

    /// Drops unwanted words, applies known title casing, and joins. Returns
    /// nil when nothing is left, so the caller can keep the original instead.
    private static func assemble(_ words: [String], drop: Set<String>, capitalizeFirst: Bool) -> String? {
        var kept = words.filter { !drop.contains($0.lowercased()) }
        guard !kept.isEmpty else { return nil }
        kept = kept.map { knownTitles[$0.lowercased()] ?? $0 }
        if capitalizeFirst, let first = kept.first, first == first.lowercased() {
            kept[0] = first.prefix(1).uppercased() + first.dropFirst()
        }
        return kept.joined(separator: " ")
    }
}
