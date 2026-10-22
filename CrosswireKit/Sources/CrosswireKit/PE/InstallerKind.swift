//
//  InstallerKind.swift
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

/// Whether an .exe is an installer, and which engine built it.
///
/// Crosswire needs this to avoid treating a failed installer as the app: when
/// an install leaves nothing to launch, a picked .exe that is itself a
/// portable app should be adopted, but an installer must not be. StarCraft's
/// SETUP.EXE, run off its disc, installed nothing and was then listed in the
/// library as an app called SETUP.
///
/// Installers identify themselves in one of three ways, checked in order:
/// the NSIS `.ndata` section, Inno Setup's "built with Inno Setup" comment,
/// or the word setup / install / installer in the description or filename.
/// The engine matters beyond this check: NSIS and Inno Setup both accept
/// documented silent-install flags.
public enum InstallerKind: Equatable, Sendable {
    case nsis
    case innoSetup
    /// Identified by its description or filename; engine unknown.
    case other

    static let installerWords: Set<String> = ["setup", "install", "installer"]

    /// Arguments that run this installer with no windows, accepting its
    /// defaults, or nil when there is no known silent mode.
    public var silentArguments: [String]? {
        switch self {
        case .nsis:
            return ["/S"]
        case .innoSetup:
            return ["/VERYSILENT", "/SUPPRESSMSGBOXES", "/NORESTART", "/SP-"]
        case .other:
            return nil
        }
    }

    public static func classify(fileName: String,
                                versionStrings: [String: String],
                                sectionNames: [String]) -> InstallerKind? {
        if sectionNames.contains(".ndata") { return .nsis }

        let comments = versionStrings["Comments"]?.lowercased() ?? ""
        if comments.contains("inno setup") { return .innoSetup }

        let description = versionStrings["FileDescription"] ?? ""
        let stem = (fileName as NSString).deletingPathExtension
        if containsInstallerWord(description) || containsInstallerWord(stem) { return .other }
        return nil
    }

    /// True when one of the words, as a whole word, is setup / install /
    /// installer. Splits on punctuation and on camel-case boundaries so
    /// `SWGLegendsSetup` and `npp.8.9.8.Installer` count but `Upsetupper`
    /// and "Reinstallation" do not.
    static func containsInstallerWord(_ text: String) -> Bool {
        text.split(whereSeparator: { !$0.isLetter && !$0.isNumber })
            .flatMap { DisplayName.splitCamelCase(String($0)) }
            .contains { installerWords.contains($0.lowercased()) }
    }
}

extension PEFile {
    /// Classifies this file with `InstallerKind.classify`.
    public var installerKind: InstallerKind? {
        InstallerKind.classify(fileName: url.lastPathComponent,
                               versionStrings: versionStrings(),
                               sectionNames: sections.map(\.name))
    }
}
